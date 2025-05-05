# Xander

![CI Status](https://github.com/wowica/xander/actions/workflows/ci.yml/badge.svg)
[![Version](https://img.shields.io/hexpm/v/xander.svg)](https://hex.pm/packages/xander)

Elixir client for Cardano's Ouroboros networking protocol.

⚠️ This project is under active development. For a more stable solution to connect to a Cardano node using Elixir, see [Xogmios](https://github.com/wowica/xogmios).

## Mini-Protocols supported by this library:

- [x] Tx Submission
- [x] Local State Query
  - get_epoch_number
  - get_current_era
  - get_current_block_height
  - get_current_tip
- [] Chain-Sync

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


1. [Running queries via Docker](docs/running-via-docker.md)
2. [Running queries with native Elixir install](docs/running-natively.md)
3. [Submitting transactions](docs/submitting-tx.md)