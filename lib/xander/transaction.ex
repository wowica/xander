defmodule Xander.Transaction do
  @moduledoc """
  Submits transactions to a Cardano node using the Node-to-Client (n2c) protocol.
  """

  @behaviour :gen_statem

  alias Xander.Handshake
  alias Xander.Messages
  alias Xander.Transaction.Response

  require Logger

  @basic_tcp_opts [:binary, active: false, send_timeout: 4_000]
  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16, 17]

  defstruct [:client, :path, :port, :socket, :network, queue: :queue.new()]

  @typedoc """
  Type defining the Transaction struct.
  """
  @type t :: %__MODULE__{
          client: atom(),
          path: any(),
          port: non_neg_integer() | 0,
          socket: any(),
          network: any(),
          queue: :queue.queue()
        }

  ##############
  # Public API #
  ##############

  @doc """
  Sends a transaction to the connected Cardano node.

  For example:

  ```elixir
  Xander.Transaction.send(tx_hash)
  ```
  """
  @spec send(atom() | pid(), binary()) :: :ok | {:error, atom()}
  def send(pid \\ __MODULE__, tx_hash) do
    :gen_statem.call(pid, {:request, :send_tx, tx_hash})
  end

  @doc """
  Starts a new transaction process.
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
  @spec child_spec(Keyword.t()) :: %{
          :id => atom(),
          :start => {atom(), atom(), Keyword.t()},
          :type => atom(),
          :restart => atom(),
          :shutdown => integer()
        }
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
  @spec init(Keyword.t()) ::
          {:ok, :disconnected, Keyword.t(), [{:next_event, :internal, :connect}]}
  def init(data) do
    actions = [{:next_event, :internal, :connect}]
    {:ok, :disconnected, data, actions}
  end

  @doc """
  Emits events when in the `disconnected` state.
  """
  @spec disconnected(:info | :internal | {:call, any()}, any(), t()) ::
          {:next_state, :disconnected, t()}
          | {:next_state, :connected, t(), [{:next_event, :internal, :establish}]}
          | {:keep_state, t(), [{:reply, any(), {:error, :disconnected}}]}
  def disconnected(
        :internal,
        :connect,
        %__MODULE__{client: client, path: path, port: port} = data
      ) do
    Logger.info("Connecting to #{inspect(path)}:#{inspect(port)}")

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
  `idle` state prior to sending queries to the node.
  """
  @spec connected(:info | :internal, :establish | any(), t()) ::
          {:next_state, :disconnected, t()}
          | {:next_state, :idle, t()}
  def connected(
        :internal,
        :establish,
        %__MODULE__{client: client, socket: socket, network: network} = data
      ) do
    Logger.info("Establishing handshake...")

    :ok =
      client.send(
        socket,
        Handshake.Proposal.version_message(@active_n2c_versions, network)
      )

    case client.recv(socket, 0, _timeout = 5_000) do
      {:ok, full_response} ->
        case Handshake.Response.validate(full_response) do
          {:ok, _handshake_response} ->
            # Transitions to idle state
            Logger.info("Handshake successful")
            {:next_state, :idle, data}

          {:refused, response} ->
            Logger.error("Handshake refused by node. Response: #{inspect(response)}")

            {:next_state, :disconnected, data}
        end

      {:error, reason} ->
        Logger.error("Error establishing connection #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  @spec busy(
          :info | :internal | {:call, any()},
          {:request, atom(), atom()} | {:tcp_closed, any()},
          t()
        ) ::
          {:next_state, :disconnected, t()}
          | {:next_state, :disconnected | :idle, t(), [{:reply, any(), {:error | :ok, any()}}]}
          | {:keep_state, t(), [{:next_event, :internal, :send_tx}]}
  def busy(_event_type, _event_content, _data)

  # Handle internal event to send a transaction (from idle state)
  def busy(
        :internal,
        :send_tx,
        %__MODULE__{client: client, socket: socket} = data
      ) do
    # Get the current transaction from queue without removing it
    {:value, {_from, tx_hash}} = :queue.peek(data.queue)

    # Set socket to active mode before sending to be ready to receive response
    :inet.setopts(socket, active: :once)

    # Send transaction to node and remain in busy state
    :ok = client.send(socket, Messages.transaction(tx_hash))

    {:keep_state, data}
  end

  def busy(:info, {:tcp_closed, _socket}, %__MODULE__{socket: _data_socket} = data) do
    Logger.error("Connection closed while in busy")
    {:next_state, :disconnected, data}
  end

  def busy(:info, {:tcp_error, _socket, reason}, %__MODULE__{socket: _data_socket} = data) do
    Logger.error("Connection error while in busy: #{inspect(reason)}")
    {:next_state, :disconnected, data}
  end

  # This function is invoked due to the socket being set to active mode.
  # Handles the response while in busy state.
  def busy(
        :info,
        {_tcp_or_ssl, _socket, bytes},
        %__MODULE__{} = data
      ) do
    case Response.parse_response(bytes) do
      {:ok, response} ->
        process_queue_item(data, {:ok, response})

      {:rejected, reason} ->
        process_queue_item(data, {:rejected, reason})

      {:error, reason} ->
        Logger.error("Failed to parse response: #{inspect(reason)}")
        process_queue_item(data, {:error, :parse_failed})
    end
  end

  @doc """
  Emits events when in the `idle` state.
  This maps to the StIdle state in the Cardano Local State Query protocol.
  This is the state where the process waits for a query to be made and the
  queue is empty.
  """
  @spec idle(
          :info | :internal | {:call, any()},
          {:request, atom(), atom()} | {:tcp_closed, any()},
          t()
        ) ::
          {:next_state, :disconnected, t()}
          | {:next_state, :busy, t(), [{:next_event, :internal, :send_tx}]}
  def idle(_event_type, _event_content, _data)

  # Handle call from dependent process to send a transaction
  def idle(
        {:call, from},
        {:request, :send_tx, tx_hash},
        %__MODULE__{client: _client, socket: _socket} = data
      ) do
    # Track the caller and transaction in our queue. A queue is kept to handle
    # transactions that are sent from the dependent process while the current
    # transaction is being processed.
    data = update_in(data.queue, &:queue.in({from, tx_hash}, &1))

    {:next_state, :busy, data, [{:next_event, :internal, :send_tx}]}
  end

  # Handle socket closure in idle state
  def idle(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in idle")
    {:next_state, :disconnected, data}
  end

  defp process_queue_item(data, result) do
    {{:value, {caller, _tx_hash}}, new_data} = get_and_update_in(data.queue, &:queue.out/1)
    actions = [{:reply, caller, result}]
    next_state = if :queue.is_empty(new_data.queue), do: :idle, else: :busy
    {:next_state, next_state, new_data, actions}
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
end
