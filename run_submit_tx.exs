# Install Xander from local path
Mix.install([
  {:xander, path: Path.expand(".")},
  {:cbor, "~> 1.0.0"},
  {:blake2, "~> 1.0.0"}
])

socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH", "/tmp/cardano-node-preview.socket")

if !File.exists?(socket_path) do
  IO.puts("Error: socket file path #{socket_path} does not exist")
  System.halt(1)
end

alias Xander.Config
alias Xander.Transaction

# Default config connects via a local UNIX socket
config = Config.default_config!(socket_path, :preview)

case Transaction.start_link(config) do
  {:ok, pid} ->
    IO.puts("Successfully connected to Cardano node 🎉\n")

    tx_hex =
      ""

    case Transaction.send(pid, tx_hex) do
      {:accepted, tx_id} -> IO.puts("Transaction submitted successfully: #{tx_id}")
      _ -> IO.puts("Error submitting transaction")
    end

  {:error, reason} ->
    IO.puts("Failed to connect to Cardano node: #{inspect(reason)}")
    System.halt(1)
end
