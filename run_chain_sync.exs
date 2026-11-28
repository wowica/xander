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
    initial_state = [
      ## :conway era is only supported on mainnet
      sync_from: :conway

      ## Start of the Babbage era (currently preview only).
      ## Requires CARDANO_NETWORK=preview.
      # sync_from: :babbage

      ## Preview testnet conway era boundary
      # sync_from: {55814394, "bdd4baa2c81d0500a695f836332193ea06c2ce364e585057142220fc0782144c"}

      ## Preprod testnet conway era boundary
      # sync_from: {68774372, "36f5b4a370c22fd4a5c870248f26ac72c0ac0ecc34a42e28ced1a4e15136efa4"}
    ]

    opts = Keyword.merge(opts, initial_state)
    Xander.ChainSync.start_link(__MODULE__, opts)
  end

  @impl true
  def handle_block(%{era: era, block_number: block_number, size: size}, state) do
    IO.puts("era: #{era}, block_number: #{block_number}, size: #{size}")
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
    network = System.get_env("CARDANO_NETWORK", "mainnet") |> String.to_atom()
    Xander.Config.default_config!(socket_path, network)
  end
end

CardanoApplication.run()

unless IEx.started?() do
  Process.sleep(:infinity)
end
