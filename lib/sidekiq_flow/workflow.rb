module SidekiqFlow
  class Workflow < Model

    def self.attribute_names
      [:id, :params]
    end

    def self.from_redis_hash(redis_hash)
      workflow_class, workflow_attrs = redis_hash.delete('klass'), JSON.parse(redis_hash.delete('attrs'))
      tasks = redis_hash.map { |task_class, task_json| Task.build(task_class, JSON.parse(task_json)) }
      build(workflow_class, workflow_attrs.merge(tasks: tasks))
    end

    def self.initial_tasks
      raise NotImplementedError
    end

    attr_reader :tasks

    def initialize(attrs={})
      super
      @id = attrs.fetch(:id)
      @params = attrs[:params] || {}
      @tasks = attrs[:tasks] || self.class.initial_tasks
      @tasks_per_class = @tasks.map { |t| [t.klass, t] }.to_h
      update_tasks!
    end

    def find_task(task_class)
      tasks_per_class[task_class]
    end

    def find_ready_to_start_tasks
      tasks.select(&:ready_to_start?)
    end

    def clear_branch!(parent_task_class)
      parent_task = find_task(parent_task_class)
      (find_task_flat_children(parent_task) << parent_task).each(&:clear!)
    end

    def update_tasks!
      tasks.each do |task|
        task.children.each { |child_class| find_task(child_class).parents << task.klass }
        task.set_workflow_data!(id, params)
      end
    end

    def succeeded?
      false
    end

    private

    attr_reader :tasks_per_class

    def find_task_flat_children(task)
      children_tasks = task.children.map { |child_class| find_task(child_class) }
      children_tasks + children_tasks.flat_map { |child_task| find_task_flat_children(child_task) }.uniq
    end
  end
end
