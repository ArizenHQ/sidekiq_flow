require 'spec_helper'

RSpec.shared_examples '.start_workflow common' do
  it 'should store the workflow in redis' do
    expect {
      subject
    }.to change { $redis.keys.count }.from(0).to(1)
  end

  it 'should enqueue a job to Sidekiq' do
    expect {
      subject
    }.to change { Sidekiq::Worker.jobs.count }.from(0).to(1)
  end

  it 'should enqueue TestTask1 job to Sidekiq' do
    subject
    expect(Sidekiq::Worker.jobs.first['args'][1]).to eq('TestTask1')
  end
end

RSpec.describe SidekiqFlow::Client do
  let(:redis) { $redis }
  let(:id) { '123' }
  let(:workflow) { TestWorkflow.new(id: id) }

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

  describe '.start_workflow' do
    subject { described_class.start_workflow(workflow) }

    context 'alphanumeric id' do
      let(:id) { 'cs-123' }

      include_examples '.start_workflow common'
    end

    context 'numeric string id' do
      include_examples '.start_workflow common'
    end

    context 'numeric id' do
      let(:id) { 123 }
      include_examples '.start_workflow common'
    end

    context 'workflow with same key started in succession' do
      context 'different instances created' do
        subject {
          described_class.start_workflow(TestWorkflow.new(id: id))
          described_class.start_workflow(TestWorkflow.new(id: id))
          described_class.start_workflow(TestWorkflow.new(id: id))
        }

        it 'should have 3 jobs in sidekiq' do
          subject
          expect(Sidekiq::Worker.jobs.count).to eq(3)
        end
      end

      context 'same instance used' do
        subject {
          described_class.start_workflow(workflow)
          described_class.start_workflow(workflow)
          described_class.start_workflow(workflow)
        }

        it 'should have 1 job in sidekiq' do
          subject
          expect(Sidekiq::Worker.jobs.count).to eq(1)
        end
      end
    end
  end

  describe '.start_task' do
    subject { described_class.start_task(workflow.id, task_klass) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      let(:task_klass) { 'TestTask2' }

      it 'should enqueue a job to Sidekiq' do
        expect {
          subject
        }.to change { Sidekiq::Worker.jobs.count }.from(1).to(2)
      end

      it 'should enqueue TestTask2 job to Sidekiq' do
        subject
        expect(Sidekiq::Worker.jobs.last['args'][1]).to eq(task_klass)
      end
    end

    context 'unstartable' do
      let(:task_klass) { 'TestTask1' }

      it 'should raise TaskUnstartable for TestTask1' do
        expect {
          subject
        }.to raise_exception(SidekiqFlow::TaskUnstartable)
      end
    end
  end

  describe '.restart_task' do
    subject { described_class.restart_task(workflow.id, task_klass) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      let(:task_klass) { 'TestTask2' }

      it 'should enqueue a job to Sidekiq' do
        expect {
          subject
        }.to change { Sidekiq::Worker.jobs.count }.from(1).to(2)
      end

      it 'should enqueue TestTask2 job to Sidekiq' do
        subject
        expect(Sidekiq::Worker.jobs.last['args'][1]).to eq(task_klass)
      end
    end


    context 'failure' do
      let(:task_klass) { 'TestTask1' }

      it 'should NOT enqueue a new job to Sidekiq' do
        expect {
          subject
        }.not_to change { Sidekiq::Worker.jobs.count }
      end

      it 'should only have 1 job' do
        subject
        expect(Sidekiq::Worker.jobs.count).to eq(1)
      end

      it 'should only have 1 TestTask1 job' do
        expect(Sidekiq::Worker.jobs.first['args'][1]).to eq(task_klass)
      end
    end
  end

  describe '.clear_task' do
    subject { described_class.clear_task(workflow.id, task_klass) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      let(:task_klass) { 'TestTask1' }

      it 'should make task status be pending' do
        expect {
          subject
        }.to change {
          SidekiqFlow::Client.find_task(workflow.id, task_klass).status
        }.from('enqueued').to('pending')
      end
    end
  end

  describe '.store_workflow' do
    subject { described_class.store_workflow(workflow, initial) }

    context 'initial' do
      let(:initial) { true }

      it 'should store the workflow' do
        expect {
          subject
        }.to change { redis.keys.count }.from(0).to(1)
      end
    end

    context 'subsequent' do
      let(:initial) { false }

      before do
        described_class.start_workflow(workflow)
      end

      it 'should NOT create a new redis key' do
        expect {
          subject
        }.not_to change { redis.keys.count }
      end

      it 'should ONLY have 1 redis key' do
        subject
        expect(redis.keys.count).to eq(1)
      end

      it 'should override the existing stored workflow' do
        hash1 = redis.hgetall(redis.keys.first)
        workflow.clear_branch!('TestTask1')
        subject
        hash2 = redis.hgetall(redis.keys.first)

        expect(hash1).not_to eq(hash2)
      end
    end
  end

  describe '.store_task' do
    context 'success' do
      subject { described_class.store_task(task) }
      let(:task) { workflow.tasks.first }

      before do
        described_class.start_workflow(workflow)
      end

      it 'should store task info in redis' do
        expect {
          task.fail!
          subject
        }.to change {
          SidekiqFlow::Client.find_task(workflow.id, task.class.name).status
        }.from('enqueued').to('failed')
      end
    end
  end

  describe '.find_workflow' do
    subject { described_class.find_workflow(workflow.id) }

    context 'success' do
      before do
        described_class.start_workflow(workflow)
      end

      it 'should return a Workflow instance' do
        result = subject
        expect(result).to be_a_kind_of(TestWorkflow)
      end

      it 'should return a the correct Workflow instance' do
        result = subject
        expect(result.id).to eq(workflow.id)
      end
    end

    context 'exception' do
      it 'should raise WorkflowNotFound' do
        expect {
          subject
        }.to raise_exception(SidekiqFlow::WorkflowNotFound)
      end
    end
  end

  describe '.destroy_workflow' do
    subject { described_class.destroy_workflow(workflow.id) }

    context 'success' do
      before do
        described_class.start_workflow(workflow)
      end

      it 'should delete the workflow' do
        expect {
          subject
        }.to change { redis.keys.count }.from(1).to(0)
      end
    end
  end

  describe '.destroy_succeeded_workflows' do
    let(:workflow2) { TestWorkflow.new(id: 345) }

    subject { described_class.destroy_succeeded_workflows }

    context 'success' do
      before do
        described_class.start_workflow(workflow)
        SidekiqFlow::Worker.drain
      end

      it 'should ONLY delete succeeded workflows' do
        described_class.start_workflow(workflow2)

        expect(redis.keys.count).to eq(2)

        subject

        expect(redis.keys.count).to eq(1)

        expect {
          SidekiqFlow::Client.find_workflow(workflow.id)
        }.to raise_exception(SidekiqFlow::WorkflowNotFound)

        expect {
          SidekiqFlow::Client.find_workflow(workflow2.id)
        }.not_to raise_error
      end
    end
  end

  describe '.find_task' do
    subject { described_class.find_task(workflow.id, task_klass) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      let(:task_klass) { 'TestTask1' }

      it 'should return TestTask1 instance' do
        result = subject
        expect(result).to be_a_kind_of(TestTask1)
      end

      it 'should return the correct TestTask1 instance' do
        result = subject
        expect(result.workflow_id).to eq(workflow.id)
      end
    end
  end

  describe '.enqueue_task' do
    let(:task) { workflow.tasks.second }
    subject { described_class.enqueue_task(task) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      it 'should enqueue a job to Sidekiq' do
        expect {
          subject
        }.to change { Sidekiq::Worker.jobs.count }.from(1).to(2)
      end

      it 'should enqueue TestTask2 job to Sidekiq' do
        subject
        expect(Sidekiq::Worker.jobs.last['args'][1]).to eq('TestTask2')
      end
    end
  end


  describe '.find_workflow_key' do
    subject { described_class.find_workflow_key(workflow.id) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      it 'should return the correct key' do
        result = subject
        expect(result).to match(/#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d+_0/)
      end
    end

    # NOTE: existing behavior can return already succeeded workflows
    context 'failure scenario' do
      it 'returns the wrong key' do
        SidekiqFlow::Worker.drain

        described_class.start_workflow(workflow)

        result = subject
        expect(result).to match(/#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d+_\d{2,}/)
      end
    end
  end

  describe '.set_task_queue' do
    let(:queue) { 'other_queue' }
    subject { described_class.set_task_queue(workflow.id, task_klass, queue) }

    before do
      described_class.start_workflow(workflow)
    end

    context 'success' do
      let(:task_klass) { 'TestTask1' }

      it 'should make task status be pending' do
        expect {
          subject
        }.to change {
          SidekiqFlow::Client.find_task(workflow.id, task_klass).queue
        }.from('default').to(queue)
      end
    end
  end
end
