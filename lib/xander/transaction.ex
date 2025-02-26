defmodule Xander.Transaction do
  @moduledoc """
  Submits transactions to a Cardano node using the Node-to-Client (n2c) protocol.
  """

  @behaviour :gen_statem

  alias Xander.Handshake
  alias Xander.Messages
  alias Xander.Query.Response

  require Logger

  @basic_tcp_opts [:binary, active: false, send_timeout: 4_000]
  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16]

  defstruct [:client, :path, :port, :socket, :network, queue: :queue.new()]

  ##############
  # Public API #
  ##############

  @doc """
  Sends a query to the connected Cardano node.

  Available queries are:

    * `:get_current_era`
    * `:get_current_block_height`
    * `:get_epoch_number`
    * `:get_current_tip`

  For example:

  ```elixir
  Xander.Query.run(pid, :get_epoch_number)
  ```
  """
  @spec run(pid() | atom(), atom()) :: {atom(), any()}
  def run(pid \\ __MODULE__, query_name) do
    :gen_statem.call(pid, {:request, query_name})
  end

  # def send(pid \\ __MODULE__, :send_tx, tx_hash) do
  #   :gen_statem.call(pid, {:request, :send_tx, tx_hash})
  # end

  @doc """
  Sends a transaction to the connected Cardano node.

  For example:

  ```elixir
  Xander.Query.run(pid, :get_epoch_number)
  ```
  """
  def send(pid \\ __MODULE__, tx_hash) do
    :gen_statem.call(pid, {:request, :send_tx, tx_hash})
  end

  @doc """
  Starts a new query process.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(network: network, path: path, port: port, type: type) do
    data = %__MODULE__{
      client: tcp_lib(type),
      path: maybe_local_path(path, type),
      port: maybe_local_port(port, type),
      network: network,
      socket: nil
    }

    :gen_statem.start_link({:local, __MODULE__}, __MODULE__, data, [])
  end

  #############
  # Callbacks #
  #############

  @doc """
  Returns a child specification for the process. This determines the
  configuration of the OTP process when it is started by its parent.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
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
  def disconnected(_event_type, _event_content, _data)

  def disconnected(
        :internal,
        :connect,
        %__MODULE__{client: client, path: path, port: port} = data
      ) do
    case client.connect(
           maybe_parse_path(path),
           port,
           tcp_opts(client, path)
         ) do
      {:ok, socket} ->
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

  @doc """
  Emits events when in the `connected` state. Must transition to the
  `established_has_agency` state prior to sending queries to the node.
  """
  def connected(_event_type, _event_content, _data)

  def connected(
        :internal,
        :establish,
        %__MODULE__{client: client, socket: socket, network: network} = data
      ) do
    :ok =
      client.send(
        socket,
        Handshake.Proposal.version_message(@active_n2c_versions, network)
      )

    case client.recv(socket, 0, _timeout = 5_000) do
      {:ok, full_response} ->
        case Handshake.Response.validate(full_response) do
          {:ok, _handshake_response} ->
            dbg("CONNECTED")
            # Transitions to idle state
            {:next_state, :idle, data}

          {:refused, response} ->
            Logger.error("Handshake refused by node. Response: #{inspect(response)}")

            Logger.error(
              "Check if network magic (#{inspect(network)}) and versions #{inspect(@active_n2c_versions)} are correct"
            )

            {:next_state, :disconnected, data}
        end

      {:error, reason} ->
        Logger.error("Error establishing connection #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  def busy(_event_type, _event_content, _data)

  def busy(
        :internal,
        {:send_tx, tx_hex},
        %__MODULE__{client: client, socket: socket} = data
      ) do
    :ok = client.send(socket, Messages.transaction(tx_hex))

    dbg("SENT TX")
    # Handle acquire response (MsgAcquired) to transition to Acquired state
    case client.recv(socket, 0, _timeout = 5_000) do
      {:ok, tx_response} ->
        # TODO: parse response
        # Set socket to active mode to receive async messages from node
        :ok = setopts_lib(client).setopts(socket, active: :once)

        IO.inspect("Transaction submitted successfully")

        dbg(tx_response)
        {:next_state, :idle, data}

      {:error, reason} ->
        Logger.error("Failed to acquire state: #{inspect(reason)}")
        # actions = [{:reply, from, {:error, :acquire_failed}}]
        actions = [{:reply, "", {:error, :acquire_failed}}]
        {:keep_state, data, actions}
    end
  end

  def busy(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in busy")
    {:next_state, :disconnected, data}
  end

  def busy(:info, {_tcp_or_ssl, socket, bytes}, %__MODULE__{socket: socket} = data) do
    case Response.parse_response(bytes) do
      {:ok, _response} ->
        # Handle successful transaction submission
        {:next_state, :idle, data}

      {:error, reason} ->
        Logger.error("Transaction submission failed: #{inspect(reason)}")
        {:next_state, :idle, data}
    end
  end

  @doc """
  Emits events when in the `idle` state.
  This maps to the StIdle state in the Cardano Local State Query protocol.
  This is the state where the process waits for a query to be made.
  """
  def idle(_event_type, _event_content, _data)

  def idle(
        {:call, _from},
        {:request, :send_tx, tx_hash},
        %__MODULE__{client: _client, socket: _socket} = data
      ) do
    dbg("idle CALL")
    dbg(tx_hash)
    {:next_state, :busy, data, [{:next_event, :internal, {:send_tx, tx_hash}}]}
  end

  def idle(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in idle")
    {:next_state, :disconnected, data}
  end

  defp maybe_local_path(path, :socket), do: {:local, path}
  defp maybe_local_path(path, _), do: path

  defp maybe_local_port(_port, :socket), do: 0
  defp maybe_local_port(port, _), do: port

  defp maybe_parse_path(path) when is_binary(path) do
    uri = URI.parse(path)
    ~c"#{uri.host}"
  end

  defp maybe_parse_path(path), do: path

  defp tcp_lib(:ssl), do: :ssl
  defp tcp_lib(_), do: :gen_tcp

  defp tcp_opts(:ssl, path),
    do:
      @basic_tcp_opts ++
        [
          verify: :verify_none,
          server_name_indication: ~c"#{path}",
          secure_renegotiate: true
        ]

  defp tcp_opts(_, _), do: @basic_tcp_opts

  defp setopts_lib(:ssl), do: :ssl
  defp setopts_lib(_), do: :inet
end
