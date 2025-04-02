# Install Xander from local path
Mix.install([
  {:xander, path: Path.expand(".")}
])

defmodule FollowDaChain do
  use Xander.ChainSync

  def start_link(opts) do
    opts = Keyword.merge(opts, sync_from: :conway)
    Xander.ChainSync.start_link(__MODULE__, opts)
  end

  def handle_block(%{block_number: block_number, size: size}) do
    IO.puts("Block number: #{block_number}, size: #{size}")
  end
end

defmodule CardanoApplication do
  def run do
    children = [
      {FollowDaChain, opts()}
    ]

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp opts do
    socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH", "/tmp/cardano-node.socket")
    Xander.Config.default_config!(socket_path)
  end
end

CardanoApplication.run()

unless IEx.started?() do
  Process.sleep(:infinity)
end
