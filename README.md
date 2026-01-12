# Xander

![CI Status](https://github.com/wowica/xander/actions/workflows/ci.yml/badge.svg)
[![Version](https://img.shields.io/hexpm/v/xander.svg)](https://hex.pm/packages/xander)

<p align="center">
  <img src="assets/xander-logo.png" alt="Xander" width="300">
</p>

Elixir client for Cardano's Ouroboros networking protocol. This library can be used to build Elixir applications that connect to a Cardano node using the Node-to-Client protocol.

⚠️ This project is under active development. See [Xogmios](https://github.com/wowica/xogmios) for a more stable solution to connect to a Cardano node through [Ogmios](https://ogmios.dev/).

## Mini-Protocols currently supported by this library:

- [x] Tx Submission
- [x] Local State Query
  - get_epoch_number
  - get_current_era
  - get_current_block_height
  - get_current_tip
- [x] Chain-Sync (support for Conway era only)

## Quickstart

Below is an example of how to connect to a Cardano node and run a query that returns the current tip of the ledger, similar to a `cardano-cli query tip` command.

```elixir
$ iex
> Mix.install([{:xander, "~> 0.2.0"}])
> # Must be a valid Unix socket path
> # to a fully synced Cardano node
> socket_path = "/path/to/cardano-node.socket"
> config = Xander.Config.default_config!(socket_path)
[
  network: :mainnet,
  path: [socket_path: "/tmp/cardano-node.socket"],
  port: 0,
  type: :socket
]
> {:ok, pid} = Xander.Query.start_link(config)
{:ok, #PID<0.207.0>}
> Xander.Query.run(pid, :get_current_tip)
{:ok,
 {147911158, "b2a4f78539559866281d6089143fa4c99db90b7efc4cf7787777f927967f0c8a"}}
```

For a more detailed description of different ways to use this library, read the following sections:


<details>
  <summary><i>Running Queries via Docker</i></summary>

  ## Running Queries via Docker

  In order to run queries via Docker, you need to build the image first:

  ```
  docker build -t xander .
  ```

  With the image built, you can now connect to either a local Cardano node via a UNIX socket or to a node at Demeter.run.

  #### 1. Connecting via a local UNIX socket

  This assumes you have access to a fully synced Cardano node.

  🚨 **Note:** Socket files mapped via socat/ssh tunnels **DO NOT WORK** when using containers on OS X.

  Run the previously built Docker image with the `-v` argument, which mounts the path of your local socket path to 
  the container's default socket path (`/tmp/cardano-node.socket`):

  ```
  docker run --rm \
    -v /your/local/node.socket:/tmp/cardano-node.socket \
    xander elixir run_queries.exs
  ```

  #### 2. Connecting to a node at Demeter.run

  The demo application can connect to a Cardano node at [Demeter.run](https://demeter.run/) 🪄 

  First, create a Node on Demeter and grab the Node's URL.

  Then, run the Docker image with the `DEMETER_URL` environment variable set to your Node's URL:

  ```bash
  docker run --rm \
    -e DEMETER_URL=https://your-node-at.demeter.run \
    xander elixir run_queries_with_demeter.exs
  ```
</details>

<details>
  <summary><i>Running Queries with native Elixir install</i></summary>
  
  ## Running Queries with native Elixir install

  For those with Elixir already installed, simply run the commands below:

  ```
  # Must set a local unix socket
  elixir run_queries.exs

  # Must set a Demeter URL
  elixir run_queries_with_demeter.exs
  ```

  More information on connection below:

  #### a) Connecting via local UNIX socket

  Run the following command using your own Cardano node's socket path:

  ```bash
  CARDANO_NODE_PATH=/your/cardano/node.socket elixir run_queries.exs
  ```

  ##### Setting up Unix socket mapping (optional when no direct access to Cardano node)

  This is useful if you want to run the application on a server different from your Cardano node.

  🚨 **Note:** Socket files mapped via socat/ssh tunnels **DO NOT WORK** when using containers on OS X.

  1. Run socat on the remote server with the following command:

  ```bash
  socat TCP-LISTEN:3002,reuseaddr,fork UNIX-CONNECT:/home/cardano_node/socket/node.socket
  ```

  2. Run socat on the local machine with the following command:

  ```bash
  socat UNIX-LISTEN:/tmp/cardano_node.socket,reuseaddr,fork TCP:localhost:3002
  ```

  3. Start an SSH tunnel from the local machine to the remote server with the following command:

  ```bash
  ssh -N -L 3002:localhost:3002 user@remote-server-ip
  ```

  4. Run the example script:

  ```bash
  CARDANO_NODE_PATH=/tmp/cardano_node.socket elixir run.exs
  ```

  #### b) Connecting via Demeter.run

  To connect to a node at Demeter.run, set `DEMETER_URL` to your Node Demeter URL.

  ```bash
  DEMETER_URL=https://your-node-at.demeter.run elixir run_queries_with_demeter.exs
  ```
</details>

<details>
  <summary><i>Submitting Transactions</i></summary>

  ## Submitting Transactions

  ⚠️ This project does not provide off-chain transaction functionality such as building and signing of transactions.

  In order to submit transactions via Xander, you can either run the `submit_tx.exs` script directly or use Docker. 


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

  This assumes you have Docker installed. No Elixir installation is required.

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
</details>

<details>
  <summary><i>Running ChainSync</i></summary>

  ## Chain Sync

  In order to sync blocks from a Cardano node, you can either run the `run_chain_sync.exs` script directly or use Docker.

  ## Running the script

  This assumes you have Elixir installed. In order to run the script directly, follow the steps below:

  1. Populate the environment variable `CARDANO_NODE_SOCKET_PATH` with a socket file for a fully synced **mainnet** Cardano node.
  2. Run `elixir run_chain_sync.exs`

  Using default settings, this will start syncing from the start of the Conway era. For each block, the block number (height) and block size (in bytes) will be displayed.

  If you wish to connect with one of the testnets, see comments on the `FollowDaChain.start_link/1` function for more information on exact points in the chain to start syncing from.

  ## Using Docker

  This assumes you have Docker installed. No Elixir installation is required.

  1. First, build the image:

  ```
  docker build -t xander .
  ```

  ```
  docker run --rm -v /your/local/cardano-node.socket:/tmp/cardano-node.socket xander elixir run_chain_sync.exs
  ```

  ## Using Demeter.run
  
  Populate the environment variable `DEMETER_URL` with the URL of a node at Demeter.run and run the `run_chain_sync_with_demeter.exs` script.

  ```
  DEMETER_URL=https://your-node-at.demeter.run elixir run_chain_sync_with_demeter.exs
  ```

  or use Docker:

  ```
  docker run --rm -e DEMETER_URL=https://your-node-at.demeter.run xander elixir run_chain_sync_with_demeter.exs
  ```
</details>

## Testing

The integration tests are built upon [Yaci Devkit](https://github.com/bloxbean/yaci-devkit) and can be run locally with [nektos/act](https://github.com/nektos/act).

For x86_64 (Intel/AMD) chips:

```
act -j integration_test
```

For Apple Silicon (M1/M2/M3) chips:

```
act -j integration_test --container-architecture linux/arm64
```
