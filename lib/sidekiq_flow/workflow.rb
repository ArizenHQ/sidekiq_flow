module SidekiqFlow
  class Workflow < Model
    attribute :id, Types::Strict::Integer
    attribute :tasks, Types::Strict::Array.of(Task)
    attribute :params, Types::Strict::Hash.default({})

    def self.run!(id, params={})
      workflow = new(id: id, tasks: task_list, params: params)
      Client.new.store_workflow(workflow)
    end

    def self.permanent_attrs
      [:id, :params]
    end

    def self.task_list
      raise NotImplementedError
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
