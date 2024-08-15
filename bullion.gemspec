# frozen_string_literal: true

require_relative "lib/bullion/version"

Gem::Specification.new do |spec|
  spec.name          = "bullion"
  spec.version       = Bullion::VERSION
  spec.authors       = ["Jonathan Gnagy"]
  spec.email         = ["jonathan.gnagy@gmail.com"]

  spec.summary       = "Ruby ACME v2 Certificate Authority"
  spec.homepage      = "https://github.com/jgnagy/bullion"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jgnagy/bullion"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = "~> 3.2"

  spec.add_dependency "dry-configurable",     "~> 1.1"
  spec.add_dependency "httparty",             "~> 0.21"
  spec.add_dependency "json",                 "~> 2.6"
  spec.add_dependency "jwt",                  "~> 2.7"
  spec.add_dependency "mysql2",               "~> 0.5"
  spec.add_dependency "openssl",              "~> 3.0"
  spec.add_dependency "prometheus-client",    "~> 4.2"
  spec.add_dependency "puma",                 "~> 6.4"
  spec.add_dependency "sinatra",              "~> 3.1"
  spec.add_dependency "sinatra-activerecord", "~> 2.0"
  spec.add_dependency "sinatra-contrib",      "~> 3.1"
  spec.add_dependency "sqlite3",              "~> 1.6"

  spec.add_development_dependency "acme-client",         "~> 2.0"
  spec.add_development_dependency "bundler",             "~> 2.4"
  spec.add_development_dependency "byebug",              "~> 11"
  spec.add_development_dependency "rack-test",           "~> 2.1"
  spec.add_development_dependency "rake",                "~> 13.1"
  spec.add_development_dependency "rspec",               "~> 3.12"
  spec.add_development_dependency "rubocop",             "~> 1.57"
  spec.add_development_dependency "rubocop-rake",        "~> 0.6"
  spec.add_development_dependency "rubocop-rspec",       "~> 2.25"
  spec.add_development_dependency "simplecov",           "~> 0.22"
  spec.add_development_dependency "simplecov-cobertura", "~> 2.1"
  spec.add_development_dependency "solargraph",          "~> 0.49"
  spec.add_development_dependency "yard",                "~> 0.9"
end
