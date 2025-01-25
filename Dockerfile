FROM elixir:1.18.1-alpine

RUN mix local.hex --force

WORKDIR /app

COPY mix.exs .
COPY mix.lock .

RUN mix deps.get

COPY . .

RUN mix compile

CMD ["elixir", "run_with_demeter.exs"]
#CMD ["elixir", "run.exs"]