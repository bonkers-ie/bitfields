require "./lib/bitfields/version"

Gem::Specification.new "bonkers-bitfields", Bitfields::VERSION do |s|
  s.summary = "Save migrations and columns by storing multiple booleans in a single integer"
  s.authors = ["Michael Grosser", "Bonkers.ie"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/bonkers-ie/bitfields"
  s.files = Dir["{lib/**/*.rb,README.md,CHANGELOG.md}"]
  s.license = "MIT"
  s.required_ruby_version = ">= 3.1"
  s.metadata = {
    "source_code_uri" => "https://github.com/bonkers-ie/bitfields",
    "changelog_uri" => "https://github.com/bonkers-ie/bitfields/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/bonkers-ie/bitfields/issues",
    "rubygems_mfa_required" => "true",
  }
  s.add_dependency "activerecord", ">= 6.1", "< 9"
  s.add_development_dependency "bump"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 3"
  s.add_development_dependency "rubocop"
  s.add_development_dependency "rubocop-performance"
  s.add_development_dependency "rubocop-rspec"
  s.add_development_dependency "sqlite3"
end
