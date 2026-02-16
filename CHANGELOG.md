# Changelog

## [0.11.2](https://github.com/jgnagy/bullion/compare/bullion/v0.11.1...bullion/v0.11.2) (2026-02-16)


### Features

* add EdDSA (Ed25519) JWT signature support ([bba2985](https://github.com/jgnagy/bullion/commit/bba29851e1c5644152f4a3e82d82c6c1d5c5ce5e))
* add EdDSA (Ed25519) JWT signature support ([77a2f5b](https://github.com/jgnagy/bullion/commit/77a2f5bfc30db3527ad3fe75136b210956279957)), closes [#3](https://github.com/jgnagy/bullion/issues/3)
* Add test coverage for Ed25519 certificate signing ([59f0f74](https://github.com/jgnagy/bullion/commit/59f0f74a039292a5d804c8e49a880f20ab5d0c1b))


### Bug Fixes

* return proper badPublicKey error for Ed448 ([a21414f](https://github.com/jgnagy/bullion/commit/a21414f66075d47e2b5613d2034fa806a0a78602))

## [0.11.1](https://github.com/jgnagy/bullion/compare/bullion/v0.11.0...bullion/v0.11.1) (2025-08-24)


### Features

* add support for ECDSA CAs ([49b752e](https://github.com/jgnagy/bullion/commit/49b752ef6fde2b0543b59fb1c5977073f21b6731))


### Bug Fixes

* improve detection of SANS for cert-manager ([605f80d](https://github.com/jgnagy/bullion/commit/605f80d97135727ab9a962d6c3078b2b4a74b533))
* loading required bigdecimal gem ([98d1668](https://github.com/jgnagy/bullion/commit/98d1668da600bba890dd0eb035af4a363fa79eef))

## [0.11.0](https://github.com/jgnagy/bullion/compare/bullion/v0.10.3...bullion/v0.11.0) (2025-08-23)


### ⚠ BREAKING CHANGES

* **db:** switch to Trilogy, update db indexes

### Features

* **db:** switch to Trilogy, update db indexes ([42b90b5](https://github.com/jgnagy/bullion/commit/42b90b5977cd497b46654ecf17085715fa6db080))

## [0.10.3](https://github.com/jgnagy/bullion/compare/bullion/v0.10.2...bullion/v0.10.3) (2025-08-23)


### Bug Fixes

* making nonroot user numeric ([b286249](https://github.com/jgnagy/bullion/commit/b28624969b440d0d7fbc87ebef87a00862295183))

## [0.10.2](https://github.com/jgnagy/bullion/compare/bullion/v0.10.1...bullion/v0.10.2) (2025-08-20)


### Bug Fixes

* correct x509 certificate version to ensure x509v3 compliance ([0e8f6d7](https://github.com/jgnagy/bullion/commit/0e8f6d7bb6fc9b6913cff84390b1a5c436b53d2c))

## [0.10.1](https://github.com/jgnagy/bullion/compare/bullion/v0.10.0...bullion/v0.10.1) (2025-07-06)


### Features

* enable automatic Docker image builds ([6854692](https://github.com/jgnagy/bullion/commit/685469269d1f7e5b11c3c87bcd814225d5a26d1e))

## [0.10.0](https://github.com/jgnagy/bullion/compare/bullion/v0.9.0...bullion/v0.10.0) (2025-07-05)


### ⚠ BREAKING CHANGES

* update Docker image with Itsi configuration

### Bug Fixes

* update Docker image with Itsi configuration ([4be39dd](https://github.com/jgnagy/bullion/commit/4be39dd6200f058907029e23a07f19241705b701))

## [0.9.0](https://github.com/jgnagy/bullion/compare/bullion/v0.8.0...bullion/v0.9.0) (2025-07-05)


### ⚠ BREAKING CHANGES

* full ruby and dependency upgrade

### Miscellaneous Chores

* full ruby and dependency upgrade ([7625208](https://github.com/jgnagy/bullion/commit/7625208b1c4fa6b1acb5a0c9e7362001d66e4e08))

## [0.8.0](https://github.com/jgnagy/bullion/compare/bullion-v0.7.3...bullion/v0.8.0) (2025-03-13)


### ⚠ BREAKING CHANGES

* **deps:** require ruby 3.3+

### Miscellaneous Chores

* **deps:** require ruby 3.3+ ([2cbbf69](https://github.com/jgnagy/bullion/commit/2cbbf69b0cdb024ea800d88cfc683437cdc9e5da))
