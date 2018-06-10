class WorkflowSerializer < SimpleDelegator
  def to_h
    __getobj__.to_h.merge(klass: klass, tasks: tasks.map { |t| t.to_h.merge(klass: t.klass) })
  end

  def to_json
    to_h.to_json
  end
end
