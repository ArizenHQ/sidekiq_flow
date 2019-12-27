module SidekiqFlow
  class TaskMiddlewareLogger

    def call(worker, job, queue)
      byebug
      yield
    end

  end
end
