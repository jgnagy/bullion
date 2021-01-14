# frozen_string_literal: true

require_relative 'lib/bullion/version'

Gem::Specification.new do |spec|
  spec.name          = 'bullion'
  spec.version       = Bullion::VERSION
  spec.authors       = ['Jonathan Gnagy']
  spec.email         = ['jonathan.gnagy@gmail.com']

  spec.summary       = 'Ruby ACME v2 Certificate Authority'
  spec.homepage      = 'https://github.com/jgnagy/bullion'
  spec.license       = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/jgnagy/bullion'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '~> 2.6'

  spec.add_runtime_dependency 'httparty',             '~> 0.18'
  spec.add_runtime_dependency 'json',                 '~> 2.5'
  spec.add_runtime_dependency 'jwt',                  '~> 1.5'
  spec.add_runtime_dependency 'mysql2',               '~> 0.5'
  spec.add_runtime_dependency 'openssl',              '~> 2.2'
  spec.add_runtime_dependency 'prometheus-client',    '~> 2.1'
  spec.add_runtime_dependency 'puma',                 '~> 3.12'
  spec.add_runtime_dependency 'sinatra',              '~> 2.1'
  spec.add_runtime_dependency 'sinatra-activerecord', '~> 2.0'
  spec.add_runtime_dependency 'sinatra-contrib',      '~> 2.1'
  spec.add_runtime_dependency 'sqlite3',              '~> 1.4'

  spec.add_development_dependency 'acme-client',         '~> 2.0'
  spec.add_development_dependency 'bundler',             '~> 2.0'
  spec.add_development_dependency 'byebug',              '~> 9'
  spec.add_development_dependency 'rack-test',           '~> 0.8'
  spec.add_development_dependency 'rake',                '~> 12.3'
  spec.add_development_dependency 'rspec',               '~> 3.10'
  spec.add_development_dependency 'rubocop',             '~> 0.93'
  spec.add_development_dependency 'simplecov',           '~> 0.20'
  spec.add_development_dependency 'simplecov-cobertura', '~> 1.4'
  # spec.add_development_dependency 'yard',                '~> 0.9'
end
