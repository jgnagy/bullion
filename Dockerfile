FROM ruby:3.4.4 AS build

ENV RACK_ENV=development

COPY . /build

RUN apt-get update && apt-get upgrade -y && apt-get install -y libsqlite3-dev sqlite3 curl libsodium-dev build-essential libclang-dev

RUN cd /build \
    && gem build bullion.gemspec \
    && mv bullion*.gem /bullion.gem

WORKDIR /build

FROM ruby:3.4.4
LABEL maintainer="Jonathan Gnagy <jonathan.gnagy@gmail.com>"

ENV BULLION_PORT=9292
ENV RACK_ENV=production
ENV DATABASE_URL=sqlite3:///tmp/bullion.db

RUN apt-get update && apt-get upgrade -y && apt-get -y install libsqlite3-dev sqlite3 curl libsodium-dev build-essential libclang-dev

RUN mkdir /app

COPY ./scripts/docker-entrypoint.sh /entrypoint.sh
COPY --from=build /bullion.gem /app/bullion.gem
COPY ./db /app/db
COPY ./config.ru /app/config.ru
COPY ./Itsi.rb /app/Itsi.rb
COPY ./Rakefile /app/Rakefile

RUN mkdir /ssl

RUN chmod +x /entrypoint.sh \
    && chown nobody /app/db \
    && chown nobody /app/db/schema.rb \
    && chown -R nobody:nogroup /ssl \
    && chown nobody /app

WORKDIR /app

RUN gem install bullion.gem

# nobody user is uid 65534
USER 65534

EXPOSE 9292

ENTRYPOINT ["/entrypoint.sh"]
