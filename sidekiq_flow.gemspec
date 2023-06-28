lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "sidekiq_flow/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq_flow"
  spec.version       = SidekiqFlow::VERSION
  spec.authors       = ["vrenaudineau"]
  spec.email         = ["vincent@coinhouse.com"]

  spec.summary       = %q{Write a short summary, because RubyGems requires one.}
  spec.description   = %q{Write a longer description or delete this line.}
  spec.homepage      = "https://github.com/ArizenHQ/sidekiq_flow"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", "~> 5.2.10", "< 6.0.0"
  spec.add_dependency "redis", "~> 4.5", "< 4.6.0"
  spec.add_dependency "activesupport", "~> 5.0"
  spec.add_runtime_dependency "sinatra", "~> 2.0"
  spec.add_runtime_dependency "thin", "~> 1.7"
  spec.add_runtime_dependency "sprockets", "~> 3.5"
  spec.add_runtime_dependency "uglifier", "~> 4.1"
  spec.add_runtime_dependency "sass", "~> 3.5"
  spec.add_runtime_dependency "timecop", "~> 0.9"

  spec.add_development_dependency "bundler", "< 3.0.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.7"
  spec.add_development_dependency "timecop", "~> 0.9.1"
  spec.add_development_dependency "fakeredis", "~> 0.7.0"
  spec.add_development_dependency "pry", "~> 0.11.3"
end
