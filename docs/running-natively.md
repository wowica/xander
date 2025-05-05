## Running Natively

For those with Elixir already installed, simply run the commands below:

```
# Must set a local unix socket
elixir run_queries.exs

# Must set a Demeter URL
elixir run_queries_with_demeter.exs

# Must provide a signed tx CBOR hex
elixir run_submit_tx.exs
```

More information on connection below:

#### a) Connecting via local UNIX socket

Run the following command using your own Cardano node's socket path:

```bash
CARDANO_NODE_PATH=/your/cardano/node.socket elixir run.exs
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
DEMETER_URL=https://your-node-at.demeter.run elixir run_with_demeter.exs
```