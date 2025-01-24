# Xander

Elixir client for Cardano's Ouroboros networking.

⚠️ This project is under active development. For a more stable solution to connect to a Cardano node using Elixir, see [Xogmios](https://github.com/wowica/xogmios).

 There are two ways to run this project:

1. [Running via Docker](#running-via-docker)
2. [Running natively with an Elixir local dev environment](#running-natively-with-an-elixir-local-dev-environment)

## Running via Docker

### Using Demeter.run

The demo application can connect to a Cardano node at [Demeter.run](https://demeter.run/) 🪄 

First, create a Node on Demeter. Then, set your Node's url in the `DEMETER_URL` environment variable in the `.env` file. 

For example:

```bash
DEMETER_URL=https://your-node-at.demeter.run
```

Then, run the application using Docker Compose:

```bash
docker compose up --build
```

#### Via local UNIX socket

Uncomment the `volumes` section in the `compose.yml` file to mount the local UNIX socket to the container's socket path.

```yml
volumes:
  - /path/to/node.socket:/tmp/cardano-node.socket
```

Then, run the application using Docker Compose:
```bash
docker compose up --build
```

## Running natively with an Elixir local dev environment

#### Via local UNIX socket

Run the following command using your own Cardano node's socket path:

```bash
CARDANO_NODE_PATH=/your/cardano/node.socket mix query_current_era
```

##### Setting up Unix socket mapping

This is useful if you want to run the application on a server different from your Cardano node.

🚨 **Note:** Socket files mapped via socat/ssh tunnels do not work when using containers on OS X.

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

To connect to a node at Demeter.run, set `DEMETER_URL` to your Node Demeter URL.

```bash
DEMETER_URL=https://your-node-at.demeter.run mix query_current_era
```