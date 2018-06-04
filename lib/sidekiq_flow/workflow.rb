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
      @params = attrs[:params] || {}
    end

    def run!(externally_triggered_tasks)
      find_pending_tasks.each do |task|
        task.enqueue!(Time.now.to_i) and next if task.external_trigger? && externally_triggered_tasks.include?(task.klass)
        task.enqueue! if TaskTriggerRules::Base.build(task.trigger_rule, find_task_parents(task)).met?
      end
    end

    def find_task(task_class)
      tasks.detect { |t| t.klass == task_class }
    end

    def find_pending_tasks
      tasks.select(&:pending?)
    end

    def find_enqueued_tasks
      tasks.select(&:enqueued?)
    end

    def to_h
      super.merge(tasks: tasks.map { |task| task.to_h })
    end

    private

    def find_task_parents(task)
      tasks.select { |t| t.children.include?(task.klass) }
    end
  end
end
