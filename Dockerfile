# Stage 1: build
FROM elixir:otp-26-slim AS builder

ENV MIX_ENV=prod

WORKDIR /build/double_gis_monitor

RUN apt-get update \
    && apt-get install -y git

COPY mix.exs mix.lock ./
COPY config config

RUN mix local.hex --force \
    && mix local.rebar --force \
    && mix deps.get --only $MIX_ENV \
    && mix deps.compile

COPY lib lib
COPY priv priv

RUN mix compile \
    && mix release --path /double_gis_monitor

# Stage 2: release
FROM debian:testing-slim AS runner

COPY --from=builder /double_gis_monitor /double_gis_monitor

EXPOSE 4369

ENV ERL_MAX_PORTS=32768

ENTRYPOINT ["/double_gis_monitor/bin/double_gis_monitor"]
CMD ["start"]
