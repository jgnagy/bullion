# Contributing to Bullion

Thanks for your interest in contributing! This document covers the expectations and workflow so contributions are smooth, consistent, and ready for review.

## Core Principles

- **Working code first** — Prioritize functional, tested changes over perfect documentation. Docs should be scoped and precise, not exhaustive.
- **Tests required** — Every behavioral change must include or update automated tests. CI runs `rake spec`; PRs that don't pass won't be reviewed.
- **Style is enforced** — RuboCop runs in CI with the project's `.rubocop.yml` config. Fix warnings locally before pushing.
- **Minimal dependencies** — The gemspec is deliberately curated. Don't add runtime dependencies without justification.
- **Security matters** — Bullion is a Certificate Authority. Changes to ACME protocol handling, crypto, or certificate issuance must include tests and warrant extra scrutiny.

## Getting Started

1. Fork the repo and clone your fork.
2. Run `bin/setup` to install dependencies.
3. Run `rake spec` to verify a clean baseline.
4. Use `bin/console` for an interactive prompt to experiment.

## Development Workflow

1. Write or update tests first (TDD encouraged).
2. Implement your changes.
3. Run quality checks before pushing:

   ```bash
   bundle exec rubocop
   bundle exec rake spec
   bundle exec rake yard
   ```

4. Open a Pull Request with a clear description.

### Integration Tests

The default `rake spec` task excludes integration specs. Run them separately with:

```bash
bundle exec rake integration_testing
```

Integration specs are not required for PRs but are appreciated for changes that affect ACME protocol flows.

## Branching & Commits

- Use feature branches: `feature/<short-description>` or `fix/<short-description>`.
- Follow [Conventional Commits](https://www.conventionalcommits.org/):
  - `feat: add ECDSA order support`
  - `fix: correct nonce validation timing`
  - `docs: update configuration reference`
  - `refactor: extract challenge client logic`
  - `test: add HTTP-01 challenge coverage`
  - `chore: bump dependency versions`
- Keep commits focused and logically grouped. Avoid mixing unrelated changes.

Conventional Commits are not just style — releases are automated via [release-please](https://github.com/googleapis/release-please), which generates the changelog from commit messages. Following the convention directly affects the quality of release notes.

## Releases

**Do not manually edit `lib/bullion/version.rb` or `CHANGELOG.md`.**

Releases are fully automated via release-please on push to `main`. When a release PR is merged, the workflow:

- Bumps the version in `lib/bullion/version.rb`
- Updates `CHANGELOG.md` from Conventional Commits
- Builds and publishes the gem to RubyGems
- Builds and pushes Docker images to Docker Hub (`jgnagy/bullion:latest`, version, and major.minor tags)

If a release is needed manually, coordinate with the maintainer rather than editing version files directly.

## Pull Request Guidelines

A good PR includes:

- **Summary** — What changed and why.
- **Scope** — Which part of the system (ACME protocol, models, challenge clients, config, docs).
- **Testing** — Outline of added tests and coverage areas.
- **Security Impact** — Any effects on certificate issuance, challenge validation, or crypto.

PRs may be declined or requested for revision if:

- Tests are missing or incomplete.
- RuboCop or YARD checks fail.
- New dependencies are added without justification.
- Unrelated changes are mixed together (split them up).

## Code of Conduct

Everyone interacting in the Bullion project is expected to follow the [Contributor Covenant](http://contributor-covenant.org) code of conduct. See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for details.

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE.txt).