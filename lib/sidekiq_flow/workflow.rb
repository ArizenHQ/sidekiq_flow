module SidekiqFlow
  class Workflow < Model
    attribute :id, Types::Strict::Integer
    attribute :tasks, Types::Strict::Array.of(Task).default([])

    def self.read_only_attrs
      [:tasks]
    end

    def self.permanent_attrs
      [:id]
    end

    def find_task_parents(task_class)
      tasks.select { |t| t.children.include?(task_class) }
    end

    def find_task_flat_children(task_class)
      find_task(task_class).children.map do |child_class|
        find_task_flat_children(child_class) << find_task(child_class)
      end.flatten.uniq
    end

    def find_task(task_class)
      tasks.detect { |t| t.klass == task_class }
    end
  end
end
