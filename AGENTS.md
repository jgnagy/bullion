# AGENTS.md

Guidelines for AI agents and automated tools working in this repository.

## Project Overview

Bullion is a Ruby gem implementing an [ACMEv2](https://tools.ietf.org/html/rfc8555)-compatible Certificate Authority. It runs as a web service (Sinatra + [Itsi](https://itsi.fyi/)) and uses ActiveRecord for persistence.

- **Language**: Ruby 3.4
- **Framework**: Sinatra, Itsi (Rack-based)
- **ORM**: ActiveRecord (SQLite3 or [Trilogy](https://github.com/trilogy-libraries/trilogy) for MySQL/MariaDB)
- **Testing**: RSpec
- **Docs**: YARD
- **Linting**: RuboCop (rubocop-rake, rubocop-rspec)
- **Releases**: Automated via release-please on push to `main`

## Quality Gates

All three must pass before opening a PR. These run in CI (`.github/workflows/ci.yml`):

```bash
bundle exec rubocop          # Style/lint
bundle exec rake spec        # Unit tests (integration specs excluded by default)
bundle exec rake yard        # YARD documentation generation
```

Integration tests run separately: `bundle exec rake integration_testing`

## Constraints

- **Do not edit** `lib/bullion/version.rb` or `CHANGELOG.md`. These are managed by release-please.
- **Do not add runtime dependencies** without explicit justification. The gemspec is deliberately curated.
- **Do not suppress RuboCop cops inline** without a stated reason. Fix the code or adjust `.rubocop.yml` if a project-wide change is warranted.
- **Security-critical areas** — Changes to `lib/bullion/services/ca.rb`, challenge client logic, or any crypto/certificate handling must include test coverage. ACME protocol correctness is a security guarantee.
- **Respect existing structure** — Modules live under `lib/bullion/` following the established namespace layout (`Bullion::Models`, `Bullion::Services`, `Bullion::ChallengeClients`, `Bullion::Helpers`).

## Conventions

- **Conventional Commits** — `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`. Release-please generates changelogs from commit messages, so this is functional, not cosmetic.
- **Double-quoted strings** — Enforced by `.rubocop.yml` (`Style/StringLiterals`).
- **100-character line length** — Enforced by RuboCop (`Layout/LineLength`).
- **Ruby 3.4 target** — Use modern Ruby syntax; don't add compatibility shims for older versions.

## Workflow

1. **Plan before code.** Produce a design or plan before writing implementation code. Use planning/brainstorming skills as appropriate.
2. **Tests first.** Write or update tests before or alongside implementation.
3. **Minimal viable output.** Produce focused artifacts with clear structure. Don't over-engineer or add scope beyond the task.
4. **Run all quality gates** before declaring work complete.
5. **Respect project boundaries** defined in this file and in `CONTRIBUTING.md`.