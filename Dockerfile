FROM hexpm/elixir:1.13.3-erlang-24.3.4-alpine-3.14.5

COPY . src
WORKDIR src

RUN mix local.rebar --force
RUN mix local.hex --force
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix release --overwrite

CMD _build/prod/rel/threadbot/bin/threadbot start
