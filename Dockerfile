FROM staging as builder

COPY . /src
WORKDIR /src

RUN rm -rf _build
RUN MIX_ENV=prod mix release

FROM hexpm/elixir:1.13.3-erlang-24.3.4-alpine-3.14.5

COPY --from=builder /src/_build/prod/rel/threadbot/ /threadbot

WORKDIR /threadbot
CMD ./bin/threadbot start
