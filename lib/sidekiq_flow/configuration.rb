module SidekiqFlow
  class Configuration
    attr_accessor :redis_url,
                  :connection_pool,
                  :concurrency,
                  :namespace,
                  :queue,
                  :retries,
                  :logger,
                  :timeout

    def initialize
      @redis_url = 'redis://localhost:6379'
      @concurrency = 10
      @namespace = 'workflows'
      @queue = 'default'
      @retries = 0
      @logger = Logger.new(STDOUT)
      @timeout = 10
    end

    def setup_logger
      logger.formatter = -> (severity, datetime, progname, msg) { "[%s][%s] %s\n" % [datetime, severity, msg] }
    end

    def setup_connection_pool
      @connection_pool = ConnectionPool.new(size: concurrency, timeout: timeout) do
        Redis.new(url: redis_url)
      end
    end
  end
end
