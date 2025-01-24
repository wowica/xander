# Install Xander from local path
Mix.install([
  {:xander, path: Path.expand(".")}
])


socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH")

unless socket_path do
  IO.puts("Error: CARDANO_NODE_SOCKET_PATH environment variable is not set")
  System.halt(1)
end

alias Xander.Config
alias Xander.Query

# Default config connects via a local UNIX socket
config = socket_path
  |> Config.default_config()
  |> Config.validate_config()

case Query.start_link(config) do
  {:ok, pid} ->
    IO.puts("Successfully connected to Cardano node")

    case Query.run(pid, :get_current_era) do
      {:ok, current_era} ->
        IO.puts("Current Cardano era: #{inspect(current_era)}")

      {:error, reason} ->
        IO.puts("Error querying current era: #{inspect(reason)}")
        System.halt(1)
    end

  {:error, reason} ->
    IO.puts("Failed to connect to Cardano node: #{inspect(reason)}")
    System.halt(1)
end
