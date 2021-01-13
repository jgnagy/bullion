# frozen_string_literal: true

require 'simplecov'
require 'bundler/setup'
require 'acme-client'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [SimpleCov::Formatter::HTMLFormatter]
)

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/.bundle/'
end

require 'rack/test'
require 'bullion'

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

RSpec.configure do |config|
  config.include Rack::Test::Methods

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
