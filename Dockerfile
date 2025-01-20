# Build stage
ARG ELIXIR_VERSION=1.18.1
ARG OTP_VERSION=27.2
ARG DEBIAN_VERSION=bullseye-20241223-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y build-essential git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy mix files first to cache dependencies
COPY mix.exs mix.lock ./

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Install mix dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application code
COPY . .

# Compile and build release
RUN mix do compile, release

# Runtime stage
FROM ${RUNNER_IMAGE}

# Install runtime dependencies and locales
RUN apt-get update && \
    apt-get install -y libstdc++6 openssl locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy release from builder stage
COPY --from=builder /app/_build/prod/rel/xander ./

# Set environment variables
ENV HOME=/app
ENV MIX_ENV=prod
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV ELIXIR_ERL_OPTIONS="+fnu"

# Create entrypoint script
RUN echo '#!/bin/sh\n\
echo "Starting application..."\n\
/app/bin/xander eval "Application.ensure_all_started(:xander); Xander.get_current_era() |> IO.inspect"' > /app/entrypoint.sh && \
chmod +x /app/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
