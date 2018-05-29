module SidekiqFlow
  class Workflow < Model
    attribute :id, Types::Strict::Integer
    attribute :tasks, Types::Strict::Array.of(Task).default([])
  end
end
