# Stage 1: build
FROM elixir:1.16.2-otp-26-alpine AS builder

ENV MIX_ENV=prod

WORKDIR /build/double_gis_monitor

RUN apk update \
    && apk add --no-cache git

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
FROM alpine:latest AS runner

RUN apk update \
    && apk add --no-cache libstdc++ libgcc ncurses-libs

COPY --from=builder /double_gis_monitor /double_gis_monitor

EXPOSE 5432

ENTRYPOINT ["/double_gis_monitor/bin/double_gis_monitor"]
CMD ["start"]
