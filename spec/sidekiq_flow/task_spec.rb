RSpec.describe SidekiqFlow::Task do
  describe '.sidekiq_options' do
    let(:task_with_options) do
      Class.new(described_class) do
        sidekiq_options queue: 'critical', retry: 5
      end
    end

    let(:task_without_options) do
      Class.new(described_class)
    end

    it 'defaults queue and retries from sidekiq_options' do
      task = task_with_options.new

      expect(task.queue).to eq('critical')
      expect(task.retries).to eq(5)
    end

    it 'falls back to configuration when sidekiq_options are not set' do
      task = task_without_options.new

      expect(task.queue).to eq(SidekiqFlow.configuration.queue)
      expect(task.retries).to eq(SidekiqFlow.configuration.retries)
    end

    it 'allows instance attributes to override sidekiq_options' do
      task = task_with_options.new(queue: 'low', retries: 1)

      expect(task.queue).to eq('low')
      expect(task.retries).to eq(1)
    end

    it 'inherits sidekiq_options from the parent class' do
      child = Class.new(task_with_options)
      task = child.new

      expect(task.queue).to eq('critical')
      expect(task.retries).to eq(5)
    end

    it 'allows a subclass to override inherited sidekiq_options' do
      child = Class.new(task_with_options) do
        sidekiq_options queue: 'low', retry: 2
      end
      task = child.new

      expect(task.queue).to eq('low')
      expect(task.retries).to eq(2)
    end

    it 'uses sidekiq_options when enqueueing to Sidekiq' do
      workflow = TestWorkflow.new(
        id: 1,
        tasks: [
          TestTaskWithSidekiqOptions.new(children: ['TestTask4']),
          TestTask4.new
        ]
      )
      SidekiqFlow::Client.start_workflow(workflow)

      expect(Sidekiq::Worker.jobs.count).to eq(1)
      expect(Sidekiq::Worker.jobs.first['args'][1]).to eq('TestTaskWithSidekiqOptions')
      expect(Sidekiq::Worker.jobs.first['queue']).to eq('critical')
      expect(Sidekiq::Worker.jobs.first['retry']).to eq(5)
    end
  end
end
