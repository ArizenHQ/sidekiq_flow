module SidekiqFlow
  class Configuration
    attr_accessor :redis_url, :concurrency, :namespace, :queue, :retries

    def initialize(redis_url: '', concurrency: 5, namespace: 'workflows', queue: 'default', retries: 0)
      @redis_url = redis_url
      @concurrency = concurrency
      @namespace = namespace
      @queue = queue
      @retries = retries
    end
  end
end
