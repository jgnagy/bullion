<img src=".images/logo.png" alt="Bullion logo" title="Bullion" align="right" height="60" />

# Bullion

Bullion is an [ACMEv2](https://tools.ietf.org/html/rfc8555)-compatible Certificate Authority (just like [Let's Encrypt](https://letsencrypt.org/)). Bullion makes it easy to leverage open standards for provisioning certificates for internal sites and services. Things like [cert-manager](https://cert-manager.io/), [certbot](https://certbot.eff.org/), and many other technologies work great with Let's Encrypt for _external_ hostnames, but for private domains and servers that aren't Internet accessible, there are few easy options.

Bullion installs easily (both as a ruby gem or a Docker image) and works with either [SQLite3](https://sqlite.org/index.html) for very small sites (where HA and high-throughput isn't a concern) or with [MariaDB](https://mariadb.org/)/[MySQL](https://www.mysql.com/) for production deployments.

The goal of the Bullion project is to make running a scalable, internal ACMEv2 CA easy. Either make a custom root CA certificate or give Bullion a signed intermediary to use in simple, compatible PEM format and you're up and running.

## Why not use...

* Let's Encrypt? Let's Encrypt is a **fantastic** service and has help make securing communication over the Internet easy and free. That said, for internal (e.g., _inside_ the firewall) communication, it isn't particularly useful.

* [Boulder](https://github.com/letsencrypt/boulder)? Let's Encrypt's Boulder is the code used by Let's Encrypt to run their public service. It is, of course, fantastic software. That said, it is a pretty complex architecture consisting of many components. It is built to scale to the needs of a huge number of public users. Per [the Boulder documentation](https://github.com/letsencrypt/boulder#production), "often Boulder is not the right fit for organizations that are evaluating it for production usage". It may meet your needs, but it is probably both overkill and more difficult to get up and running than you'll need.

* [cfssl](https://github.com/cloudflare/cfssl)? The "cfssl" project is a great tool for running a tiny CA for manually managing certs. It is certainly easier than using OpenSSL directly. While it offers an API, it isn't an ACME-compliant API and has less integration with things like Kubernetes. While I'm a fan of the project but it didn't meet my needs with creating certificates through automation and at the scale I need.

* [step-ca](https://smallstep.com/blog/private-acme-server/)? The step-ca project is a well-documented and robust CA and includes nearly all the features of Bullion. It really is wonderful, but the project takes on more than the goal of managing the provisioning of certificates via the ACME protocol. While there's no strong argument against using step-ca, it might be more complicated to setup and manage than Bullion for your scenario.

## Usage

### Prerequisites

Before running Bullion, you need a CA key pair. Bullion requires two PEM files:

- **`tls.key`** — An encrypted private key (RSA, ECDSA, or EdDSA) for signing certificates. Bullion supports encrypted PEM keys using AES-128-CBC.
- **`tls.crt`** — The corresponding public certificate. If Bullion is an intermediate CA, include the root CA's certificate in this file as well (certificate chain order: intermediate first, then root).

You can generate these with OpenSSL. For example, a self-signed root CA:

```bash
# Generate an encrypted RSA private key
openssl genrsa -aes128 -out tls.key 4096

# Create a self-signed root certificate (5 years)
openssl req -x509 -new -key tls.key -sha256 -days 1825 \
  -out tls.crt -subj "/DC=example/DC=com/CN=Bullion Root CA"
```

For production, you'll typically want an intermediate CA signed by your organization's root CA. Provide the intermediate certificate and its private key to Bullion, and include the root CA certificate in `tls.crt` so clients receive the full chain.

### Running with Docker

The quickest way to run Bullion is with the official Docker image:

```bash
docker run -d \
  --name bullion \
  -p 9292:9292 \
  -v /path/to/ssl:/ssl:ro \
  -v /path/to/data:/data \
  -e CA_DIR=/ssl \
  -e CA_SECRET=your-key-password \
  -e CA_DOMAINS=example.com \
  -e DATABASE_URL=sqlite3:/data/bullion.db \
  jgnagy/bullion:latest
```

This starts Bullion on port 9292 with:

- CA key pair mounted from `/path/to/ssl` (containing `tls.key` and `tls.crt`)
- SQLite database persisted at `/path/to/data/bullion.db`
- Certificate signing restricted to `example.com` and its subdomains

Verify it's running:

```bash
curl http://localhost:9292/ping
# {"status":"up"}
```

For MySQL/MariaDB, use a `trilogy://` connection URL instead:

```bash
-e DATABASE_URL=trilogy://user:password@mariadb:3306/bullion
```

### Running as a Gem

Install the gem:

```bash
gem install bullion
```

Bullion is a Rack application served by [Itsi](https://itsi.fyi/). After installing the gem, you'll need a `config.ru` and an `Itsi.rb` configuration file. The simplest approach is to create a working directory with your CA key pair and a minimal Rack config:

```bash
mkdir bullion-server && cd bullion-server

# Place your CA key pair here
cp /path/to/tls.key .
cp /path/to/tls.crt

# Create a minimal config.ru
cat > config.ru <<'RUBY'
# frozen_string_literal: true

require "bullion"
Bullion.validate_config!

require "prometheus/middleware/collector"
require "prometheus/middleware/exporter"

use Rack::ShowExceptions
use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter

mappings = {
  "/ping" => Bullion::Services::Ping.new,
  "/acme" => Bullion::Services::CA.new
}

run Rack::URLMap.new(mappings)
RUBY

# Initialize Itsi and run database migrations
itsi init
DATABASE_URL=sqlite3:./bullion.db bullion-exec rake db:migrate

# Start the server
CA_DIR=. CA_SECRET=your-key-password CA_DOMAINS=example.com \
  DATABASE_URL=sqlite3:./bullion.db itsi
```

### Database Setup

Bullion uses ActiveRecord migrations to create its schema. The migrations are included with the gem. Run them before starting the server:

```bash
DATABASE_URL=sqlite3:./bullion.db bundle exec rake db:migrate
```

When using Docker, the included entrypoint handles this automatically on first start. If you're running the gem directly, you may need to run migrations manually after installing the gem.

### Quick Local Demo

For testing or evaluation, the Rakefile includes a `local_demo` task that generates a temporary CA key pair, runs migrations, and starts the server in the foreground:

```bash
git clone https://github.com/jgnagy/bullion.git
cd bullion
bundle install
bundle exec rake local_demo
```

This creates a self-signed root CA and intermediate certificate in `tmp/`, uses an SQLite database in `tmp/db/`, and starts Bullion on port 9292. Press `Ctrl+C` to stop.

### Configuration Options

Whether run locally or via Docker, the following environment variables configure Bullion:

| Environment Variable | Default Value | Description |
| --- | --- | --- |
| `CA_DIR` | `./tmp/` | Path to directory container the public and private key for Bullion. |
| `CA_SECRET` | `SomeS3cret` | Secret used to read the encrypted `$CA_KEY` PEM. |
| `CA_KEY_PATH` | `$CA_DIR/tls.key` | Private signer key for Bullion. Keep this safe! |
| `CA_CERT_PATH` | `$CA_DIR/tls.crt` | Public cert for Bullion. If Bullion is an intermediate CA, you'll want to include the root CA's public cert in this file as well the signed cert for Bullion. |
| `CA_DOMAINS` | `example.com` | A comma-delimited list of domains for which Bullion will sign certificate requests. Subdomains are automatically allowed. Certificates containing other domains will be rejected. |
| `CERT_VALIDITY_DURATION` | `7776000` | How long should issued certs be valid (in seconds)? Default is 90 days. |
| `DATABASE_URL` | _None_ | **(Required)** A shorthand for telling Bullion how to connect to a database. Acceptable URLs will either begin with `sqlite3:` or [`trilogy://`](https://github.com/trilogy-libraries/trilogy/tree/main/contrib/ruby). |
| `DNS01_NAMESERVERS` | _None_ | A comma-delimited list of nameservers to use for resolving [DNS-01](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) challenges. Usually you'll want this to be set to your _internal_ nameservers so internal names resolve correctly. When not set, it'll use the host's DNS. |
| `LOG_LEVEL` | `warn` | Log level for Bullion. Supported levels (starting with the noisiest) are debug, info, warn, error, and fatal. |
| `BULLION_PORT` | `9292` | TCP port Bullion will listen on. |
| `THREADS` | `3` | Number of [Itsi threads](https://itsi.fyi/options/threads/) for processing requests. |
| `WORKERS` | `1` | Number of [Itsi workers](https://itsi.fyi/options/workers/) to spawn. |
| `WORKER_MEMORY_LIMIT` | `1024**3` | [Itsi worker memory limit](https://itsi.fyi/options/worker_memory_limit/) for each worker process (in bytes). Default is 1GiB. |
| `RACK_ENV` | `production`* | When run via Docker, the default is `production`, when run via `rake local_demo` it is `development`. Used to tell Bullion if it is run in development mode or for testing. |

### Integrating

Any client that speaks the [ACMEv2](https://tools.ietf.org/html/rfc8555) protocol can be pointed at `/acme/directory` and everything else can be auto-discovered.

Bullion also supports a non-standard directory option `caBundle` (which directs clients to `/acme/cabundle`) that responds with Bullion's PEM-encoded public key. Trusting this should automatically trust certificates signed by Bullion (eliminating browser messages about untrusted/unverified certificates).

### Monitoring

Bullion provides a `/ping` endpoint that should respond with `{ 'status': 'up' }` when Bullion is functional and ready to receive requests.

Prometheus metrics are also scrapable at `/metrics`. This includes typical web request information as well as latencies related to the different Challenge types.

## Development & Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, testing, style guidelines, and pull request expectations. Guidelines for AI agents and automated tools are in [`AGENTS.md`](AGENTS.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
