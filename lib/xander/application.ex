defmodule Xander.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Xander.ClientStatem, client_opts()}
    ]

    opts = [strategy: :one_for_one, name: Xander.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp client_opts do
    network = System.get_env("CARDANO_NETWORK", "mainnet") |> String.to_atom()
    path = System.get_env("CARDANO_NODE_PATH", "/tmp/cardano-node.socket")
    port = System.get_env("CARDANO_NODE_PORT", "0") |> String.to_integer()
    # socket, tcp or tls
    type = System.get_env("CARDANO_NODE_TYPE", "socket")

    [
      network: network,
      path: path,
      port: port,
      type: type
    ]
  end
end
