require 'bundler/setup'
require 'sidekiq_flow'

# Sidekiq 8.1 deprecates require 'sidekiq/testing' in favor of Sidekiq.testing!
if Sidekiq.respond_to?(:testing!)
  Sidekiq.testing!(:fake)
else
  require 'sidekiq/testing'
end
require 'test_workflow'
require 'timecop'

SidekiqFlow.configuration.redis_url = ENV['REDIS_URL'] if ENV['REDIS_URL']
$redis = Redis.new(url: SidekiqFlow.configuration.redis_url)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    $redis.flushdb
    Sidekiq::Job.clear_all
  end
end
