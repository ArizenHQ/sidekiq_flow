require 'spec_helper'

RSpec.describe 'workflow' do
  describe 'happy path' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      expect(SidekiqFlow::Client.find_workflow_key(workflow.id)).to match(/^.+\.123_\d+_0$/)

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'enqueued', 'enqueued', 'pending'])
      expect(SidekiqFlow::Client.find_workflow_key(workflow.id)).to match(/^.+\.123_\d+_0$/)

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'enqueued', 'pending'])
      expect(SidekiqFlow::Client.find_workflow_key(workflow.id)).to match(/^.+\.123_\d+_0$/)

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'enqueued'])
      expect(SidekiqFlow::Client.find_workflow_key(workflow.id)).to match(/^.+\.123_\d+_0$/)

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
      expect(SidekiqFlow::Client.find_workflow_key(workflow.id)).to match(/^.+\.123_\d+_\d{2,}$/)

      expect(SidekiqFlow::Worker.jobs).to be_empty
    end
  end

  describe 'failing task (no retries)' do
    before do
      allow_any_instance_of(TestTask3).to receive(:perform) { raise 'Some error' }
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      expect do
        SidekiqFlow::Worker.drain
      end.to raise_error(RuntimeError)
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'failed', 'pending'])
    end
  end

  describe 'failing task (retries present)' do
    before do
      allow_any_instance_of(TestTask3).to receive(:perform) { raise 'Some error' }
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4'], retries: 3),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      expect do
        SidekiqFlow::Worker.drain
      end.to raise_error(RuntimeError)
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'awaiting_retry', 'pending'])
    end
  end

  describe 'task externally triggered' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4'], start_date: nil),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'pending', 'pending'])

      expect do
        SidekiqFlow::Client.start_task(workflow.id, 'TestTask2')
        SidekiqFlow::ClientWorker::TaskStarterWorker.drain
      end.to raise_error(SidekiqFlow::TaskUnstartable)
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'pending', 'pending'])

      SidekiqFlow::Client.start_task(workflow.id, 'TestTask3')
      SidekiqFlow::ClientWorker::TaskStarterWorker.drain
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
    end
  end

  describe 'task reptition with delay' do
    let(:first_job_at) { Sidekiq::Worker.jobs.dig(0, 'at') }

    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3'], loop_interval: 5),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }

      Timecop.freeze
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain

      allow_any_instance_of(TestTask1).to receive(:perform) { raise SidekiqFlow::TryLater.new(delay_time: 15.minutes) }
      expect{SidekiqFlow::Worker.perform_one}.to change{Sidekiq::Worker.jobs.dig(0, 'at')}.to(first_job_at + 15.minutes.to_i)
    end
  end

  describe 'task repetition' do
    before do
      allow_any_instance_of(TestTask1).to receive(:perform) { raise SidekiqFlow::RepeatTask }
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3'], loop_interval: 5, end_date: (Time.now + 60).to_i),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['enqueued', 'pending', 'pending', 'pending'])

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['enqueued', 'pending', 'pending', 'pending'])

      allow_any_instance_of(TestTask1).to receive(:perform)
      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'enqueued', 'enqueued', 'pending'])

      SidekiqFlow::Worker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
    end
  end

  describe 'expired task' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3'], end_date: (Time.now - 60).to_i),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      SidekiqFlow::Worker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['failed', 'pending', 'pending', 'pending'])
      expect(SidekiqFlow::Client.find_task(workflow.id, 'TestTask1').error_msg).to eq('expired')
    end
  end

  describe 'task trigger rules' do
    context 'all_succeeded' do
      before do
        allow(TestWorkflow).to receive(:initial_tasks) {
          [
            TestTask1.new(children: ['TestTask2', 'TestTask3']),
            TestTask2.new(children: ['TestTask4']),
            TestTask3.new(children: ['TestTask4']),
            TestTask4.new
          ]
        }
      end

      it 'behaves properly' do
        allow_any_instance_of(TestTask2).to receive(:perform) { raise SidekiqFlow::SkipTask }
        allow_any_instance_of(TestTask3).to receive(:perform) { raise SidekiqFlow::SkipTask }
        workflow = TestWorkflow.new(id: 1)
        SidekiqFlow::Client.start_workflow(workflow)
        SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'skipped', 'pending'])

        allow_any_instance_of(TestTask3).to receive(:perform)
        workflow = TestWorkflow.new(id: 2)
        SidekiqFlow::Client.start_workflow(workflow)
        SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'succeeded', 'pending'])

        allow_any_instance_of(TestTask2).to receive(:perform)
        workflow = TestWorkflow.new(id: 3)
        SidekiqFlow::Client.start_workflow(workflow)
        SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
      end
    end

    context 'number_succeeded' do
      before do
        allow(TestWorkflow).to receive(:initial_tasks) {
          [
            TestTask1.new(children: ['TestTask2', 'TestTask3']),
            TestTask2.new(children: ['TestTask4']),
            TestTask3.new(children: ['TestTask4']),
            TestTask4.new(trigger_rule: ['number_succeeded', {number: 1}])
          ]
        }
      end

      it 'behaves properly' do
        allow_any_instance_of(TestTask2).to receive(:perform) { raise SidekiqFlow::SkipTask }
        allow_any_instance_of(TestTask3).to receive(:perform) { raise SidekiqFlow::SkipTask }
        workflow = TestWorkflow.new(id: 1)
        SidekiqFlow::Client.start_workflow(workflow)
        SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'skipped', 'pending'])

        allow_any_instance_of(TestTask3).to receive(:perform)
        workflow = TestWorkflow.new(id: 2)
        SidekiqFlow::Client.start_workflow(workflow)
        SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'succeeded', 'succeeded'])

        allow_any_instance_of(TestTask2).to receive(:perform)
        workflow = TestWorkflow.new(id: 3)
        SidekiqFlow::Client.start_workflow(workflow)
        SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
      end
    end
  end

  describe 'task restart' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])

      SidekiqFlow::Client.restart_task(workflow.id, 'TestTask1')
      SidekiqFlow::ClientWorker::TaskStarterWorker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['enqueued', 'pending', 'pending', 'pending'])
    end
  end

  describe 'destroying workflows' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 1))
      SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 2))
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      SidekiqFlow::Worker.drain
      SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 3))
      SidekiqFlow::Client.start_workflow(TestWorkflow.new(id: 4))
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain

      SidekiqFlow::Client.destroy_workflow(4)
      expect(SidekiqFlow::Client.find_workflow_keys.map { |k| k.split('.').last.split('_').first.to_i }).to match_array([1, 2, 3])

      SidekiqFlow::Client.destroy_succeeded_workflows
      expect(SidekiqFlow::Client.find_workflow_keys.map { |k| k.split('.').last.split('_').first.to_i }).to eq([3])
    end
  end

  describe 'auto_succeed?' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3'], end_date: (Time.now - 60).to_i),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
      class TestTask1
        def auto_succeed?
          true
        end
      end
    end

    after do
      class TestTask1
        def auto_succeed?
          false
        end
      end
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      SidekiqFlow::Worker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
    end
  end

  describe "setting task's queue" do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3']),
          TestTask2.new(children: ['TestTask4'], queue: 'initial_queue'),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }
      class TestTask1
        def perform
          SidekiqFlow::Client.set_task_queue(workflow_id, 'TestTask2', 'new_queue')
        end
      end
    end

    after do
      class TestTask1
        def perform; end
      end
    end

    it 'behaves properly' do
      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      expect(SidekiqFlow::Client.find_task(workflow.id, 'TestTask2').queue).to eq('initial_queue')

      SidekiqFlow::Worker.perform_one
      expect(SidekiqFlow::Client.find_task(workflow.id, 'TestTask2').queue).to eq('new_queue')
    end
  end

  describe 'task externally triggered raises TriggerTaskManually' do
    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2']),
          TestTask2.new(children: ['TestTask3', 'TestTask4'], start_date: nil),
          TestTask3.new,
          TestTask4.new
        ]
      }
    end

    it 'behaves properly' do
      # first run raises error
      allow_any_instance_of(TestTask2).to receive(:perform) { raise SidekiqFlow::TriggerTaskManually }

      workflow = TestWorkflow.new(id: 123)
      SidekiqFlow::Client.start_workflow(workflow)
      SidekiqFlow::ClientWorker::WorkflowStarterWorker.drain
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'pending', 'pending', 'pending'])

      # trigger the manual task
      SidekiqFlow::Client.start_task(workflow.id, 'TestTask2')
      SidekiqFlow::ClientWorker::TaskStarterWorker.drain
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'pending', 'pending', 'pending'])

      # second run is ok
      allow_any_instance_of(TestTask2).to receive(:perform).and_return(true)

      # trigger the manual task
      SidekiqFlow::Client.start_task(workflow.id, 'TestTask2')
      SidekiqFlow::ClientWorker::TaskStarterWorker.drain
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
    end
  end
end
