defmodule Xander.Transport do
  @moduledoc """
  Abstracts transport layer details for connecting to Cardano nodes.

  This module provides a unified interface for both Unix socket connections
  (via `:gen_tcp`) and SSL connections (via `:ssl`), eliminating the need
  for mini-protocol implementations to handle transport-specific logic.

  ## Usage

  Create a transport from configuration:

      config = Xander.Config.default_config!("/path/to/node.socket")
      transport = Xander.Transport.new(config)

  Then use the transport for all socket operations:

      {:ok, socket} = Xander.Transport.connect(transport)
      :ok = Xander.Transport.send(transport, socket, data)
      {:ok, response} = Xander.Transport.recv(transport, socket, 0, 5_000)
      :ok = Xander.Transport.setopts(transport, socket, active: :once)
      :ok = Xander.Transport.close(transport, socket)
  """

  @basic_opts [:binary, active: false, send_timeout: 4_000]

  defstruct [:type, :client, :setopts_module, :path, :port, :connect_opts]

  @type t :: %__MODULE__{
          type: :socket | :ssl,
          client: :gen_tcp | :ssl,
          setopts_module: :inet | :ssl,
          path: {:local, String.t()} | String.t(),
          port: non_neg_integer(),
          connect_opts: keyword()
        }

  @doc """
  Creates a new Transport struct from configuration options.

  ## Options

    * `:path` - The socket path (for Unix sockets) or URL (for SSL)
    * `:port` - The port number (0 for Unix sockets, typically 9443 for SSL)
    * `:type` - Either `:socket` for Unix sockets or `:ssl` for SSL connections

  ## Examples

      # Unix socket
      transport = Xander.Transport.new(path: "/tmp/node.socket", port: 0, type: :socket)

      # SSL connection
      transport = Xander.Transport.new(path: "https://node.demeter.run", port: 9443, type: :ssl)
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    type = Keyword.fetch!(opts, :type)
    path = Keyword.fetch!(opts, :path)
    port = Keyword.fetch!(opts, :port)

    %__MODULE__{
      type: type,
      client: client_module(type),
      setopts_module: setopts_module(type),
      path: normalize_path(path, type),
      port: normalize_port(port, type),
      connect_opts: build_connect_opts(type, path)
    }
  end

  @doc """
  Connects to the Cardano node using the transport configuration.

  Returns `{:ok, socket}` on success or `{:error, reason}` on failure.
  """
  @spec connect(t()) :: {:ok, any()} | {:error, any()}
  def connect(%__MODULE__{client: client, path: path, port: port, connect_opts: opts}) do
    client.connect(parse_connect_address(path), port, opts)
  end

  @doc """
  Sends data through the socket.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec send(t(), any(), iodata()) :: :ok | {:error, any()}
  def send(%__MODULE__{client: client}, socket, data) do
    client.send(socket, data)
  end

  @doc """
  Receives data from the socket.

  Returns `{:ok, data}` on success or `{:error, reason}` on failure.
  """
  @spec recv(t(), any(), non_neg_integer(), timeout()) :: {:ok, binary()} | {:error, any()}
  def recv(%__MODULE__{client: client}, socket, length, timeout) do
    client.recv(socket, length, timeout)
  end

  @doc """
  Sets socket options.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec setopts(t(), any(), keyword()) :: :ok | {:error, any()}
  def setopts(%__MODULE__{setopts_module: setopts_module}, socket, opts) do
    setopts_module.setopts(socket, opts)
  end

  @doc """
  Closes the socket connection.

  Returns `:ok`.
  """
  @spec close(t(), any()) :: :ok
  def close(%__MODULE__{client: client}, socket) do
    client.close(socket)
  end

  # Private functions

  defp client_module(:ssl), do: :ssl
  defp client_module(_), do: :gen_tcp

  defp setopts_module(:ssl), do: :ssl
  defp setopts_module(_), do: :inet

  defp normalize_path(path, :socket), do: {:local, path}
  defp normalize_path(path, _), do: path

  defp normalize_port(_port, :socket), do: 0
  defp normalize_port(port, _), do: port

  defp build_connect_opts(:ssl, path) do
    @basic_opts ++
      [
        verify: :verify_none,
        server_name_indication: ~c"#{path}",
        secure_renegotiate: true
      ]
  end

  defp build_connect_opts(_, _), do: @basic_opts

  defp parse_connect_address({:local, _path} = local_path), do: local_path

  defp parse_connect_address(path) when is_binary(path) do
    uri = URI.parse(path)
    ~c"#{uri.host}"
  end

  defp parse_connect_address(path), do: path
end
