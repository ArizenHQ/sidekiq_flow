module SidekiqFlow
  class Task < Model
    STATUS_PENDING = 'pending'
    STATUS_ENQUEUED = 'enqueued'
    STATUS_SUCCEEDED = 'succeeded'
    STATUS_FAILED = 'failed'
    STATUS_SKIPPED = 'skipped'
    STATUS_AWAITING_RETRY = 'awaiting_retry'

    def self.attribute_names
      [
        :start_date, :end_date, :loop_interval, :retries, :queue, :inline,
        :children, :status, :trigger_rule, :params, :error_msg
      ]
    end

    attr_reader :workflow, :workflow_id, :workflow_params, :parents

    def initialize(attrs = {})
      super
      @start_date = attrs.fetch(:start_date, Time.now.to_i) # may return nil for manual start
      @end_date = attrs[:end_date]
      @loop_interval = attrs[:loop_interval] || 0
      @retries = attrs[:retries] || SidekiqFlow.configuration.retries
      @queue = attrs[:queue] || SidekiqFlow.configuration.queue
      @children = attrs[:children] || []
      @status = attrs[:status] || STATUS_PENDING
      @trigger_rule = attrs[:trigger_rule] || ['all_succeeded', {}]
      @params = attrs[:params] || {}
      @parents = attrs[:parents] || []
      @inline = attrs[:inline] || false
      @error_msg = attrs[:error_msg]
    end

    def perform
      raise NotImplementedError
    end

    def enqueue!
      @status = STATUS_ENQUEUED
    end

    def succeed!
      @status = STATUS_SUCCEEDED
    end

    def fail!
      @status = STATUS_FAILED
    end

    def skip!
      @status = STATUS_SKIPPED
    end

    # this method prepares this task to be manually restarted
    def clear!
      @status = STATUS_PENDING
    end

    # this method prepares this task to be manually restarted
    def clear_dates!
      # make the task be a manual one
      @start_date = nil

      # clear end date (most cases it's already expired)
      @end_date = nil
    end

    def await_retry!
      @status = STATUS_AWAITING_RETRY
    end

    def set_queue!(queue)
      @queue = queue
    end

    def set_error_msg!(msg)
      @error_msg = msg
    end

    def enqueued?
      @status == STATUS_ENQUEUED
    end

    def succeeded?
      @status == STATUS_SUCCEEDED
    end

    def failed?
      @status == STATUS_FAILED
    end

    def skipped?
      @status == STATUS_SKIPPED
    end

    def pending?
      @status == STATUS_PENDING
    end

    def awaiting_retry?
      @status == STATUS_AWAITING_RETRY
    end

    def no_retries?
      retries == 0
    end

    def expired?
      end_date.present? && Time.now.to_i > end_date
    end

    def external_trigger?
      start_date.nil?
    end

    def ready_to_start?
      pending? && !external_trigger? && trigger_rule_instance.met?
    end

    # When task is ready to start, it can be run inline if start date is not too far in the future.
    def ready_to_perform_inline?
      inline? && start_date < 1.second.from_now
    end

    def auto_succeed?
      false
    end

    def inline?
      @inline == true
    end

    def set_workflow_data!(workflow, workflow_params)
      @workflow, @workflow_params = workflow, workflow_params
      @workflow_id = workflow.id
    end

    private

    def trigger_rule_instance
      @trigger_rule_instance ||= TaskTriggerRules::Base.build(trigger_rule[0], trigger_rule[1], workflow, parents)
    end
  end
end
