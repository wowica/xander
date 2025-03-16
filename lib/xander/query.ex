defmodule Xander.Query do
  @moduledoc """
  Issues ledger queries to a Cardano node using the Node-to-Client (n2c) protocol.
  This module implements the `gen_statem` OTP behaviour.
  """

  @behaviour :gen_statem

  alias Xander.Handshake
  alias Xander.Messages
  alias Xander.Query.Response

  require Logger

  @basic_tcp_opts [:binary, active: false, send_timeout: 4_000]
  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16, 17]

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
        {:ok, _handshake_response} = Handshake.Response.validate(full_response)

        # Transitions to idle state
        {:next_state, :established_no_agency, data}

      {:error, reason} ->
        Logger.error("Error establishing connection #{inspect(reason)}")
        {:next_state, :disconnected, data}
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
        %__MODULE__{client: client, socket: socket} = data
      ) do
    # Send acquire message to transition to Acquiring state
    :ok = client.send(socket, Messages.msg_acquire())

    # Handle acquire response (MsgAcquired) to transition to Acquired state
    case client.recv(socket, 0, _timeout = 5_000) do
      {:ok, _acquire_response} ->
        # Set socket to active mode to receive async messages from node
        :ok = setopts_lib(client).setopts(socket, active: :once)

        # Track the caller and query_name, then transition to
        # established_has_agency state prior to sending the query.
        data = update_in(data.queue, &:queue.in({from, query_name}, &1))
        {:next_state, :established_has_agency, data, [{:next_event, :internal, :send_query}]}

      {:error, reason} ->
        Logger.error("Failed to acquire state: #{inspect(reason)}")
        actions = [{:reply, from, {:error, :acquire_failed}}]
        {:keep_state, data, actions}
    end
  end

  def established_no_agency(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while in established_no_agency")
    {:next_state, :disconnected, data}
  end

  @doc """
  Emits events when in the `established_has_agency` state.
  This maps to the Querying state in the Cardano Local State Query protocol.
  """
  def established_has_agency(_event_type, _event_content, _data)

  def established_has_agency(
        :internal,
        :send_query,
        %__MODULE__{client: client, socket: socket} = data
      ) do
    # Get the current query_name from queue without removing it
    {:value, {_from, query_name}} = :queue.peek(data.queue)

    # Send query to node and remain in established_has_agency state
    :ok = client.send(socket, build_query_message(query_name))
    {:keep_state, data}
  end

  # This function is invoked due to the socket being set to active mode.
  # It receives a response from the node, sends a release message and
  # then transitions back to the established_no_agency state.
  def established_has_agency(
        :info,
        {_tcp_or_ssl, socket, bytes},
        %__MODULE__{client: client, socket: socket} = data
      ) do
    # Parse query response (MsgResult)
    case Response.parse_response(bytes) do
      {:ok, query_response} ->
        # Get the caller from our queue
        {{:value, {caller, _query_name}}, new_data} = get_and_update_in(data.queue, &:queue.out/1)

        # Send release message to transition back to StIdle
        :ok = client.send(socket, Messages.msg_release())

        # Reply to caller and transition back to established_no_agency (StIdle)
        actions = [{:reply, caller, {:ok, query_response}}]
        {:next_state, :established_no_agency, new_data, actions}

      {:error, reason} ->
        Logger.error("Failed to parse response: #{inspect(reason)}")
        {{:value, {caller, _query_name}}, new_data} = get_and_update_in(data.queue, &:queue.out/1)
        actions = [{:reply, caller, {:error, :parse_failed}}]
        {:next_state, :established_no_agency, new_data, actions}
    end
  end

  def established_has_agency(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed while querying")
    {:next_state, :disconnected, data}
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
