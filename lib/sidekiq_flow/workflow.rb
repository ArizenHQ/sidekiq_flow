module SidekiqFlow
  class Workflow < Model
    attribute :id, Types::Strict::Integer
    attribute :tasks, Types::Strict::Array.of(Task)
    attribute :params, Types::Strict::Hash.default({})

    def self.run!(id, params={})
      workflow = new(id: id, tasks: task_list, params: params)
      Client.store_workflow(workflow)
    end

    def self.permanent_attrs
      [:id, :params]
    end

    def self.task_list
      raise NotImplementedError
    end

    def find_task_parents(task_class_name)
      tasks.select { |t| t.children.include?(task_class_name) }
    end

    def find_task_flat_children(task_class_name)
      find_task(task_class_name).children.map do |child_class_name|
        find_task_flat_children(child_class_name) << find_task(child_class_name)
      end.flatten.uniq
    end

    def find_task(task_class_name)
      tasks.detect { |t| t.class_name == task_class_name }
    end
  end
end
