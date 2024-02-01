FROM node:16 as npm_build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install

COPY esbuild.js tailwind.config.js tsconfig.json ./
COPY src src/
RUN npm run build -- --minify


FROM elixir:1.14 as mix_build
WORKDIR /app

RUN mix local.hex --force && \
  mix local.rebar --force

COPY mix.exs mix.lock VERSION ./
RUN mix deps.get --only prod

COPY lib lib/
COPY priv priv/
COPY --from=npm_build /app/priv/static priv/static/

RUN MIX_ENV=prod mix release


FROM debian:bullseye
WORKDIR /app

ARG data_dir=/data
ENV COFLUX_DATA_DIR=${data_dir}
RUN mkdir ${data_dir}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

COPY --from=mix_build /app/_build/prod/rel/coflux ./

CMD [ "/app/bin/coflux", "start" ]
