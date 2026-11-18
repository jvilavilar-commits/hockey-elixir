FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3 AS build

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force
COPY mix.exs ./
RUN mix deps.get --only prod && mix deps.compile
COPY config config
COPY lib lib
COPY priv priv
RUN mix compile && mix release

FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3
WORKDIR /app
RUN addgroup -S hockey && adduser -S hockey -G hockey
COPY --from=build --chown=hockey:hockey /app/_build/prod/rel/hockey_2d ./
USER hockey
ENV HOME=/app PORT=4000
EXPOSE 4000
CMD ["bin/hockey_2d", "start"]
