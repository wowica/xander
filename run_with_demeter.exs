# Install Xander from local path
Mix.install([
  {:xander, path: Path.expand(".")}
])

# Example script showing Xander usage with Demeter configuration
# Usage: DEMETER_URL=your-demeter-url elixir run_with_demeter.exs
demeter_url = System.get_env("DEMETER_URL")

unless demeter_url do
  IO.puts("Error: DEMETER_URL environment variable is not set")
  System.halt(1)
end

alias Xander.Config
alias Xander.Query

# Configure Xander client for Demeter
config = Config.demeter_config(
    demeter_url,
    network: :mainnet,
    port: 9443
  )
  |> Config.validate_config()

case Query.start_link(config) do
  {:ok, pid} ->
    IO.puts("Successfully connected to Demeter node")

    case Query.run(pid, :get_current_era) do
      {:ok, current_era} ->
        IO.puts("Current Cardano era: #{inspect(current_era)}")

      {:error, reason} ->
        IO.puts("Error querying current era: #{inspect(reason)}")
        System.halt(1)
    end

  {:error, reason} ->
    IO.puts("Failed to connect to Demeter node: #{inspect(reason)}")
    System.halt(1)
end
