FROM elixir:1.18.1-alpine

RUN mix local.hex --force

WORKDIR /app

COPY mix.exs .
COPY mix.lock .

RUN mix deps.get

COPY . .

RUN mix compile

ENV CARDANO_NETWORK=${CARDANO_NETWORK:-mainnet}
ENV CARDANO_NODE_PATH=${CARDANO_NODE_PATH}
ENV CARDANO_NODE_PORT=${CARDANO_NODE_PORT:-0}
ENV CARDANO_NODE_TYPE=${CARDANO_NODE_TYPE:-socket}

CMD ["mix", "query_current_era"]
