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

class TestWorkflow < SidekiqFlow::Workflow
  def succeeded?
    find_task(TestTask4.to_s).succeeded?
  end
end
