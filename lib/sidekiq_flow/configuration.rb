module SidekiqFlow
  class Configuration
    attr_accessor :redis_url, :concurrency, :namespace, :queue, :retries

    def initialize(opts={})
      @redis_url = opts[:redis_url] || 'redis://localhost:6379'
      @concurrency = opts[:concurrency] || 5
      @namespace = opts[:namespace] || 'workflows'
      @queue = opts[:queue] || 'default'
      @retries = opts[:retries] || 0
    end
  end
end
