# Install Xander from local path
Mix.install([
  {:blake2, "~> 1.0"},
  {:xander, path: Path.expand(".")}
])

socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH", "/tmp/cardano-node.socket")

if !File.exists?(socket_path) do
  IO.puts("Error: socket file path #{socket_path} does not exist")
  System.halt(1)
end

alias Xander.Config
alias Xander.Query

# Default config connects via a local UNIX socket
config = Config.default_config!(socket_path, :preview)

queries = [
  :get_epoch_number,
  :get_current_era,
  :get_current_block_height,
  :get_current_tip
]

case Query.start_link(config) do
  {:ok, pid} ->
    IO.puts("Successfully connected to Cardano node 🎉\n")

    for query <- queries do
      case Query.run(pid, query) do
        {:ok, result} ->
          IO.puts("Query #{query} result: #{inspect(result)}")

        {:error, reason} ->
          IO.puts("Error querying #{inspect(query)}: #{inspect(reason)}")
          System.halt(1)
      end
    end

  {:error, reason} ->
    IO.puts("Failed to connect to Cardano node: #{inspect(reason)}")
    System.halt(1)
end
