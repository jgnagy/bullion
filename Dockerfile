FROM ruby:3.2 AS build

ENV RACK_ENV=development

COPY . /build

RUN apt-get update && apt-get upgrade -y && apt-get install -y libsqlite3-dev sqlite3 curl libsodium-dev

RUN cd /build \
    && gem build bullion.gemspec \
    && mv bullion*.gem /bullion.gem

WORKDIR /build

FROM ruby:3.2
LABEL maintainer="Jonathan Gnagy <jonathan.gnagy@gmail.com>"

ENV BULLION_PORT=9292
ENV BULLION_ENVIRONMENT=development
ENV DATABASE_URL=sqlite3:///tmp/bullion.db

RUN apt-get update && apt-get upgrade -y && apt-get -y install libsqlite3-dev sqlite3 curl libsodium-dev

RUN mkdir /app

COPY ./scripts/docker-entrypoint.sh /entrypoint.sh
COPY --from=build /bullion.gem /app/bullion.gem
COPY ./db /app/db
COPY ./config.ru /app/config.ru
COPY ./Rakefile /app/Rakefile

RUN mkdir /ssl

RUN chmod +x /entrypoint.sh \
    && chown nobody /app/db \
    && chown nobody /app/db/schema.rb \
    && chown -R nobody:nogroup /ssl

WORKDIR /app

RUN gem install bullion.gem

USER nobody

ENTRYPOINT ["/entrypoint.sh"]
