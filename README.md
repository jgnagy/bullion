<img src=".images/logo.png" alt="Bullion logo" title="Bullion" align="right" height="60" />

# Bullion

Bullion is an [ACMEv2](https://tools.ietf.org/html/rfc8555)-compatible Certificate Authority (just like [Let's Encrypt](https://letsencrypt.org/)). Bullion makes it easy to leverage open standards for provisioning certificates for internal sites and services. Things like [cert-manager](https://cert-manager.io/), [certbot](https://certbot.eff.org/), and many other technologies work great with Let's Encrypt for _external_ hostnames, but for private domains and servers that aren't Internet accessible, there are few easy options.

Bullion installs easily (both as a ruby gem or a Docker image) and will shortly come with Kubernetes examples and even a helm chart to make installing it that much easier. For its data, Bullion works with either [SQLite3](https://sqlite.org/index.html) for very small sites (where HA and high-throughput isn't a concern) or with [MariaDB](https://mariadb.org/)/[MySQL](https://www.mysql.com/).

The goal of the Bullion project is to make running a scalable, internal ACMEv2 CA easy. Either make a custom root CA certificate or give Bullion a signed intermediary to use in simple, compatible PEM format and you're up and running.

## Why not use...

* Let's Encrypt? Let's Encrypt is a **fantastic** service and has help make securing communication over the Internet easy and free. That said, for internal (e.g., _inside_ the firewall) communication, it isn't particularly useful.

* [Boulder](https://github.com/letsencrypt/boulder)? Let's Encrypt's Boulder is the code used by Let's Encrypt to run their public service. It is, of course, fantastic software. That said, it is a pretty complex architecture consisting of many components. It is built to scale to the needs of a huge number of public users. Per [the Boulder documentation](https://github.com/letsencrypt/boulder#production), "often Boulder is not the right fit for organizations that are evaluating it for production usage". It may meet your needs, but it is probably both overkill and more difficult to get up and running than you'll need.

* [cfssl](https://github.com/cloudflare/cfssl)? The "cfssl" project is a great tool for running a tiny CA for manually managing certs. It is certainly easier than using OpenSSL directly. While it offers an API, it isn't an ACME-compliant API and has less integration with things like Kubernetes. While I'm a fan of the project but it didn't meet my needs with creating certificates through automation and at the scale I need.

* [step-ca](https://smallstep.com/blog/private-acme-server/)? The step-ca project is a well-documented and robust CA and includes nearly all the features of Bullion. It really is wonderful, but the project takes on more than the goal of managing the provisioning of certificates via the ACME protocol. While there's no strong argument against using step-ca, it might be more complicated to setup and manage than Bullion for your scenario.

## Usage

### Running

TODO: Write instructions for starting Bullion

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
| `DATABASE_URL` | _None_ | A shorthand for telling Bullion how to connect to a database. Acceptable URLs will either being with `sqlite3:` or [`mysql2://`](https://github.com/brianmario/mysql2#using-active-records-database_url). |
| `DNS01_NAMESERVERS` | `8.8.8.8` | A comma-delimited list of nameservers to use for resolving [DNS-01](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) challenges. Usually you'll want this to be set to your _internal_ nameservers so internal names resolve correctly. |
| `LOG_LEVEL` | `warn` | Log level for Bullion. Supported levels (starting with the noisiest) are debug, info, warn, error, and fatal. |
| `BULLION_PORT` | `9292` | TCP port Bullion will listen on. |
| `MIN_THREADS` | `2` | Minimum number of [Puma](https://puma.io/) threads for processing requests. |
| `MAX_THREADS` | `32` | Maximum number of [Puma](https://puma.io/) threads for processing requests. |
| `RACK_ENV` | `production`* | When run via Docker, the default is `production`, when run via `rake local_demo` it is `development`. Used to tell Bullion if it is run in development mode or for testing. |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jgnagy/bullion. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Bullion project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jgnagy/bullion/blob/master/CODE_OF_CONDUCT.md).
