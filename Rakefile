# frozen_string_literal: true

ENV["RACK_ENV"] ||= "development"

if %w[development test].include? ENV["RACK_ENV"]
  ENV["DATABASE_URL"] = "sqlite3:#{File.expand_path(".")}/tmp/db/#{ENV["RACK_ENV"]}.sqlite3"
end

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "yard"
require "openssl"
require "sqlite3"
require "sinatra/activerecord/rake"

namespace :db do
  task :load_config do
    ActiveRecord::Base.establish_connection(url: ENV.fetch("DATABASE_URL", nil))
  end
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)
YARD::Rake::YardocTask.new

task :prep do
  FileUtils.mkdir_p(File.join(File.expand_path("."), "tmp"))
  ENV["CA_DIR"] = File.join(File.expand_path("."), "tmp").to_s
  ENV["CA_SECRET"] = "SomeS3cret"
  ENV["CA_DOMAINS"] = "test.domain"

  key = OpenSSL::PKey::RSA.new(4096)
  File.write(File.join(File.expand_path("."), "tmp", "tls.key"),
             key.to_pem(OpenSSL::Cipher.new("aes-128-cbc"), ENV.fetch("CA_SECRET", nil)))

  root_ca = OpenSSL::X509::Certificate.new
  root_ca.version = 2
  root_ca.serial = (2**rand(10..20)) - 1
  root_ca.subject = OpenSSL::X509::Name.parse(
    %w[test domain].reverse.map { |piece| "DC=#{piece}" }.join("/") + "/CN=bullion"
  )
  root_ca.issuer = root_ca.subject # root CA's are "self-signed"
  root_ca.public_key = key.public_key
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
  root_ca.sign(key, OpenSSL::Digest.new("SHA256"))
  File.write(File.join(File.expand_path("."), "tmp", "tls.crt"), root_ca.to_pem)
end

task :demo do
  system("rackup -D -P #{File.expand_path(".")}/tmp/daemon.pid")
end

task :foreground_demo do
  system("rackup -P #{File.expand_path(".")}/tmp/daemon.pid")
end

task :cleanup do
  at_exit do
    if File.exist?("#{File.expand_path(".")}/tmp/daemon.pid")
      system("kill $(cat #{File.expand_path(".")}/tmp/daemon.pid)")
    end
    FileUtils.rm_f(File.join(File.expand_path("."), "tmp", "tls.crt"))
    FileUtils.rm_f(File.join(File.expand_path("."), "tmp", "tls.key"))
    FileUtils.rm_rf(File.join(File.expand_path("."), "tmp", "db"))
    ENV["CA_DIR"] = nil
    ENV["CA_SECRET"] = nil
    ENV["CA_DOMAINS"] = nil
  end
end

Rake::Task["spec"].enhance(["cleanup"])

task default: %i[prep db:migrate demo spec rubocop]

task test: %i[prep db:migrate demo spec]

task local_demo: %i[prep db:migrate foreground_demo]
