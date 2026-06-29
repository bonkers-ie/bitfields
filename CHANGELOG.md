# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (breaking)
- **Renamed the published gem to `bonkers-bitfields`.** The required library path
  (`require "bitfields"`) and the `Bitfields` module are unchanged, so `include Bitfields`
  and all generated methods keep working — only the `Gemfile` entry changes.
- **Positional bit declarations now warn by default.** `bitfield :flags, :a, :b, :c` maps each
  symbol to `2**index`, so inserting, removing, or reordering a symbol silently shifts every later
  bit. The new `Bitfields.positional_bits` setting controls this: `:warn` (default) emits a
  warning, `:forbid` raises, `:allow` restores the old silent behaviour. Prefer the explicit
  `bitfield :flags, 1 => :a, 2 => :b, 4 => :c` form, which locks each name to its bit.
- **Duplicate bit names across columns now raise `DuplicateBitNameError` at declaration time.**
  Previously a name reused in two columns silently resolved to the first column. Bit names must be
  unique per model.

### Added
- `Bitfields.positional_bits` configuration (`:warn` / `:forbid` / `:allow`).
- `nil` / `:_skip` placeholders are allowed in positional declarations to reserve a bit position
  without shifting later bits.
- `with_bitfields` / `without_bitfields` class query methods (resolves the long-standing README
  TODO), built on Arel so they survive eager-load table aliasing (resolves
  [#45](https://github.com/grosser/bitfields/issues/45)).
- GitHub Actions CI (`.github/workflows/ci.yml`) now lints and runs the test matrix on **every
  branch** as well as pull requests, with concurrent superseded runs cancelled.
- Release workflow (`.github/workflows/release.yml`) that publishes the gem to RubyGems via
  [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (OIDC, no stored API key)
  when a `v*` tag is pushed.

### Fixed
- Cross-column duplicate bit names no longer silently misbehave
  ([#21](https://github.com/grosser/bitfields/issues/21)).
- README SQL examples (`(users.my_bits & 6) = 2`; `users.my_bits` table reference).
- Duplicated assertion line in the RSpec `have_a_bitfield` matcher.

### Removed
- Travis CI (replaced with GitHub Actions) and the `wwtd` development dependency.
- Support for Ruby < 3.1 and ActiveRecord < 6.1.
