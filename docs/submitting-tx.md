## Submitting Transactions

⚠️ This project does not provide off-chain transaction functionality such as building and signing of transactions.

In order to submit transactions via Xander, you can either run the `run_submit_tx.exs` script directly or use Docker. 


## Running the script

This assumes you have Elixir installed. In order to run the script directly, follow the steps below:

1. Get ahold of the CBOR hex of a valid signed transaction (not covered by this library)
2. Populate the environment variable `CARDANO_NODE_SOCKET_PATH` with a socket file for a fully synced Cardano node.
3. Ensure the `Config.default_config!` function call matches the network being used:
    - `Config.default_config!(socket_path)` defaults to Mainnet
    - `Config.default_config!(socket_path, :preview)` for Preview network
4. Run `elixir submit_tx.exs <transaction-CBOR-hex>` providing the CBOR hex as its single argument.

A successful submission should return the transaction ID. This ID can be used to check the status of the transaction on any Cardano blockchain explorer.

## Using Docker

1. First, build the image:

```
docker build -t xander .
```

2. Ensure the `Config.default_config!` function inside the `submit_tx.exs` file matches the network being used:
    - `Config.default_config!(socket_path)` defaults to Mainnet
    - `Config.default_config!(socket_path, :preview)` for Preview network

3. Get ahold of the CBOR hex of a valid signed transaction (not covered by this library)

Run the previously built Docker image with the `-v` argument, which mounts the path of your local socket path to 
the container's default socket path (`/tmp/cardano-node-preview.socket`):

```
docker run --rm \
  -v /your/local/preview-node.socket:/tmp/cardano-node-preview.socket \
  xander elixir submit_tx.exs <transaction-CBOR-hex>
```

A successful submission should return the transaction ID. This ID can be used to check the status of the transaction on any Cardano blockchain explorer.