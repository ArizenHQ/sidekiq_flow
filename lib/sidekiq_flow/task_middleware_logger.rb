module SidekiqFlow
  class TaskMiddlewareLogger
    def call(worker, job, queue)
      yield
    end
  end
end
