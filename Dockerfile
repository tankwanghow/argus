ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=bookworm-20260202-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app/tugas

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY shared_config /app/shared_config
COPY .global_assets /app/.global_assets

COPY tugas/mix.exs tugas/mix.lock ./
RUN HEX_HTTP_CONCURRENCY=8 HEX_HTTP_TIMEOUT=240 mix deps.get --only $MIX_ENV
RUN mkdir config

COPY tugas/config/config.exs tugas/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY tugas/priv priv
COPY tugas/lib lib
COPY tugas/assets assets

RUN mix assets.deploy

RUN mix compile

COPY tugas/config/runtime.exs config/

COPY tugas/rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y \
    libncurses5 \
    libstdc++6 \
    locales \
    openssl \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/tugas/_build/${MIX_ENV}/rel/tugas ./

USER nobody

CMD ["/app/bin/server"]