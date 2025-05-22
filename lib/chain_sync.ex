defmodule Xander.ChainSync do
  @behaviour :gen_statem

  @basic_transport_opts [:binary, active: false, send_timeout: 4_000]
  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16]

  alias Xander.ChainSync.Response, as: CSResponse
  # Investigate possibly extracting Handshake into a separate state machine.
  alias Xander.Handshake.Proposal
  alias Xander.Handshake.Response, as: HSResponse
  alias Xander.Messages
  alias Xander.Util

  require Logger

  defstruct [
    :client_module,
    :sync_from,
    :client,
    :path,
    :port,
    :socket,
    :network,
    queue: :queue.new(),
    state: %{}
  ]

  @doc """
  Starts a new query process.
  """
  def start_link(
        client_module,
        opts
      ) do
    {network, opts} = Keyword.pop(opts, :network)
    {path, opts} = Keyword.pop(opts, :path)
    {port, opts} = Keyword.pop(opts, :port)
    {type, opts} = Keyword.pop(opts, :type)
    # After removing all the options, the remaining options are the initial state
    # optionally given by the client of this module
    {sync_from, state} = Keyword.pop(opts, :sync_from, nil)

    data = %__MODULE__{
      client_module: client_module,
      sync_from: sync_from,
      client: transport(type),
      path: maybe_local_path(path, type),
      port: maybe_local_port(port, type),
      network: network,
      socket: nil,
      state: state
    }

    :gen_statem.start_link({:local, __MODULE__}, __MODULE__, data, [])
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(data) do
    actions = [{:next_event, :internal, :connect}]
    {:ok, :disconnected, data, actions}
  end

  @doc """
  Emits events when in the `disconnected` state.
  """
  def disconnected(
        :internal,
        :connect,
        %__MODULE__{client: client, path: path, port: port} = data
      ) do
    Logger.debug("Connecting to #{inspect(path)}")

    case client.connect(
           maybe_parse_path(path),
           port,
           transport_opts(client, path)
         ) do
      {:ok, socket} ->
        Logger.debug("Connected to #{inspect(path)}")
        data = %__MODULE__{data | socket: socket}
        actions = [{:next_event, :internal, :establish}]
        {:next_state, :connected, data, actions}

      {:error, reason} ->
        Logger.error("Error reaching socket #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  def disconnected({:call, from}, _command, data) do
    actions = [{:reply, from, {:error, :disconnected}}]
    {:keep_state, data, actions}
  end

  def connected(
        :internal,
        :establish,
        %__MODULE__{
          client: client,
          socket: socket,
          network: network
        } = data
      ) do
    Logger.debug("Establishing handshake...")

    version_message = Proposal.version_message(@active_n2c_versions, network)

    case propose_handshake(client, socket, version_message) do
      {:ok, _handshake_response} ->
        Logger.debug("Handshake successful")
        actions = [{:next_event, :internal, :find_intersection}]
        {:next_state, :catching_up, data, actions}

      {:error, reason} ->
        Logger.error("Error establishing handshake: #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  defp propose_handshake(client, socket, version_message) do
    with :ok <- client.send(socket, version_message),
         {:ok, full_response} <- client.recv(socket, 0, _timeout = 5_000),
         {:ok, handshake_response} <- HSResponse.validate(full_response) do
      {:ok, handshake_response}
    else
      {:refused, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def catching_up(
        :internal,
        :find_intersection,
        %__MODULE__{client: client, socket: socket, sync_from: sync_from} = data
      ) do
    :ok = client.send(socket, Messages.next_request())

    case client.recv(socket, 0, _timeout = 5_000) do
      {:ok, intersection_response} ->
        case CSResponse.parse_response(intersection_response) do
          {:ok, %CSResponse.RollBackward{tip: tip}} ->
            Logger.debug("First rollback: (#{tip.slot_number}, #{tip.hash})")

            {target_slot_number, target_block_hash, target_block_bytes} =
              case sync_from do
                :conway ->
                  # Last Babbage
                  {133_660_799,
                   "e757d57eb8dc9500a61c60a39fadb63d9be6973ba96ae337fd24453d4d15c343",
                   Base.decode16!(
                     "e757d57eb8dc9500a61c60a39fadb63d9be6973ba96ae337fd24453d4d15c343",
                     case: :lower
                   )}

                {slot_number, block_hash} ->
                  {slot_number, block_hash, Base.decode16!(block_hash, case: :lower)}

                _ ->
                  Logger.debug("Sync to tip")
                  {tip.slot_number, tip.hash, tip.bytes}
              end

            message = Messages.find_intersection(target_slot_number, target_block_bytes)
            :ok = client.send(socket, message)

            case client.recv(socket, 0, _timeout = 5_000) do
              {:ok, intersection_response} ->
                Logger.debug("Find intersection response successful")

                case CSResponse.parse_response(intersection_response) do
                  {:ok,
                   %CSResponse.IntersectFound{
                     point: [
                       ^target_slot_number,
                       %CBOR.Tag{tag: :bytes, value: ^target_block_bytes}
                     ],
                     tip: _tip
                   }} ->
                    Logger.debug(
                      "Intersection point is (#{target_slot_number}, #{target_block_hash})"
                    )

                    # Start the actual chainsync messages
                    actions = [{:next_event, :internal, :start_chain_sync}]
                    {:keep_state, data, actions}

                  {:error, _error} ->
                    Logger.debug("Intersection not found. Disconnecting.")
                    {:next_state, :disconnected, data}
                end

              {:error, reason} ->
                Logger.debug("Find intersection response failed: #{inspect(reason)}")
                {:next_state, :disconnected, data}
            end

          error ->
            Logger.debug("Next request response failed: #{inspect(error)}")
            {:next_state, :disconnected, data}
        end

      {:error, reason} ->
        Logger.debug("Next request response failed: #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  def catching_up(
        :internal,
        :start_chain_sync,
        %__MODULE__{client: client, socket: socket, client_module: client_module} = data
      ) do
    Logger.debug("starting chainsync")
    "ok banana" = start_chain_sync(client, socket, 0, client_module, data.state)
    {:next_state, :new_blocks, data}
  end

  def new_blocks(
        :info,
        {:tcp, socket, data},
        %__MODULE__{client: client, socket: socket, client_module: client_module, state: state} =
          module_state
      ) do
    Logger.debug("handling new block")

    %{payload: rest, size: payload_length} = Util.plex!(data)

    remaining_payload_length = payload_length - byte_size(rest)

    # This ensures that if the entire payload has been read sent in data,
    # we don't try to read anymore.
    read_remaining_payload = fn
      0 = _recv_payload_length ->
        {:ok, rest}

      recv_payload_length ->
        client.recv(socket, recv_payload_length, _timeout = 2_000)
    end

    case read_remaining_payload.(remaining_payload_length) do
      {:ok, payload} ->
        Logger.debug("read payload on new block")
        combined_payload = rest <> payload

        case CSResponse.decode(combined_payload) do
          {:ok, %CSResponse.RollForward{header: header}} ->
            Logger.debug("decoded block perfectly")

            case client_module.handle_block(
                   %{
                     block_number: header.block_number,
                     size: byte_size(header.bytes)
                   },
                   state
                 ) do
              {:ok, :next_block, _new_state} ->
                :ok = client.send(socket, Messages.next_request())

                {:ok, data} = client.recv(socket, 8, _timeout = 2_000)
                %{payload: rest, size: payload_length} = Util.plex!(data)

                remaining_payload_length = payload_length - byte_size(rest)
                {:ok, payload} = read_remaining_payload.(remaining_payload_length)

                case CSResponse.decode(payload) do
                  {:ok, %CSResponse.AwaitReply{}} ->
                    # Response should always be [1] msgAwaitReply
                    :ok = setopts_lib(client).setopts(socket, active: :once)
                    :keep_state_and_data

                  error ->
                    Logger.warning("Error decoding next request: #{inspect(error)}")
                    :keep_state_and_data
                end

              {:ok, :stop} ->
                {:next_state, :disconnected, module_state}
            end

          {:ok, %CSResponse.AwaitReply{}} ->
            :ok = setopts_lib(client).setopts(socket, active: :once)
            {:keep_state, module_state}

          {:ok, %CSResponse.RollBackward{point: point}} ->
            Logger.debug(
              "Calling client_module.handle_rollback with #{point.slot_number}, #{point.hash}"
            )

            case client_module.handle_rollback(
                   %{
                     slot_number: point.slot_number,
                     block_hash: point.hash
                   },
                   state
                 ) do
              {:ok, :next_block, _new_state} ->
                :ok = client.send(socket, Messages.next_request())
                :ok = setopts_lib(client).setopts(socket, active: :once)
                :keep_state_and_data

              {:ok, :stop} ->
                {:next_state, :disconnected, module_state}
            end

          {:error, _} ->
            # If decoding fails, try to read another message
            read_next_message_continue(
              client,
              socket,
              combined_payload,
              _possibly_remove_this = 666,
              client_module,
              state
            )

            :keep_state_and_data

          unknown_response ->
            Logger.debug("Unknown message: #{inspect(unknown_response)}")
        end

      {:error, reason} ->
        Logger.debug("Failed to read payload on new block: #{inspect(reason)}")
        :keep_state_and_data
    end
  end

  # As part of the chainsync process, this function emits msgRequestNext
  # and waits for a subsequent msgRollbackward
  defp start_chain_sync(client, socket, 0, client_module, state) do
    :ok = client.send(socket, Messages.next_request())
    {:ok, header_bytes} = client.recv(socket, 8, _timeout = 2_000)
    <<_timestamp::big-32, _mode::1, _protocol_id::15, payload_length::big-16>> = header_bytes

    case client.recv(socket, payload_length, _timeout = 2_000) do
      {:ok, payload} ->
        case CSResponse.decode(payload) do
          {:ok, %CSResponse.RollBackward{point: point}} ->
            Logger.debug("Rolling back to (#{point.slot_number}, #{point.hash})")

            :ok = client.send(socket, Messages.next_request())

            # Read the next message
            read_next_message(client, socket, 0, client_module, state)

          {:error, reason} ->
            Logger.warning("Error decoding payload: #{inspect(reason)}")

            :keep_state_and_data
        end

      {:error, reason} ->
        Logger.warning("Error reading socket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper function to read the next message
  defp read_next_message(client, socket, counter, client_module, state) do
    # Read the header (8 bytes)
    case client.recv(socket, 8, _timeout = 2_000) do
      {:ok, header_bytes} ->
        <<_timestamp::big-32, _mode::1, _protocol_id::15, payload_length::big-16>> = header_bytes

        case client.recv(socket, payload_length, _timeout = 2_000) do
          {:ok, payload} ->
            case CSResponse.decode(payload) do
              {:ok, %CSResponse.RollForward{header: header}} ->
                # This is the callback from the client module
                case client_module.handle_block(
                       %{
                         block_number: header.block_number,
                         size: byte_size(header.bytes)
                       },
                       state
                     ) do
                  {:ok, :next_block, _new_state} ->
                    :ok = client.send(socket, Messages.next_request())
                    read_next_message(client, socket, counter + 1, client_module, state)

                  {:ok, :stop} ->
                    :ok
                end

              {:ok, %CSResponse.AwaitReply{}} ->
                Logger.debug("Awaiting reply")
                :ok = setopts_lib(client).setopts(socket, active: :once)
                "ok banana"

              {:error, :incomplete_cbor_data} ->
                # If decoding fails, try to read another message
                read_next_message_continue(client, socket, payload, counter, client_module, state)
            end

          {:error, reason} ->
            Logger.debug("Failed to read payload: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.debug("Failed to read header: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper function to continue reading if the first attempt fails
  defp read_next_message_continue(client, socket, first_payload, counter, client_module, state) do
    # Read another header
    case client.recv(socket, 8, _timeout = 5_000) do
      {:ok, header_bytes} ->
        <<_timestamp::big-32, _mode::1, _protocol_id::15, payload_length::big-16>> = header_bytes

        # Read another payload
        case client.recv(socket, payload_length, _timeout = 5_000) do
          {:ok, second_payload} ->
            # Combine the payloads and try to decode
            combined_payload = first_payload <> second_payload

            case CSResponse.decode(combined_payload) do
              {:ok, %CSResponse.RollForward{header: header}} ->
                case client_module.handle_block(
                       %{
                         block_number: header.block_number,
                         size: byte_size(header_bytes)
                       },
                       state
                     ) do
                  {:ok, :next_block, _new_state} ->
                    :ok = client.send(socket, Messages.next_request())
                    read_next_message(client, socket, counter + 1, client_module, state)

                  {:ok, :stop} ->
                    :ok
                end

              {:error, :incomplete_cbor_data} ->
                read_next_message_continue(
                  client,
                  socket,
                  combined_payload,
                  counter,
                  client_module,
                  state
                )
            end

          {:error, reason} ->
            Logger.debug("Failed to read second payload: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.debug("Failed to read second header: #{inspect(reason)}")
        {:error, reason}
    end
  end

  ### Helper functions

  defp maybe_local_path(path, :socket), do: {:local, path}
  defp maybe_local_path(path, _), do: path

  defp maybe_local_port(_port, :socket), do: 0
  defp maybe_local_port(port, _), do: port

  defp maybe_parse_path(path) when is_binary(path) do
    uri = URI.parse(path)
    ~c"#{uri.host}"
  end

  defp maybe_parse_path(path), do: path

  defp transport(:ssl), do: :ssl
  defp transport(_), do: :gen_tcp

  defp setopts_lib(:ssl), do: :ssl
  defp setopts_lib(_), do: :inet

  defp transport_opts(:ssl, path),
    do:
      @basic_transport_opts ++
        [
          verify: :verify_none,
          server_name_indication: ~c"#{path}",
          secure_renegotiate: true
        ]

  defp transport_opts(_, _), do: @basic_transport_opts

  defmacro __using__(_opts) do
    quote do
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :temporary,
          shutdown: 5_000
        }
      end
    end
  end
end
