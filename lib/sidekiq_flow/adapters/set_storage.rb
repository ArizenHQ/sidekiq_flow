module SidekiqFlow
  module Adapters
    class SetStorage
      IN_PROGRESS = 'workflows.set.in-progress'.freeze
      FINISHED = 'workflows.set.finished'.freeze

      attr_reader :configuration

      def initialize(configuration)
        @configuration = configuration
      end

      def store_workflow(workflow, initial = false)
        workflow_key = workflow_key(workflow.id)

        current_time = Time.now.to_i

        workflow.updated_at_timestamp = current_time
        if initial
          workflow.start_timestamp = current_time
          workflow.current_workflow_set = IN_PROGRESS
        end

        connection_pool.with do |redis|
          redis.pipelined do
            redis.sadd(IN_PROGRESS, workflow_key) if initial
            redis.hmset(
              workflow_key,
              [:klass, workflow.klass, :attrs, workflow.to_json] + workflow.tasks.map { |t| [t.klass, t.to_json] }.flatten
            )
          end
        end
      end

      def store_task(task)
        connection_pool.with do |redis|
          redis.hset(workflow_key(task.workflow_id), task.klass, task.to_json)
        end

        return unless workflow_succeeded?(task.workflow_id)

        succeed_workflow(task.workflow_id)
      end

      def find_workflow(workflow_id)
        connection_pool.with do |redis|
          workflow_redis_hash = redis.hgetall(workflow_key(workflow_id))
          raise WorkflowNotFound if workflow_redis_hash.empty?

          Workflow.from_redis_hash(workflow_redis_hash)
        end
      end

      def destroy_workflow(workflow_id)
        workflow_key = workflow_key(workflow_id)

        connection_pool.with do |redis|
          redis.pipelined do
            redis.del(workflow_key)
            redis.srem(FINISHED, workflow_key)
          end
        end
      end

      def destroy_succeeded_workflows
        workflow_keys = []

        connection_pool.with do |redis|
          workflow_keys = redis.smembers(FINISHED)
        end

        return if workflow_keys.empty?

        connection_pool.with do |redis|
          redis.pipelined do
            redis.del(*workflow_keys)
            redis.srem(FINISHED, workflow_keys)
          end
        end
      end

      def workflow_key(workflow_id)
        "#{configuration.namespace}.set.#{workflow_id}"
      end

      alias_method :find_workflow_key, :workflow_key

      def already_started?(workflow_id)
        workflow_key = workflow_key(workflow_id)

        connection_pool.with do |redis|
          redis.sismember(IN_PROGRESS, workflow_key)
        end
      end

      def connection_pool
        @connection_pool ||= configuration.connection_pool
      end

      private

      def generate_initial_workflow_key(workflow_id)
        "#{configuration.namespace}.set.#{workflow_id}"
      end

      def workflow_succeeded?(workflow_id)
        find_workflow(workflow_id).succeeded?
      end

      def succeed_workflow(workflow_id)
        workflow_key = workflow_key(workflow_id)

        current_time = Time.now.to_i

        workflow = find_workflow(workflow_id)
        workflow.end_timestamp = current_time
        workflow.updated_at_timestamp = current_time
        workflow.current_workflow_set = FINISHED

        connection_pool.with do |redis|
          redis.pipelined do
            redis.smove(IN_PROGRESS, FINISHED, workflow_key)
            redis.hmset(
              workflow_key,
              [:klass, workflow.klass, :attrs, workflow.to_json] + workflow.tasks.map { |t| [t.klass, t.to_json] }.flatten
            )
          end
        end
      end

      def already_succeeded?(workflow_key)
        connection_pool.with do |redis|
          redis.sismember(FINISHED, workflow_key)
        end
      end
    end
  end
end
