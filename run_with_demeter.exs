# Install Xander from local path
Mix.install([
  {:xander, path: Path.expand(".")}
])

# Example script showing Xander usage with Demeter configuration
# Usage: DEMETER_URL=your-demeter-url elixir run_with_demeter.exs
demeter_url = System.get_env("DEMETER_URL")

if demeter_url == nil do
  IO.puts("Error: DEMETER_URL environment variable is not set")
  System.halt(1)
end

alias Xander.Config
alias Xander.Query

network = System.get_env("CARDANO_NETWORK", "mainnet") |> String.to_atom()

# Configure Xander client for Demeter
config = Config.demeter_config!(demeter_url, network: network)

queries = [
  :get_epoch_number,
  :get_current_era,
  :get_current_block_height
]

case Query.start_link(config) do
  {:ok, pid} ->
    IO.puts("Successfully connected to Demeter node")

    for query <- queries do
      case Query.run(pid, query) do
      {:ok, result} ->
        IO.puts("Query #{query} result: #{inspect(result)}")

      {:error, reason} ->
          IO.puts("Error querying epoch number: #{inspect(reason)}")
          System.halt(1)
      end
    end

  {:error, reason} ->
    IO.puts("Failed to connect to Demeter node: #{inspect(reason)}")
    System.halt(1)
end
