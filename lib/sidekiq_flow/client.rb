module SidekiqFlow
  class Client
    def new
      @redis_url = SidekiqFlow.configuration.redis_url
      @concurrency = SidekiqFlow.configuration.concurrency
      @namespace = SidekiqFlow.configuration.namespace
    end

    def find_workflow(workflow_id)
      connection_pool.with do |redis|
        workflow_key = workflow_key(workflow_id)
        workflow_json = redis.get(workflow_key)
        raise "Workflow doesn't exist" if workflow_json.nil?

        tasks = redis.mget(*redis.scan_each(match: "#{workflow_key}.*")).map do |task_json|
          attrs = parse_json(task_json)
          attrs[:klass].constantize.new(attrs)
        end
        workflow_attrs = parse_json(workflow_json)
        workflow_attrs[:klass].constantize.new(workflow_attrs)
      end
    end

    def store_workflow(workflow, store_tasks=true)
      connection_pool.with do |redis|
        redis.set(workflow_key(workflow.id), workflow.to_json)
        workflow.tasks.each { |task| store_task(workflow.id, task) } if store_task
      end
    end

    def store_task(workflow_id, task)
      connection_pool.with do |redis|
        redis.set("#{workflow_key(workflow_id)}.#{task.to_json}")
      end
    end

    private

    attr_reader :redis_url, :concurrency, :namespace

    def connection_pool
      @connection_pool ||= ConnectionPool.new(size: concurrency, timeout: 5) { Redis.new(url: redis_url) }
    end

    def workflow_key(workflow_id)
      "#{namespace}.#{workflow_id}"
    end

    def parse_json(json)
      JSON.parse(json).deep_symbolize_keys
    end
  end
end
