module SidekiqFlow
  class Task < Model
    Statuses = Types::Strict::String.default('pending').enum('pending', 'enqueued', 'running', 'succeeded', 'failed', 'skipped')

    attribute :start_date, (Types::Strict::Nil | Types::Strict::Integer).meta(omittable: true)
    attribute :end_date, Types::Strict::Integer.meta(omittable: true)
    attribute :loop_interval, Types::Strict::Integer.meta(omittable: true)
    attribute :retries, Types::Strict::Integer.default { SidekiqFlow.configuration.retries }
    attribute :job_id, Types::Strict::String.meta(omittable: true)
    attribute :queue, Types::Strict::String.default { SidekiqFlow.configuration.queue }
    attribute :children, Types::Strict::Array.of(Types::Strict::String).default([])
    attribute :params, Types::Strict::Hash.default({})
    attribute :status, Statuses

    def self.build(attrs={})
      attrs[:start_date] = Time.now.to_i unless attrs.has_key?(:start_date)
      new(attrs.reject { |k, v| read_only_attrs.include?(k) })
    end

    def self.read_only_attrs
      [:execution_time, :job_id, :status]
    end

    def self.permanent_attrs
      [:start_date, :end_date, :loop_interval, :retries, :job_id, :queue, :children, :params, :status]
    end
  end
end
