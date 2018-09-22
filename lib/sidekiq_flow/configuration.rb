module SidekiqFlow
  class Configuration
    attr_accessor :redis_url, :concurrency, :namespace, :queue, :retries, :logger

    def initialize
      @redis_url = 'redis://localhost:6379'
      @concurrency = 5
      @namespace = 'workflows'
      @queue = 'default'
      @retries = 0
      @logger = Logger.new(STDOUT)
    end

    def setup_logger
      logger.formatter = -> (severity, datetime, progname, msg) { "[%s][%s] %s\n" % [datetime, severity, msg] }
    end
  end
end
