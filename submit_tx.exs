# Install Xander from local path
Mix.install([
  {:blake2, "~> 1.0.0"},
  {:xander, path: Path.expand(".")}
])

socket_path = System.get_env("CARDANO_NODE_SOCKET_PATH", "/tmp/cardano-node-preview.socket")

if !File.exists?(socket_path) do
  IO.puts("Error: socket file path #{socket_path} does not exist")
  System.halt(1)
end

tx_hex =
  case System.argv() do
    [hex] ->
      hex

    _ ->
      IO.puts("Error: Please provide a valid transaction CBOR hex as an argument")
      System.halt(1)
  end

alias Xander.Config
alias Xander.Transaction

# Default config connects via a local UNIX socket
config = Config.default_config!(socket_path, :preview)

case Transaction.start_link(config) do
  {:ok, pid} ->
    IO.puts("Successfully connected to Cardano node 🎉\n")

    case Transaction.send(pid, tx_hex) do
      {:accepted, tx_id} -> IO.puts("\nTransaction submitted successfully ✅\nTx ID: #{tx_id}")
      _ -> IO.puts("Error submitting transaction")
    end

  {:error, reason} ->
    IO.puts("Failed to connect to Cardano node: #{inspect(reason)}")
    System.halt(1)
end
