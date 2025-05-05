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
  xander elixir run_queries.exs
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