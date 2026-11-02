FROM ruby:4.0.9 AS build

ENV RACK_ENV=development

# Build toolchain and headers for native extensions. These packages (and their
# compilers) stay in this stage; only the installed gem tree is copied forward.
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
      build-essential libclang-dev libsqlite3-dev libsodium-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . /build

WORKDIR /build

RUN gem build bullion.gemspec \
    && mv bullion*.gem /bullion.gem

# Install the gem (compiling native extensions) while the toolchain is still
# available. The gems land in the base image's GEM_HOME, which is copied into
# the runtime stage below at the same path.
RUN gem install --no-document /bullion.gem

FROM ruby:4.0.9-slim
LABEL maintainer="Jonathan Gnagy <jonathan.gnagy@gmail.com>"

ENV BULLION_PORT=9292
ENV RACK_ENV=production
ENV DATABASE_URL=sqlite3:///tmp/bullion.db

# Runtime-only image: the apt build toolchain (build-essential, libclang-dev,
# *-dev headers, curl) deliberately stays in the build stage. The slim ruby
# base already provides the shared libraries the installed extensions link
# against (libc, libm, libz, libssl/libcrypto, libgmp, libyaml), so no apt
# layer is needed here.

RUN mkdir /app

COPY ./scripts/docker-entrypoint.sh /entrypoint.sh
COPY --from=build /usr/local/bundle /usr/local/bundle
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

# nobody user is uid 65534
USER 65534

EXPOSE 9292

ENTRYPOINT ["/entrypoint.sh"]
