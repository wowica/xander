# Xander

Elixir client for Cardano's Ouroboros networking.

## Running

#### Via local UNIX socket

Run the following command using your own Cardano node's socket path:

```bash
CARDANO_NODE_PATH=/your/cardano/node.socket mix query_current_era
```

##### Setting up Unix socket mapping

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

#### Using Demeter.run

To connect to a node at Demeter.run, set `CARDANO_NODE_TYPE=ssl` and `CARDANO_NODE_PATH` to your Node Demeter URL.

```bash
CARDANO_NODE_TYPE=ssl CARDANO_NODE_PATH=https://your-node-at.demeter.run mix query_current_era
```

## Catalyst Proposal

F13 proposal for further development of this project:
[https://cardano.ideascale.com/c/cardano/idea/131598](https://cardano.ideascale.com/c/cardano/idea/131598)
