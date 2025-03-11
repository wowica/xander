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

  defstruct [:client, :path, :port, :socket, :network, :caller, queue: :queue.new()]

  @typedoc """
  Type defining the Transaction struct.
  """
  @type t :: %__MODULE__{
          client: atom(),
          path: any(),
          port: non_neg_integer() | 0,
          socket: any(),
          network: any(),
          caller: any(),
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
  `established_has_agency` state prior to sending queries to the node.
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

  @spec busy(:info | :internal, {:send_tx, binary()} | {:tcp_closed, any()}, t()) ::
          {:next_state, :disconnected, t()}
          | {:next_state, :disconnected | :idle, t(), [{:reply, any(), {:error | :ok, any()}}]}
  def busy(_event_type, _event_content, _data)

  def busy(
        :internal,
        {:send_tx, tx_hex},
        %__MODULE__{client: client, socket: socket, caller: from} = data
      ) do
    :ok = setopts_lib(client).setopts(socket, active: :once)

    :ok = client.send(socket, Messages.transaction(tx_hex))

    {next_state, actions} =
      case client.recv(socket, 0, _timeout = 5_000) do
        {:ok, tx_response} ->
          handle_tx_response(tx_response, from)

        {:error, reason} ->
          Logger.error("Failed to send transaction: #{inspect(reason)}")
          # Reply to caller with error
          actions = [{:reply, from, {:error, {:send_failed, reason}}}]

          {:idle, actions}
      end

    data = Map.delete(data, :caller)
    {:next_state, next_state, data, actions}
  end

  def busy(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in busy")
    {:next_state, :disconnected, data}
  end

  @doc """
  Emits events when in the `idle` state.
  This maps to the StIdle state in the Cardano Local State Query protocol.
  This is the state where the process waits for a query to be made.
  """
  @spec idle(
          :info | :internal | {:call, any()},
          {:request, atom(), atom()} | {:tcp_closed, any()},
          t()
        ) ::
          {:next_state, :disconnected, t()}
          | {:next_state, :busy, t(), [{:next_event, :internal, {:send_tx, binary()}}]}
  def idle(_event_type, _event_content, _data)

  def idle(
        {:call, from},
        {:request, :send_tx, tx_hash},
        %__MODULE__{client: _client, socket: _socket} = data
      ) do
    # Store the caller in data and don't reply immediately
    data = Map.put(data, :caller, from)

    {:next_state, :busy, data, [{:next_event, :internal, {:send_tx, tx_hash}}]}
  end

  def idle(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in idle")
    {:next_state, :disconnected, data}
  end

  defp handle_tx_response(tx_response, from) do
    case Response.parse_response(tx_response) do
      {:ok, :accepted} ->
        Logger.info("Transaction submitted successfully")

        actions = [{:reply, from, {:ok, :accepted}}]
        {:idle, actions}

      {:ok, :disconnected} ->
        Logger.info(~c"ltMsgDone message received from protocol.")

        actions = [{:reply, from, {:error, {:disconnected, :disconnected}}}]
        {:disconnected, actions}

      {:ok, {:rejected, failure_reason}} ->
        Logger.error("Transaction submission failed. Reason: #{inspect(failure_reason)}")

        actions = [{:reply, from, {:error, {:rejected, failure_reason}}}]
        {:idle, actions}

      {:error, error} ->
        Logger.error("Failed to decode transaction response: #{inspect(error)}")

        actions = [{:reply, from, {:error, {:decode_failed, error}}}]
        {:idle, actions}
    end
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
