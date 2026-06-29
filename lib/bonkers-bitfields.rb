# frozen_string_literal: true

# The gem is published as `bonkers-bitfields` but its library lives at `bitfields`
# (the require path and `Bitfields` module are unchanged from the upstream gem).
# This shim lets Bundler's auto-require resolve the gem-name path, so a plain
# `gem "bonkers-bitfields"` loads the library without needing `require: "bitfields"`.
require 'bitfields'
