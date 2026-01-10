defmodule Xander.ChainSync do
  @behaviour :gen_statem

  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16]
  @recv_timeout 5_000

  @doc """
  Invoked when a new block is emitted. This callback is required.

  Receives block information as argument and the current state of the handler.

  Returning `{:ok, :next_block, new_state}` will request the next block once
  it's made available.

  Returning `{:close, new_state}` will close the connection to the node.
  """
  @callback handle_block(block :: map(), state) ::
              {:ok, :next_block, new_state}
              | {:close, new_state}
            when state: term(), new_state: term()

  @doc """
  Invoked when a rollback event is emitted. This callback is optional.

  Receives as argument a point and the state of the handler. The point is a
  map with keys for `id` (block id) and a `slot`. This information can then
  be used by the handler module to perform the necessary corrections.
  For example, resetting all current known state past this point and then
  rewriting it from future invokations of `c:handle_block/2`

  Returning `{:ok, :next_block, new_state}` will request the next block once
  it's made available. This is the only valid return value.
  """
  @callback handle_rollback(point :: map(), state) ::
              {:ok, :next_block, new_state}
            when state: term(), new_state: term()

  alias Xander.ChainSync.Intersection
  alias Xander.ChainSync.Ledger.IntersectionTarget
  alias Xander.ChainSync.Response, as: CSResponse
  alias Xander.ChainSync.Response.AwaitReply
  alias Xander.ChainSync.Response.IntersectFound
  alias Xander.ChainSync.Response.RollBackward
  alias Xander.ChainSync.Response.RollForward
  alias Xander.Transport

  # Investigate possibly extracting Handshake into a separate state machine.
  alias Xander.Handshake.Proposal
  alias Xander.Handshake.Response, as: HSResponse
  alias Xander.Messages
  alias Xander.Util

  require Logger

  defstruct [
    :client_module,
    :sync_from,
    :transport,
    :socket,
    :network,
    queue: :queue.new(),
    state: []
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

    transport = Transport.new(path: path, port: port, type: type)

    data = %__MODULE__{
      client_module: client_module,
      sync_from: sync_from,
      transport: transport,
      network: network,
      socket: nil,
      state: state
    }

    if sync_from && sync_from == :origin && network != :yaci_devkit do
      Logger.error(
        "Syncing from origin is only supported on the yaci_devkit network when create-node is used with the --era conway flag."
      )

      :ignore
    else
      :gen_statem.start_link({:local, __MODULE__}, __MODULE__, data, [])
    end
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
        %__MODULE__{transport: transport} = data
      ) do
    Logger.debug("Connecting...")

    case Transport.connect(transport) do
      {:ok, socket} ->
        Logger.debug("Connected")
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
          transport: transport,
          socket: socket,
          network: network
        } = data
      ) do
    Logger.debug("Establishing handshake...")

    version_message = Proposal.version_message(@active_n2c_versions, network)

    case propose_handshake(transport, socket, version_message) do
      {:ok, _handshake_response} ->
        Logger.debug("Handshake successful")
        actions = [{:next_event, :internal, :find_intersection}]
        {:next_state, :catching_up, data, actions}

      {:error, reason} ->
        Logger.error("Error establishing handshake: #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  defp propose_handshake(transport, socket, version_message) do
    with :ok <- Transport.send(transport, socket, version_message),
         {:ok, full_response} <- Transport.recv(transport, socket, 0, @recv_timeout),
         {:ok, handshake_response} <- HSResponse.validate(full_response) do
      {:ok, handshake_response}
    else
      {:refused, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The catching_up state is when the client is catching up to the tip of the chain.
  # In this state, it finds the intersection point and then starts reading the blocks
  # until it reaches the tip of the chain - this happens when the client receives
  # a msgAwaitReply response.
  @spec catching_up(:internal, :find_intersection | :start_chain_sync, %Xander.ChainSync{
          :transport => Transport.t(),
          :socket => any()
        }) ::
          :keep_state_and_data
          | {:keep_state,
             %Xander.ChainSync{
               :transport => Transport.t(),
               :socket => any(),
               :sync_from => any()
             }, [{any(), any(), any()}, ...]}
          | {:next_state, :disconnected | :new_blocks,
             %Xander.ChainSync{:transport => Transport.t(), :socket => any()}}
  def catching_up(
        :internal,
        :find_intersection,
        %__MODULE__{transport: transport, socket: socket, sync_from: sync_from} = data
      ) do
    with {:ok, %IntersectionTarget{slot: slot, block_bytes: block_bytes}} <-
           Intersection.find_target(transport, socket, sync_from),
         {:ok, %IntersectFound{}} <-
           Intersection.find_intersection(transport, socket, slot, block_bytes) do
      # Start the actual chainsync messages
      actions = [{:next_event, :internal, :start_chain_sync}]
      {:keep_state, data, actions}
    else
      {:error, reason} ->
        Logger.error("Find intersection failed: #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  def catching_up(
        :internal,
        :start_chain_sync,
        %__MODULE__{transport: transport, socket: socket, client_module: client_module} =
          data
      ) do
    Logger.debug("starting chainsync")

    emit_initial_next_message = fn transport, socket ->
      with :ok <- Transport.send(transport, socket, Messages.next_request()),
           {:ok, header_bytes} <- Transport.recv(transport, socket, 8, @recv_timeout),
           # TODO: use Util.plex!
           <<_timestamp::big-32, _mode::1, _protocol_id::15, payload_length::big-16>> <-
             header_bytes,
           {:ok, payload} <- Transport.recv(transport, socket, payload_length, @recv_timeout) do
        CSResponse.decode(payload)
      else
        {:error, reason} ->
          {:error, reason}
      end
    end

    case emit_initial_next_message.(transport, socket) do
      {:ok, %RollBackward{}} ->
        :ok = Transport.send(transport, socket, Messages.next_request())

        # Read the next message
        read_until_sync(transport, socket, client_module, data)
        {:next_state, :new_blocks, data}

      {:error, reason} ->
        Logger.warning("Error decoding payload: #{inspect(reason)}")
        :keep_state_and_data
    end
  end

  # Handle socket messages that arrive during the race condition window
  # between setting active mode and transitioning to new_blocks state
  def catching_up(
        :info,
        {_tcp_or_ssl, socket, data},
        %__MODULE__{
          transport: transport,
          # client: client,
          socket: socket,
          client_module: client_module,
          state: client_state
        } =
          module_state
      ) do
    Logger.debug(
      "Received socket message during catching_up state transition - handling gracefully"
    )

    %{payload: payload, size: payload_length} = Util.plex!(data)
    remaining_payload_length = payload_length - byte_size(payload)

    # This ensures that if the entire payload has been read sent in data,
    # we don't try to read anymore.
    read_remaining_payload = fn
      current_payload, 0 ->
        {:ok, current_payload}

      current_payload, recv_payload_length ->
        case Transport.recv(transport, socket, recv_payload_length, @recv_timeout) do
          {:ok, additional_payload} ->
            {:ok, current_payload <> additional_payload}

          {:error, reason} ->
            {:error, reason}
        end
    end

    case read_remaining_payload.(payload, remaining_payload_length) do
      {:ok, combined_payload} ->
        Logger.debug("read payload during state transition")

        case CSResponse.decode(combined_payload) do
          {:ok, %AwaitReply{}} ->
            # We're at the tip, transition to new_blocks and re-enable active mode
            :ok = Transport.setopts(transport, socket, active: :once)
            {:next_state, :new_blocks, module_state}

          {:ok, %RollForward{header: header}} ->
            Logger.debug("decoded block during transition")

            case client_module.handle_block(
                   %{
                     block_number: header.block_number,
                     size: header.block_body_size
                   },
                   client_state
                 ) do
              {:ok, :next_block, _new_state} ->
                :ok = Transport.send(transport, socket, Messages.next_request())
                :ok = Transport.setopts(transport, socket, active: :once)
                :keep_state_and_data

              {:close, _new_state} ->
                Logger.debug("Disconnecting from node")
                :ok = Transport.close(transport, socket)
                {:next_state, :disconnected, module_state}
            end

          {:ok, %RollBackward{point: point}} ->
            Logger.debug(
              "Calling client_module.handle_rollback during transition with #{point.slot_number}, #{point.hash}"
            )

            case client_module.handle_rollback(
                   %{
                     slot_number: point.slot_number,
                     block_hash: point.hash
                   },
                   client_state
                 ) do
              {:ok, :next_block, _new_state} ->
                :ok = Transport.send(transport, socket, Messages.next_request())
                :ok = Transport.setopts(transport, socket, active: :once)
                :keep_state_and_data
            end

          {:error, _} ->
            # If decoding fails, try to read another message
            read_next_message_continue(
              transport,
              socket,
              combined_payload,
              client_module,
              client_state
            )

            :ok = Transport.setopts(transport, socket, active: :once)
            :keep_state_and_data

          unknown_response ->
            Logger.debug("Unknown message during transition: #{inspect(unknown_response)}")
            :ok = Transport.setopts(transport, socket, active: :once)
            :keep_state_and_data
        end

      {:error, reason} ->
        Logger.debug("Failed to read payload during transition: #{inspect(reason)}")
        :ok = Transport.setopts(transport, socket, active: :once)
        :keep_state_and_data
    end
  end

  # Handle socket close/error events during catching_up state
  def catching_up(:info, {tcp_or_ssl_closed, _socket}, module_state)
      when tcp_or_ssl_closed in [:tcp_closed, :ssl_closed] do
    Logger.warning("Socket closed during catching_up state transition")
    {:next_state, :disconnected, module_state}
  end

  def catching_up(:info, {tcp_or_ssl_error, _socket, reason}, module_state)
      when tcp_or_ssl_error in [:tcp_error, :ssl_error] do
    Logger.error("Socket error during catching_up state transition: #{inspect(reason)}")
    {:next_state, :disconnected, module_state}
  end

  # The new_blocks state is when the client has caught up to the tip of the chain
  # and passively receives new blocks from the node after msgAwaitReply responses.
  def new_blocks(
        :info,
        {_tcp_or_ssl, socket, data},
        %__MODULE__{
          transport: transport,
          socket: socket,
          client_module: client_module,
          state: state
        } =
          module_state
      ) do
    Logger.debug("handling new block")

    %{payload: payload, size: payload_length} = Util.plex!(data)
    remaining_payload_length = payload_length - byte_size(payload)

    # This ensures that if the entire payload has been read sent in data,
    # we don't try to read anymore.
    read_remaining_payload = fn
      current_payload, 0 ->
        {:ok, current_payload}

      current_payload, recv_payload_length ->
        case Transport.recv(transport, socket, recv_payload_length, @recv_timeout) do
          {:ok, additional_payload} ->
            {:ok, current_payload <> additional_payload}

          {:error, reason} ->
            {:error, reason}
        end
    end

    case read_remaining_payload.(payload, remaining_payload_length) do
      {:ok, combined_payload} ->
        Logger.debug("read payload on new block")

        case CSResponse.decode(combined_payload) do
          {:ok, %AwaitReply{}} ->
            :ok = Transport.setopts(transport, socket, active: :once)
            :keep_state_and_data

          {:ok, %RollForward{header: header}} ->
            Logger.debug("decoded block perfectly")

            case client_module.handle_block(
                   %{
                     block_number: header.block_number,
                     size: header.block_body_size
                   },
                   state
                 ) do
              {:ok, :next_block, new_state} ->
                :ok = Transport.send(transport, socket, Messages.next_request())

                {:ok, data} = Transport.recv(transport, socket, 8, @recv_timeout)
                %{payload: payload, size: payload_length} = Util.plex!(data)
                remaining_payload_length = payload_length - byte_size(payload)

                {:ok, combined_payload} =
                  read_remaining_payload.(payload, remaining_payload_length)

                case CSResponse.decode(combined_payload) do
                  {:ok, %AwaitReply{}} ->
                    # Response should always be [1] msgAwaitReply
                    :ok = Transport.setopts(transport, socket, active: :once)
                    {:keep_state, %{module_state | state: new_state}}

                  error ->
                    Logger.warning("Error decoding next request: #{inspect(error)}")
                    {:keep_state, %{module_state | state: new_state}}
                end

              {:close, new_state} ->
                Logger.debug("Disconnecting from node")
                :ok = Transport.close(transport, socket)
                {:next_state, :disconnected, %{module_state | state: new_state}}
            end

          {:ok, %RollBackward{point: point}} ->
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
              {:ok, :next_block, new_state} ->
                :ok = Transport.send(transport, socket, Messages.next_request())
                :ok = Transport.setopts(transport, socket, active: :once)
                {:keep_state, %{module_state | state: new_state}}

              {:ok, :stop} ->
                {:next_state, :disconnected, module_state}
            end

          {:error, _} ->
            # If decoding fails, try to read another message
            read_next_message_continue(
              transport,
              socket,
              combined_payload,
              client_module,
              state
            )

            :keep_state_and_data

          unknown_response ->
            Logger.debug("Unknown message: #{inspect(unknown_response)}")
            :keep_state_and_data
        end

      {:error, reason} ->
        Logger.debug("Failed to read payload on new block: #{inspect(reason)}")
        :keep_state_and_data
    end
  end

  # Helper function to read the next message
  defp read_until_sync(transport, socket, client_module, state) do
    # Read the header (8 bytes)
    case Transport.recv(transport, socket, 8, @recv_timeout) do
      {:ok, header_bytes} ->
        # TODO: use Util.plex!
        <<_timestamp::big-32, _mode::1, _protocol_id::15, payload_length::big-16>> = header_bytes

        case Transport.recv(transport, socket, payload_length, @recv_timeout) do
          {:ok, payload} ->
            case CSResponse.decode(payload) do
              # When we receive a msgAwaitReply, this means we have reached
              # the tip and are done with the sync.
              {:ok, %AwaitReply{}} ->
                Logger.debug("Awaiting reply")
                # This is the base case of the recursion and the function no
                # longer recurses. It sets the socket to active mode so that
                # data ingestion continues from the "new_blocks" state.
                # The state transition from the "catching up" state to
                # "new_blocks" state occurs in the caller of this function.

                # TODO: address race condition that takes place in case the
                # node replies after socket is set to active but before the
                # client has transitioned to the new state.
                :ok = Transport.setopts(transport, socket, active: :once)

              {:ok, %RollForward{header: header}} ->
                # This is the callback from the client module
                case client_module.handle_block(
                       %{
                         block_number: header.block_number,
                         size: header.block_body_size
                       },
                       state
                     ) do
                  {:ok, :next_block, new_state} ->
                    :ok = Transport.send(transport, socket, Messages.next_request())
                    read_until_sync(transport, socket, client_module, new_state)

                  {:close, new_state} ->
                    Logger.debug("Disconnecting from node")
                    :ok = Transport.close(transport, socket)
                    {:next_state, :disconnected, new_state}
                end

              {:error, :incomplete_cbor_data} ->
                # If decoding fails, try to read another message
                read_next_message_continue(transport, socket, payload, client_module, state)
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
  defp read_next_message_continue(transport, socket, first_payload, client_module, state) do
    # Read another header
    case Transport.recv(transport, socket, 8, @recv_timeout) do
      {:ok, header_bytes} ->
        # TODO: use Util.plex!
        <<_timestamp::big-32, _mode::1, _protocol_id::15, payload_length::big-16>> = header_bytes

        # Read another payload
        case Transport.recv(transport, socket, payload_length, @recv_timeout) do
          {:ok, second_payload} ->
            # Combine the payloads and try to decode
            combined_payload = first_payload <> second_payload

            case CSResponse.decode(combined_payload) do
              {:ok, %RollForward{header: header}} ->
                case client_module.handle_block(
                       %{
                         block_number: header.block_number,
                         size: header.block_body_size
                       },
                       state
                     ) do
                  {:ok, :next_block, new_state} ->
                    :ok = Transport.send(transport, socket, Messages.next_request())
                    read_until_sync(transport, socket, client_module, new_state)

                  {:ok, :stop} ->
                    :ok
                end

              {:error, :incomplete_cbor_data} ->
                read_next_message_continue(
                  transport,
                  socket,
                  combined_payload,
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

  defmacro __using__(_opts) do
    quote do
      @behaviour Xander.ChainSync

      def handle_rollback(_point, state), do: {:ok, :next_block, state}
      defoverridable handle_rollback: 2

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
