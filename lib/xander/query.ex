defmodule Xander.Query do
  @moduledoc """
  Issues ledger queries to a Cardano node using the Node-to-Client (n2c) protocol.
  This module implements the `gen_statem` OTP behaviour.
  """

  @behaviour :gen_statem

  alias Xander.Handshake
  alias Xander.Messages
  alias Xander.Query.Response
  alias Xander.Transport

  require Logger

  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16, 17]

  defstruct [:transport, :socket, :network, queue: :queue.new()]

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

  @doc """
  Starts a new query process.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(network: network, path: path, port: port, type: type) do
    transport = Transport.new(path: path, port: port, type: type)

    data = %__MODULE__{
      transport: transport,
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
        %__MODULE__{transport: transport} = data
      ) do
    case Transport.connect(transport) do
      {:ok, socket} ->
        data = %__MODULE__{data | socket: socket}
        actions = [{:next_event, :internal, :establish}]
        {:next_state, :connected, data, actions}

      {:error, reason} ->
        Logger.error("Error connecting to node #{inspect(reason)}")
        actions = [{:state_timeout, 5_000, :retry_connect}]
        {:keep_state, data, actions}
    end
  end

  def disconnected(:state_timeout, :retry_connect, data) do
    actions = [{:next_event, :internal, :connect}]
    {:keep_state, data, actions}
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
        %__MODULE__{transport: transport, socket: socket, network: network} = data
      ) do
    :ok =
      Transport.send(
        transport,
        socket,
        Handshake.Proposal.version_message(@active_n2c_versions, network)
      )

    case Transport.recv(transport, socket, 0, _timeout = 5_000) do
      {:ok, full_response} ->
        {:ok, _handshake_response} = Handshake.Response.validate(full_response)

        # Transitions to idle state
        {:next_state, :established_no_agency, data}

      {:error, reason} ->
        Logger.error("Error establishing connection #{inspect(reason)}")
        actions = [{:state_timeout, 5_000, :retry_connect}]
        {:next_state, :disconnected, data, actions}
    end
  end

  @doc """
  Emits events when in the `established_no_agency` state.
  This maps to the StIdle state in the Cardano Local State Query protocol.
  This is the state where the process waits for a query to be made.
  """
  def established_no_agency(_event_type, _event_content, _data)

  def established_no_agency(
        {:call, from},
        {:request, query_name},
        %__MODULE__{transport: transport, socket: socket} = data
      ) do
    # Send acquire message and handle response
    with :ok <- Transport.send(transport, socket, Messages.msg_acquire()),
         {:ok, _acquire_response} <- Transport.recv(transport, socket, 0, _timeout = 5_000),
         :ok <- Transport.setopts(transport, socket, active: :once) do
      # Track the caller and query_name, then transition to
      # established_has_agency state prior to sending the query.
      data = update_in(data.queue, &:queue.in({from, query_name}, &1))
      {:next_state, :established_has_agency, data, [{:next_event, :internal, :send_query}]}
    else
      {:error, :closed} ->
        Logger.error("Connection closed during acquire")

        actions = [
          {:reply, from, {:error, :disconnected}},
          {:state_timeout, 5_000, :retry_connect}
        ]

        data = %{data | socket: nil}
        {:next_state, :disconnected, data, actions}

      {:error, reason} ->
        Logger.error("Failed to acquire state: #{inspect(reason)}")
        actions = [{:reply, from, {:error, :acquire_failed}}]
        {:keep_state, data, actions}
    end
  end

  def established_no_agency(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in established_no_agency")
    data = %{data | socket: nil}
    actions = [{:state_timeout, 5_000, :retry_connect}]
    {:next_state, :disconnected, data, actions}
  end

  @doc """
  Emits events when in the `established_has_agency` state.
  This maps to the Querying state in the Cardano Local State Query protocol.
  """
  def established_has_agency(_event_type, _event_content, _data)

  def established_has_agency(
        {:call, from},
        {:request, request},
        %__MODULE__{queue: queue} = data
      ) do
    # Enqueue the new request (from is usually {pid, ref})
    new_queue = :queue.in({from, request}, queue)
    new_data = %{data | queue: new_queue}
    {:keep_state, new_data}
  end

  def established_has_agency(
        :internal,
        :send_query,
        %__MODULE__{transport: transport, socket: socket} = data
      ) do
    # Get the current query_name from queue without removing it
    {:value, {_from, query_name}} = :queue.peek(data.queue)

    # Set socket to active mode so we can receive the next response
    :ok = Transport.setopts(transport, socket, active: :once)

    # Send query to node and remain in established_has_agency state
    :ok = Transport.send(transport, socket, build_query_message(query_name))
    {:keep_state, data}
  end

  # This function is invoked due to the socket being set to active mode.
  # It receives a response from the node, processes the next query in the
  # queue, and either keeps or transitions its state depending on if the
  # queue is empty or not. More queries may be added to the queue while
  # in this state if they arrive in the process mailbox before the queue
  # is emptied.
  def established_has_agency(
        :info,
        {_tcp_or_ssl, socket, bytes},
        %__MODULE__{transport: transport, socket: socket} = data
      ) do
    # Parse query response (MsgResult)
    case Response.parse_response(bytes) do
      {:ok, query_response} ->
        handle_query_result({:ok, query_response}, data, transport, socket)

      {:error, reason} ->
        Logger.error("Failed to parse response: #{inspect(reason)}")
        handle_query_result({:error, :parse_failed}, data, transport, socket)
    end
  end

  def established_has_agency(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while querying")
    data = %{data | socket: nil}
    actions = [{:state_timeout, 5_000, :retry_connect}]
    {:next_state, :disconnected, data, actions}
  end

  def established_has_agency(:timeout, _event_content, data) do
    Logger.error("Query timeout")
    {:next_state, :established_no_agency, data}
  end

  defp build_query_message(query_name) do
    case query_name do
      :get_current_era -> Messages.get_current_era()
      :get_current_block_height -> Messages.get_current_block_height()
      :get_epoch_number -> Messages.get_epoch_number()
      :get_current_tip -> Messages.get_current_tip()
    end
  end

  defp handle_query_result(result, data, transport, socket) do
    case :queue.out(data.queue) do
      {{:value, {caller, _query_name}}, rest_queue} ->
        actions = [{:reply, caller, result}]

        if :queue.is_empty(rest_queue) do
          :ok = Transport.send(transport, socket, Messages.msg_release())
          new_data = %{data | queue: rest_queue}
          {:next_state, :established_no_agency, new_data, actions}
        else
          new_data = %{data | queue: rest_queue}
          {:keep_state, new_data, actions ++ [{:next_event, :internal, :send_query}]}
        end

      {:empty, _} ->
        :ok = Transport.send(transport, socket, Messages.msg_release())
        {:next_state, :established_no_agency, data, []}
    end
  end
end
