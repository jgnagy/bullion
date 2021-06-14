#!/bin/sh

gem install bundler
bundle install --jobs=4
gem build ./bullion.gemspec
bundle exec rake
