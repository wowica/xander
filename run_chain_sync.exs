# Install Xander from local path
Mix.install([
  {:blake2, "~> 1.0"},
  {:xander, path: Path.expand(".")},
  {:telemetry, "~> 1.0"}
])

defmodule IndexState do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{start_timestamp: nil, last_timestamp: nil, block_count: 0} end,
      name: __MODULE__
    )
  end

  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  def update_state(new_state) do
    Agent.update(__MODULE__, fn _ -> new_state end)
  end
end

defmodule FollowDaChain do
  use Xander.ChainSync

  def start_link(opts) do
    initial_state = [
      sync_from: {155_767_673, "9e61fede5d99c60e5353bb3174b4152709ca5b3aa833edc42ab42d61c34528d6"}
    ]

    opts = Keyword.merge(opts, initial_state)
    Xander.ChainSync.start_link(__MODULE__, opts)
  end

  def handle_block(%{block_number: block_number, size: size}, state) do
    # :telemetry.execute(
    #   [:xander, :chain_sync, :block_processed],
    #   %{
    #     timestamp: System.system_time(:millisecond),
    #     block_height: block_number
    #   }
    # )
    IO.puts("block_number: #{block_number}, size: #{size}")
    {:ok, :next_block, state}
  end
end

defmodule CardanoApplication do
  def run do
    children = [
      IndexState,
      {FollowDaChain, opts()}
    ]

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  end

  :telemetry.attach(
    "xander-chain-sync-metrics",
    [:xander, :chain_sync, :block_processed],
    &__MODULE__.handle_block_processed/4,
    nil
  )

  defp opts do
    socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH", "/tmp/cardano-node.socket")
    Xander.Config.default_config!(socket_path)
  end

  def handle_block_processed(
        [:xander, :chain_sync, :block_processed],
        %{timestamp: now, block_height: height},
        _metadata,
        _config
      ) do
    # Get current state
    state = IndexState.get_state()

    # Calculate throughput
    {new_state, instant_throughput, avg_throughput} = calculate_throughput(state, now)

    # Update state
    IndexState.update_state(new_state)

    # Print metrics
    print_metrics(instant_throughput, avg_throughput, height)
  end

  defp calculate_throughput(state, now) do
    cond do
      is_nil(state.start_timestamp) ->
        # First block
        new_state = %{state | start_timestamp: now, last_timestamp: now, block_count: 1}
        {new_state, 0.0, 0.0}

      true ->
        # Subsequent blocks
        time_diff = now - state.last_timestamp
        total_time = now - state.start_timestamp

        # Handle edge cases where time_diff or total_time is zero or negative
        instant_throughput = if time_diff > 0, do: 1000 / time_diff, else: 0.0
        avg_throughput = if total_time > 0, do: state.block_count * 1000 / total_time, else: 0.0

        new_state = %{state | last_timestamp: now, block_count: state.block_count + 1}
        {new_state, instant_throughput, avg_throughput}
    end
  end

  defp print_metrics(_instant_throughput, avg_throughput, height) do
    IO.puts(
      IO.ANSI.format([
        :green,
        "Chain Sync Throughput: ",
        :yellow,
        :io_lib.format("~.2f", [avg_throughput]),
        :reset,
        " blocks/second (avg) | height: #{height}"
      ])
    )
  end
end

CardanoApplication.run()

unless IEx.started?() do
  Process.sleep(:infinity)
end
