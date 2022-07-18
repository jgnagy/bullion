#!/bin/sh

apt-get update && apt-get install -y libsodium-dev

gem install bundler -v '~> 2.3'
bundle install
rm -rf pkg/*.gem
bundle exec rake build
bundle exec gem push pkg/*.gem
