<img src=".images/logo.png" alt="Bullion logo" title="Bullion" align="right" height="60" />

# Bullion

Bullion is an [ACMEv2](https://tools.ietf.org/html/rfc8555)-compatible Certificate Authority (just like [Let's Encrypt](https://letsencrypt.org/)). Bullion makes it easy to leverage open standards for provisioning certificates for internal sites and services. Things like [cert-manager](https://cert-manager.io/), [certbot](https://certbot.eff.org/), and many other technologies work great with Let's Encrypt for _external_ hostnames, but for private domains and servers that aren't Internet accessible, there are few easy options.

Bullion installs easily (both as a ruby gem or a Docker image) and will shortly come with Kubernetes examples and even a helm chart to make installing it that much easier. For its data, Bullion works with either [SQLite3](https://sqlite.org/index.html) for very small sites (where HA and high-throughput isn't a concern) or with [MariaDB](https://mariadb.org/)/[MySQL](https://www.mysql.com/).

## Installation

TODO: Write installation instructions

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jgnagy/bullion. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Bullion project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jgnagy/bullion/blob/master/CODE_OF_CONDUCT.md).
