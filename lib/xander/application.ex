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
    demeter_url = System.get_env("DEMETER_URL", "") |> String.trim()

    if demeter_url == "" do
      path = System.get_env("CARDANO_NODE_PATH", "/tmp/cardano-node.socket")

      [
        network: network,
        path: path,
        port: 0,
        type: "socket"
      ]
    else
      port = System.get_env("DEMETER_PORT", "9443") |> String.trim()
      port = if port == "", do: 9443, else: String.to_integer(port)

      [
        network: network,
        path: demeter_url,
        port: port,
        type: "ssl"
      ]
    end
  end
end
