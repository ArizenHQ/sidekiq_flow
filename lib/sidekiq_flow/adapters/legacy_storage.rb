module SidekiqFlow
    module Adapters
      class LegacyStorage
        SCAN_COUNT = 2000

        class << self
      
          def store_workflow(workflow, initial=false)
            workflow_key = initial ? generate_initial_workflow_key(workflow.id) : find_workflow_key(workflow.id)
            connection_pool.with do |redis|
              redis.hmset(
                workflow_key,
                [:klass, workflow.klass, :attrs, workflow.to_json] + workflow.tasks.map { |t| [t.klass, t.to_json] }.flatten
              )
            end
          end
      
          def store_task(task)
            connection_pool.with do |redis|
              redis.hset(find_workflow_key(task.workflow_id), task.klass, task.to_json)
            end
            return unless workflow_succeeded?(task.workflow_id)
            succeed_workflow(task.workflow_id)
          end
      
          def find_workflow(workflow_id)
            connection_pool.with do |redis|
              workflow_redis_hash = redis.hgetall(find_workflow_key(workflow_id))
              raise WorkflowNotFound if workflow_redis_hash.empty?
              Workflow.from_redis_hash(workflow_redis_hash)
            end
          end
      
          def destroy_workflow(workflow_id)
            connection_pool.with do |redis|
              redis.del(find_workflow_key(workflow_id))
            end
          end
      
          def destroy_succeeded_workflows
            workflow_keys = find_workflow_keys(succeeded_workflow_key_pattern)
            return if workflow_keys.empty?
            connection_pool.with do |redis|
              redis.del(*workflow_keys)            
            end
          end
      
          def find_workflow_keys(pattern=workflow_key_pattern)
            connection_pool.with do |redis|
              redis.scan_each(match: pattern, count: SCAN_COUNT).to_a
            end
          end

          def find_workflow_key(workflow_id)
            key_pattern = "#{configuration.namespace}.#{workflow_id}_*"
    
            find_first(key_pattern)
          end
      
          def connection_pool
            @connection_pool ||= ConnectionPool.new(size: configuration.concurrency, timeout: configuration.timeout) do
              Redis.new(url: configuration.redis_url)
            end
          end

          def find_first(key_pattern)
            result = nil
      
            connection_pool.with do |redis|
              cursor = "0"
              loop do
                cursor, keys = redis.scan(
                          cursor,
                          match: key_pattern,
                          count: SCAN_COUNT
                        )
      
                result = keys.first
      
                break if (result || cursor == "0")
              end
            end
      
            result
          end
      
          private

          def configuration
            @configuration ||= SidekiqFlow.configuration
          end

          def generate_initial_workflow_key(workflow_id)
            "#{configuration.namespace}.#{workflow_id}_#{Time.now.to_i}_0"
          end

          def workflow_succeeded?(workflow_id)
            find_workflow(workflow_id).succeeded?
          end

          def succeed_workflow(workflow_id)
            current_key = find_workflow_key(workflow_id)
      
            # NOTE: Race condition. Some other task might have renamed/deleted the key already.
            return if current_key.blank?
      
            return if already_succeeded?(workflow_id, current_key)
      
            connection_pool.with do |redis|
              redis.rename(current_key, current_key.chop.concat(Time.now.to_i.to_s))
            end
          end

          def succeeded_workflow_key_pattern
            "#{configuration.namespace}.*_*_[^0]*"
          end
            
          def already_succeeded?(workflow_id, workflow_key)
            workflow_key.match(/#{configuration.namespace}\.#{workflow_id}_\d{10}_\d{10}/)
          end
    
        end
      end
    end
  end
  