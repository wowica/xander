# Xander

![CI Status](https://github.com/wowica/xander/actions/workflows/ci.yml/badge.svg)
[![Version](https://img.shields.io/hexpm/v/xander.svg)](https://hex.pm/packages/xander)

Elixir client for Cardano's Ouroboros networking protocol.

⚠️ This project is under active development. For a more stable solution to connect to a Cardano node using Elixir, see [Xogmios](https://github.com/wowica/xogmios).

## Quickstart

Below is an example of how to connect to a Cardano node and run a query that returns the current tip of the ledger, similar to a `cardano-cli query tip` command.

```elixir
$ iex
> Mix.install([{:xander, "~> 0.1.0"}])
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


1. [Running via Docker](#running-via-docker)
2. [Running natively with an Elixir local dev environment](#running-natively-with-an-elixir-local-dev-environment)

## Running via Docker

In order to run the application via Docker, you need to build the image first:

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
  xander elixir run.exs
```

#### 2. Connecting to a node at Demeter.run

The demo application can connect to a Cardano node at [Demeter.run](https://demeter.run/) 🪄 

First, create a Node on Demeter and grab the Node's URL.

Then, run the Docker image with the `DEMETER_URL` environment variable set to your Node's URL:

```bash
docker run --rm \
  -e DEMETER_URL=https://your-node-at.demeter.run \
  xander elixir run_with_demeter.exs
```

## Running natively with an Elixir local dev environment

#### a) Via local UNIX socket

Run the following command using your own Cardano node's socket path:

```bash
CARDANO_NODE_PATH=/your/cardano/node.socket elixir run.exs
```

##### Setting up Unix socket mapping

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

#### b) Using Demeter.run

To connect to a node at Demeter.run, set `DEMETER_URL` to your Node Demeter URL.

```bash
DEMETER_URL=https://your-node-at.demeter.run elixir run_with_demeter.exs
```