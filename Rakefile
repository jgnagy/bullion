# frozen_string_literal: true

ENV["RACK_ENV"] ||= "development"

if %w[development test].include? ENV["RACK_ENV"]
  ENV["DATABASE_URL"] = "sqlite3:#{File.expand_path(".")}/tmp/db/#{ENV["RACK_ENV"]}.sqlite3"
  require "bundler/gem_tasks"
  require "rspec/core/rake_task"
  require "rubocop/rake_task"
  require "yard"

  RSpec::Core::RakeTask.new(:spec) do |t|
    t.exclude_pattern = "spec/integration/**{,/*/**}/*_spec.rb"
    t.rspec_opts = "--require spec_helper"
  end
  RSpec::Core::RakeTask.new(:integration_testing) do |t|
    t.pattern = "spec/integration/**{,/*/**}/*_spec.rb"
    t.rspec_opts = "--require integration_helper"
  end
  RuboCop::RakeTask.new(:rubocop)
  YARD::Rake::YardocTask.new

  desc "Runs a backgrounded demo environment"
  task :demo do
    rack_env = "test"
    database_url = "sqlite3:#{File.expand_path(".")}/tmp/db/#{rack_env}.sqlite3"
    system("RACK_ENV=\"#{rack_env}\" DATABASE_URL=\"#{database_url}\" bundle exec rake db:migrate")
    system(
      "RACK_ENV=\"#{rack_env}\" DATABASE_URL=\"#{database_url}\" " \
      "LOG_LEVEL='#{ENV.fetch("LOG_LEVEL", "info")}' " \
      "itsi --daemonize"
    )
    FileUtils.touch(File.join(File.expand_path("."), "tmp", "daemon.pid"))
  end

  desc "Runs a foregrounded demo environment"
  task :foreground_demo do
    system("itsi")
  end

  desc "Cleans up test or demo environment"
  task :cleanup do
    at_exit do
      pid_file = File.join(File.expand_path("."), "tmp", "daemon.pid")
      if File.exist?(pid_file)
        system("itsi stop")
        FileUtils.rm_f(pid_file)
      end
      FileUtils.rm_f(File.join(File.expand_path("."), "tmp", "tls.crt"))
      FileUtils.rm_f(File.join(File.expand_path("."), "tmp", "tls.key"))
      FileUtils.rm_f(File.join(File.expand_path("."), "tmp", "root_tls.crt"))
      FileUtils.rm_f(File.join(File.expand_path("."), "tmp", "root_tls.key"))
      FileUtils.rm_rf(File.join(File.expand_path("."), "tmp", "db"))
      ENV["CA_DIR"] = nil
      ENV["CA_SECRET"] = nil
      ENV["CA_DOMAINS"] = nil
    end
  end

  Rake::Task["integration_testing"].enhance(["cleanup"])
end

require "openssl"
require "sqlite3"
require "trilogy"
require "sinatra/activerecord/rake"

namespace :db do
  # A hack to connect to the DB for testing
  desc "Establishes a required connection to the DB for testing and demos"
  task :load_config do
    ActiveRecord::Base.establish_connection(url: ENV.fetch("DATABASE_URL", nil))
  end
end

desc "Prepares a demo or test environment"
task :prep do
  FileUtils.mkdir_p(File.join(File.expand_path("."), "tmp"))
  ENV["CA_DIR"] = File.join(File.expand_path("."), "tmp").to_s
  ENV["CA_SECRET"] = "SomeS3cret"
  ENV["CA_DOMAINS"] = "test.domain"

  root_key = OpenSSL::PKey::RSA.new(4096)
  File.write(File.join(File.expand_path("."), "tmp", "root_tls.key"),
             root_key.to_pem(OpenSSL::Cipher.new("aes-128-cbc"), ENV.fetch("CA_SECRET", nil)))

  root_ca = OpenSSL::X509::Certificate.new
  root_ca.version = 2
  root_ca.serial = (2**rand(10..20)) - 1
  root_ca.subject = OpenSSL::X509::Name.parse(
    %w[test domain].reverse.map { "DC=#{it}" }.join("/") + "/CN=bullion"
  )
  root_ca.issuer = root_ca.subject # root CA's are "self-signed"
  root_ca.public_key = root_key.public_key
  root_ca.not_before = Time.now
  root_ca.not_after = root_ca.not_before + (5 * 365 * 24 * 60 * 60) # 5 years validity
  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = root_ca
  ef.issuer_certificate = root_ca
  root_ca.add_extension(
    ef.create_extension("basicConstraints", "CA:TRUE", true)
  )
  root_ca.add_extension(
    ef.create_extension("keyUsage", "keyCertSign, cRLSign", true)
  )
  root_ca.add_extension(
    ef.create_extension("subjectKeyIdentifier", "hash", false)
  )
  root_ca.add_extension(
    ef.create_extension("authorityKeyIdentifier", "keyid:always", false)
  )
  root_ca.sign(root_key, OpenSSL::Digest.new("SHA256"))
  File.write(File.join(File.expand_path("."), "tmp", "root_tls.crt"), root_ca.to_pem)

  intermediate_key = OpenSSL::PKey::RSA.new(4096)
  File.write(File.join(File.expand_path("."), "tmp", "tls.key"),
             intermediate_key.to_pem(OpenSSL::Cipher.new("aes-128-cbc"), ENV.fetch("CA_SECRET")))

  int_ca = OpenSSL::X509::Certificate.new
  int_ca.version = 2
  int_ca.serial = (2**rand(10..20)) - 1
  int_ca.subject = OpenSSL::X509::Name.parse(
    %w[intermediate test domain].reverse.map { |piece| "DC=#{piece}" }.join("/") + "/CN=bullion"
  )
  int_ca.issuer = root_ca.subject
  int_ca.public_key = intermediate_key.public_key
  int_ca.not_before = Time.now
  int_ca.not_after = int_ca.not_before + (2 * 365 * 24 * 60 * 60) # 2 years validity
  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = int_ca
  ef.issuer_certificate = root_ca
  int_ca.add_extension(
    ef.create_extension("basicConstraints", "CA:TRUE", true)
  )
  int_ca.add_extension(
    ef.create_extension("keyUsage", "keyCertSign, cRLSign", true)
  )
  int_ca.add_extension(
    ef.create_extension("subjectKeyIdentifier", "hash", false)
  )
  int_ca.add_extension(
    ef.create_extension("authorityKeyIdentifier", "keyid:always", false)
  )
  int_ca.sign(root_key, OpenSSL::Digest.new("SHA256"))
  File.write(
    File.join(File.expand_path("."), "tmp", "tls.crt"),
    int_ca.to_pem + root_ca.to_pem
  )
end

task test: %i[prep db:migrate spec demo integration_testing]
task unit: %i[prep db:migrate spec]

task default: %i[test rubocop yard]

task local_demo: %i[prep db:migrate foreground_demo]
