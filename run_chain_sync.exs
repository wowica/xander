# Install Xander from local path
Mix.install([
  {:blake2, "~> 1.0"},
  {:xander, path: Path.expand(".")}
])

logger_level = System.get_env("LOGGER_LEVEL", "warning")
Logger.configure(level: String.to_atom(logger_level))

defmodule FollowDaChain do
  use Xander.ChainSync

  def start_link(opts) do
    slot = 156_719_996
    block_hash = "fc3173fddbf1b45a653c940747fe8226b4b7c3f272b8968a81c757c32654af14"

    initial_state = [
      sync_from: {slot, block_hash}
    ]

    opts = Keyword.merge(opts, initial_state)
    Xander.ChainSync.start_link(__MODULE__, opts)
  end

  @impl true
  def handle_block(%{block_number: block_number, size: size}, state) do
    IO.puts("block_number: #{block_number}, size: #{size}")
    {:ok, :next_block, state}
  end

  @impl true
  def handle_rollback(%{slot_number: slot_number, block_hash: block_hash}, state) do
    IO.puts("Rollback to Slot: #{slot_number}, Block Hash: #{block_hash}")
    {:ok, :next_block, state}
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
