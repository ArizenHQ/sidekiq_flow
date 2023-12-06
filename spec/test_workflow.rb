class TestTask1 < SidekiqFlow::Task
  def perform; end
end

class TestTask2 < SidekiqFlow::Task
  def perform; end
end

class TestTask3 < SidekiqFlow::Task
  def perform; end
end

class TestTask4 < SidekiqFlow::Task
  def perform; end
end

class TestTaskStartDateOverloaded < SidekiqFlow::Task
  def perform; end

  def start_date
    1.hour.from_now.to_i
  end
end

class TestWorkflow < SidekiqFlow::Workflow
  def succeeded?
    find_task(TestTask4.to_s).succeeded?
  end
end
