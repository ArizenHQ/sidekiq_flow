require 'spec_helper'

RSpec.describe 'workflow' do
  describe 'happy path' do
    before do
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
      SidekiqFlow::Worker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.all?(&:succeeded?)).to be(true)
    end
  end

  describe 'failing task (no retries)' do
    before do
      allow_any_instance_of(TestTask3).to receive(:perform) { raise 'Some error' }
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
      expect do
        SidekiqFlow::Worker.drain
      end.to raise_error(RuntimeError)
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'failed', 'pending'])
    end
  end

  describe 'failing task (retries present)' do
    before do
      allow_any_instance_of(TestTask3).to receive(:perform) { raise 'Some error' }
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
      expect do
        SidekiqFlow::Worker.drain
      end.to raise_error(RuntimeError)
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'awaiting_retry', 'pending'])
    end
  end

  describe 'task externally triggered' do
    before do
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'pending', 'pending'])

      SidekiqFlow::Client.run_workflow(workflow, ['TestTask2'])
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'pending', 'pending'])

      SidekiqFlow::Client.run_workflow(workflow, ['TestTask3'])
      SidekiqFlow::Worker.drain
      workflow = SidekiqFlow::Client.find_workflow(workflow.id)
      expect(workflow.tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
    end
  end

  describe 'task repetition' do
    before do
      allow_any_instance_of(TestTask1).to receive(:perform) { raise SidekiqFlow::RepeatTask }
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
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
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
      SidekiqFlow::Worker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['failed', 'pending', 'pending', 'pending'])
    end
  end

  describe 'task trigger rules' do
    context 'all_succeeded' do
      before do
        allow(TestWorkflow).to receive(:task_list) {
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
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'skipped', 'pending'])

        allow_any_instance_of(TestTask3).to receive(:perform)
        workflow = TestWorkflow.new(id: 2)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'succeeded', 'pending'])

        allow_any_instance_of(TestTask2).to receive(:perform)
        workflow = TestWorkflow.new(id: 3)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
      end
    end

    context 'one_succeeded' do
      before do
        allow(TestWorkflow).to receive(:task_list) {
          [
            TestTask1.new(children: ['TestTask2', 'TestTask3']),
            TestTask2.new(children: ['TestTask4']),
            TestTask3.new(children: ['TestTask4']),
            TestTask4.new(trigger_rule: 'one_succeeded')
          ]
        }
      end

      it 'behaves properly' do
        allow_any_instance_of(TestTask2).to receive(:perform) { raise SidekiqFlow::SkipTask }
        allow_any_instance_of(TestTask3).to receive(:perform) { raise SidekiqFlow::SkipTask }
        workflow = TestWorkflow.new(id: 1)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'skipped', 'pending'])

        allow_any_instance_of(TestTask3).to receive(:perform)
        workflow = TestWorkflow.new(id: 2)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'succeeded', 'succeeded'])

        allow_any_instance_of(TestTask2).to receive(:perform)
        workflow = TestWorkflow.new(id: 3)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
      end
    end

    context 'all_done' do
      before do
        allow(TestWorkflow).to receive(:task_list) {
          [
            TestTask1.new(children: ['TestTask2', 'TestTask3']),
            TestTask2.new(children: ['TestTask4']),
            TestTask3.new(children: ['TestTask4']),
            TestTask4.new(trigger_rule: 'all_done')
          ]
        }
      end

      it 'behaves properly' do
        allow_any_instance_of(TestTask2).to receive(:perform) { raise SidekiqFlow::SkipTask }
        allow_any_instance_of(TestTask3).to receive(:perform) { raise SidekiqFlow::SkipTask }
        workflow = TestWorkflow.new(id: 1)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'skipped', 'succeeded'])

        allow_any_instance_of(TestTask3).to receive(:perform)
        workflow = TestWorkflow.new(id: 2)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'skipped', 'succeeded', 'succeeded'])

        allow_any_instance_of(TestTask2).to receive(:perform)
        workflow = TestWorkflow.new(id: 3)
        SidekiqFlow::Client.run_workflow(workflow)
        SidekiqFlow::Worker.drain
        expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])
      end
    end
  end

  describe 'task clearing' do
    before do
      allow(TestWorkflow).to receive(:task_list) {
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
      SidekiqFlow::Client.run_workflow(workflow)
      SidekiqFlow::Worker.drain
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['succeeded', 'succeeded', 'succeeded', 'succeeded'])

      SidekiqFlow::Client.clear_workflow_branch(workflow.id, 'TestTask1')
      expect(SidekiqFlow::Client.find_workflow(workflow.id).tasks.map(&:status)).to eq(['pending', 'pending', 'pending', 'pending'])
    end
  end
end
