defmodule Xander.ClientStatem do
  @moduledoc """
  Connects to a Cardano node via local UNIX socket using the Node-to-Client protocol
  """
  @behaviour :gen_statem

  alias Xander.Handshake
  alias Xander.LocalStateQueryResponse
  alias Xander.Messages

  require Logger

  @basic_tcp_opts [:binary, active: false, send_timeout: 4_000]
  @active_n2c_versions [9, 10, 11, 12, 13, 14, 15, 16]

  defstruct [:client, :path, :port, :socket, :network, queue: :queue.new()]

  ##############
  # Public API #
  ##############

  def query(pid \\ __MODULE__, query_name) do
    :gen_statem.call(pid, {:request, query_name})
  end

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

    case client.recv(socket, 0, 5_000) do
      {:ok, full_response} ->
        {:ok, _handshake_response} = Handshake.Response.validate(full_response)

        actions = [{:next_event, :internal, :acquire_agency}]
        {:next_state, :established_no_agency, data, actions}

      {:error, reason} ->
        Logger.error("Error establishing connection #{inspect(reason)}")
        {:next_state, :disconnected, data}
    end
  end

  def established_no_agency(
        :internal,
        :acquire_agency,
        %__MODULE__{client: client, socket: socket} = data
      ) do
    :ok = client.send(socket, Messages.msg_acquire())
    {:ok, _acquire_response} = client.recv(socket, 0, 5_000)
    {:next_state, :established_has_agency, data}
  end

  def established_no_agency(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed")
    {:next_state, :disconnected, data}
  end

  def established_has_agency(
        {:call, from},
        {:request, :get_current_era},
        %__MODULE__{client: client, socket: socket} = data
      ) do
    :ok = setopts_lib(client).setopts(socket, active: :once)
    :ok = client.send(socket, Messages.get_current_era())
    data = update_in(data.queue, &:queue.in(from, &1))
    {:keep_state, data}
  end

  def established_has_agency(
        :info,
        {_tcp_or_ssl, socket, bytes},
        %__MODULE__{socket: socket} = data
      ) do
    {:ok, current_era} = LocalStateQueryResponse.parse_response(bytes)
    {{:value, caller}, data} = get_and_update_in(data.queue, &:queue.out/1)
    # This action issues the response back to the clinet
    actions = [{:reply, caller, {:ok, current_era}}]
    {:keep_state, data, actions}
  end

  def established_has_agency(:info, {:tcp_closed, socket}, %__MODULE__{socket: socket} = data) do
    Logger.error("Connection closed")
    {:next_state, :disconnected, data}
  end

  defp maybe_local_path(path, "socket"), do: {:local, path}
  defp maybe_local_path(path, _), do: path

  defp maybe_local_port(_port, "socket"), do: 0
  defp maybe_local_port(port, _), do: port

  defp maybe_parse_path(path) when is_binary(path), do: ~c[#{path}]
  defp maybe_parse_path(path), do: path

  defp tcp_lib("ssl"), do: :ssl
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
