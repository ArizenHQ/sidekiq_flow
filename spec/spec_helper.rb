require 'bundler/setup'
require 'fakeredis'
require 'sidekiq/testing'
require 'sidekiq_flow'
require 'test_workflow'
require 'timecop'

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
    Sidekiq::Worker.clear_all
  end
end
