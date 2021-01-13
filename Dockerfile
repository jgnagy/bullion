FROM ruby:2.6-alpine AS build

ENV RACK_ENV=development

COPY . /build

RUN apk --no-cache upgrade \
    && apk --no-cache add git mariadb-client mariadb-connector-c \
       runit sqlite-dev \
    && apk --no-cache add --virtual build-dependencies \
       build-base mariadb-dev

RUN apk add build-base \
    && cd /build \
    && gem build bullion.gemspec \
    && mv bullion*.gem /bullion.gem

WORKDIR /build

FROM ruby:2.6-alpine
LABEL maintainer="Jonathan Gnagy <jonathan.gnagy@gmail.com>"

ENV BULLION_PORT=9292
ENV BULLION_ENVIRONMENT=development
ENV DATABASE_URL=sqlite3:///tmp/bullion.db

RUN apk --no-cache upgrade \
    && apk --no-cache add git mariadb-client mariadb-connector-c \
       runit sqlite-dev \
    && apk --no-cache add --virtual build-dependencies \
       build-base mariadb-dev

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

RUN gem install bullion.gem \
    && apk del build-dependencies

USER nobody

ENTRYPOINT ["/entrypoint.sh"]
