module SidekiqFlow
  class Workflow < Model
    def self.attribute_names
      [:id, :tasks, :params]
    end

    def self.task_list
      raise NotImplementedError
    end

    def self.from_hash(attrs={})
      attrs[:tasks].map! { |task_attrs| Task.from_hash(task_attrs) }
      super
    end

    def initialize(attrs={})
      super
      @id = attrs.fetch(:id)
      @tasks = attrs[:tasks] || self.class.task_list
      @tasks_per_class = @tasks.map { |t| [t.klass, t] }.to_h
      @params = attrs[:params] || {}
    end

    def run!(externally_triggered_tasks)
      find_pending_tasks.each do |task|
        if task.external_trigger?
          task.enqueue!(Time.now.to_i) if externally_triggered_tasks.include?(task.klass)
          next
        end
        task.enqueue! if TaskTriggerRules::Base.build(task.trigger_rule, find_task_parents(task)).met?
      end
    end

    def find_task(task_class)
      @tasks_per_class[task_class]
    end

    def find_pending_tasks
      tasks.select(&:pending?)
    end

    def find_ready_to_start_tasks
      tasks.select(&:ready_to_start?)
    end

    def clear_branch!(parent_task_class)
      parent_task = find_task(parent_task_class)
      (find_task_flat_children(parent_task) << parent_task).each(&:clear!)
    end

    def to_h
      super.merge(tasks: tasks.map { |task| task.to_h })
    end

    private

    def find_task_parents(task)
      tasks.select { |t| t.children.include?(task.klass) }
    end

    def find_task_flat_children(task)
      children_tasks = task.children.map { |child_class| find_task(child_class) }
      children_tasks + children_tasks.flat_map { |child_task| find_task_flat_children(child_task) }.uniq
    end
  end
end
