module SidekiqFlow
  class Task < Model
    attribute :start_time, Types::Strict::Integer.meta(omittable: true)
    attribute :end_time, Types::Strict::Integer.meta(omittable: true)
    attribute :execution_time, Types::Strict::Integer.meta(omittable: true)
    attribute :failed, Types::Strict::Bool.default(false)
    attribute :skipped, Types::Strict::Bool.default(false)
    attribute :loop_interval, Types::Strict::Integer.meta(omittable: true)
    attribute :retries, Types::Strict::Integer.default(0)
    attribute :job_id, Types::Strict::String.meta(omittable: true)
    attribute :queue, Types::Strict::String.default('default')
    attribute :children, Types::Strict::Array.of(Types::Class).default([])

    def self.build(attrs)
      attrs[:start_time] = Time.now.to_i unless attrs.has_key?(:start_time)
      super
    end

    def self.read_only_attrs
      [:execution_time, :job_id, :failed, :skipped]
    end
  end
end
