require 'bundler/setup'
require 'bitfields/rspec'
require 'bitfields'
require 'timeout'

require 'active_record'

require_relative 'database'

# The legacy example models below use the positional shorthand on purpose; silence the warning
# for them. Dedicated examples flip this back to :warn / :forbid to exercise the policy.
Bitfields.positional_bits = :allow

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.syntax = :expect }
end
