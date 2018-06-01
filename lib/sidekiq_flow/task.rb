module SidekiqFlow
  class Task < Model
    Statuses = Types::Strict::String.default('pending').enum('pending', 'enqueued' 'running', 'succeeded', 'failed', 'skipped')
    Results = Types::Strict::Symbol.enum(:success, :skip, :repeat)

    attribute :start_date, (Types::Strict::Nil | Types::Strict::Integer).meta(omittable: true)
    attribute :end_date, Types::Strict::Integer.meta(omittable: true)
    attribute :loop_interval, Types::Strict::Integer.default(0)
    attribute :retries, Types::Strict::Integer.default { SidekiqFlow.configuration.retries }
    attribute :job_id, Types::Strict::String.meta(omittable: true)
    attribute :queue, Types::Strict::String.default { SidekiqFlow.configuration.queue }
    attribute :children, Types::Strict::Array.of(Types::Strict::String).default([])
    attribute :params, Types::Strict::Hash.default({})
    attribute :status, Statuses

    def self.build(attrs={})
      attrs[:start_date] = Time.now.to_i unless attrs.has_key?(:start_date)
      super
    end

    def self.read_only_attrs
      [:execution_time, :job_id, :status]
    end

    def self.permanent_attrs
      [:start_date, :end_date, :loop_interval, :retries, :job_id, :queue, :children, :params, :status]
    end

    def perform
      raise NotImplementedError
    end

    def enqueue
      new(status: Statuses['enqueued'])
    end

    def run
      new(status: Statuses['running'])
    end

    def succeed
      new(status: Statuses['succeeded'])
    end

    def fail
      new(status: Statuses['failed'])
    end

    def skip
      new(status: Statuses['skip'])
    end

    def clear
      new(status: Statuses['pending'])
    end

    def set_job(job_id)
      new(job_id: job_id)
    end

    def clear_job
      new(job_id: nil)
    end

    def no_retries?
      retries == 0
    end

    def expired?
      end_date.present? && Time.now > end_date
    end
  end
end
