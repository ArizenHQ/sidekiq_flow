require 'spec_helper'

def redis_key_count
  $redis.keys("workflows.*").count
end

RSpec.shared_examples '.start_workflow common' do
  it 'should store the workflow in redis' do
    expect {
      subject
    }.to change { redis_key_count }.from(0).to(1)
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

        it 'should have 1 job in sidekiq' do
          subject
          expect(Sidekiq::Worker.jobs.count).to eq(1)
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

    let(:start_date) { Time.now.to_i + 60 }
    let(:end_date) { Time.now.to_i + 120 }

    before do
      allow(TestWorkflow).to receive(:initial_tasks) {
        [
          TestTask1.new(children: ['TestTask2', 'TestTask3'], start_date: start_date, end_date: end_date),
          TestTask2.new(children: ['TestTask4']),
          TestTask3.new(children: ['TestTask4']),
          TestTask4.new
        ]
      }

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

      context 'task end_date is set' do
        it 'should make task status be pending' do
          expect {
            subject
          }.to change {
            SidekiqFlow::Client.find_task(workflow.id, task_klass).status
          }.from('enqueued').to('pending')
        end

        it 'should set start_date to nil' do
          expect {
            subject
          }.to change {
            SidekiqFlow::Client.find_task(workflow.id, task_klass).start_date.nil?
          }.from(false).to(true)
        end

        it 'should set end_date to nil' do
          expect {
            subject
          }.to change {
            SidekiqFlow::Client.find_task(workflow.id, task_klass).end_date.nil?
          }.from(false).to(true)
        end
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
        }.to change { redis_key_count }.from(0).to(1)
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
        }.not_to change { redis_key_count }
      end

      it 'should ONLY have 1 redis key' do
        subject
        expect(redis_key_count).to eq(1)
      end

      it 'should override the existing stored workflow' do
        key = redis.keys.detect { |element| element.include?('_0') }

        hash1 = redis.hgetall(key)
        workflow.clear_branch!('TestTask1')
        subject
        hash2 = redis.hgetall(key)

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

      context 'NOT yet succeeded workflow' do
        it 'should rename workflow key to succeed pattern' do
          SidekiqFlow::Client.find_workflow_key(workflow.id) =~ /#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d{10}_0/
          subject
          SidekiqFlow::Client.find_workflow_key(workflow.id) =~ /#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d{10}_\d{10}/
        end
      end

      context 'already succeeded workflow' do
        it 'should NOT change the workflow key' do
          subject
          key = SidekiqFlow::Client.find_workflow_key(workflow.id)

          # call subject to trigger succeed call again, should not change key
          subject
          expect(SidekiqFlow::Client.find_workflow_key(workflow.id)).to eq key
        end
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
      it 'should raise WorkflowNotFound when workflow_key not found' do
        expect {
          subject
        }.to raise_exception(SidekiqFlow::WorkflowNotFound)
      end

      it 'should log error when workflow_key not found' do
        expect(described_class.send(:logger)).to receive(:error).with(/Cannot find workflow: workflow_key not found/)
        expect { subject }.to raise_exception(SidekiqFlow::WorkflowNotFound)
      end
    end

    context 'workflow data empty' do
      let(:empty_key) { "#{SidekiqFlow.configuration.namespace}.#{workflow.id}_1234567890_0" }

      before do
        redis.hset('workflow-keys', workflow.id, empty_key)
        # Key exists in lookup hash but no workflow data
      end

      it 'should raise WorkflowNotFound' do
        expect {
          subject
        }.to raise_exception(SidekiqFlow::WorkflowNotFound)
      end

      it 'should log error before raising' do
        expect(described_class.send(:logger)).to receive(:error).with(/Cannot find workflow: workflow data is empty/)
        expect { subject }.to raise_exception(SidekiqFlow::WorkflowNotFound)
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
        }.to change { redis_key_count }.from(1).to(0)
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

        expect(redis_key_count).to eq(2)

        subject

        expect(redis_key_count).to eq(1)

        # Succeeded workflow should be deleted
        expect {
          SidekiqFlow::Client.find_workflow(workflow.id)
        }.to raise_exception(SidekiqFlow::WorkflowNotFound)

        # In-progress workflow should still exist
        expect {
          SidekiqFlow::Client.find_workflow(workflow2.id)
        }.not_to raise_error
      end

      it 'should remove workflow from lookup hash' do
        subject

        expect(redis.hget('workflow-keys', workflow.id)).to be_nil
      end

      it 'should delete timestamp keys' do
        subject

        expect(redis.get("workflow-timestamps.#{workflow.id}.start")).to be_nil
        expect(redis.get("workflow-timestamps.#{workflow.id}.end")).to be_nil
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

    context 'failure' do
      let(:task_klass) { 'UnknownTask' }

      it 'should return raise error' do
        task = subject
        expect { task.status }.to raise_error NoMethodError
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

    context 'happy path' do
      before do
        described_class.start_workflow(workflow)
      end

      context 'in-progress workflow' do
        it 'should return the correct key' do
          result = subject
          expect(result).to match(/#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d+_0/)
        end

        it 'should lookup from workflow-keys hash' do
          expect(redis.hget('workflow-keys', workflow.id)).to be_present
        end
      end

      context 'completed workflow' do
        before do
          described_class.send(:succeed_workflow, workflow.id)
        end

        it 'should return the correct key' do
          result = subject
          expect(result).to match(/#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d{10}_\d{10}/)
        end

        it 'should update workflow-keys hash with new key' do
          expect(redis.hget('workflow-keys', workflow.id)).to match(/_\d{10}_\d{10}$/)
        end
      end
    end

    context 'edge cases' do
      context 'workflow not found' do
        it 'should return nil' do
          expect(subject).to be_nil
        end

        it 'should not have entry in workflow-keys hash' do
          expect(redis.hget('workflow-keys', workflow.id)).to be_nil
        end
      end

      context 'legacy workflow (no lookup hash entry, only timestamps)' do
        let(:legacy_key) { "#{SidekiqFlow.configuration.namespace}.#{workflow.id}_1234567890_0" }

        before do
          # Simulate old workflow: create workflow hash and timestamps but NO lookup hash entry
          redis.hset(legacy_key, 'klass', 'TestWorkflow')
          redis.set("workflow-timestamps.#{workflow.id}.start", '1234567890')
        end

        it 'should find key via timestamp fallback' do
          expect(subject).to eq(legacy_key)
        end

        it 'should auto-migrate to lookup hash' do
          subject
          expect(redis.hget('workflow-keys', workflow.id)).to eq(legacy_key)
        end
      end

      context 'corrupted state: timestamps exist but workflow data missing' do
        before do
          redis.set("workflow-timestamps.#{workflow.id}.start", '1234567890')
          # No workflow hash created
        end

        it 'should return nil' do
          expect(subject).to be_nil
        end

        it 'should log warning' do
          expect(described_class.send(:logger)).to receive(:warn).with(/Timestamps exist but workflow data missing/)
          subject
        end
      end

      context 'workflow-keys hash entry exists but points to deleted workflow' do
        let(:stale_key) { "#{SidekiqFlow.configuration.namespace}.#{workflow.id}_1234567890_0" }

        before do
          redis.hset('workflow-keys', workflow.id, stale_key)
          # Workflow hash at stale_key doesn't exist
        end

        it 'should return the stale key (caller will handle missing data)' do
          expect(subject).to eq(stale_key)
        end
      end
    end

    context 'race conditions' do
      context 'workflow deleted between lookup and use' do
        before do
          described_class.start_workflow(workflow)
        end

        it 'should return key even if workflow gets deleted after lookup' do
          key = subject
          described_class.destroy_workflow(workflow.id)

          # Key should still be returned from cache
          expect(key).to match(/#{SidekiqFlow.configuration.namespace}\.#{workflow.id}_\d+_0/)

          # But next lookup should return nil
          expect(described_class.find_workflow_key(workflow.id)).to be_nil
        end
      end

      context 'workflow succeeds during multiple lookups' do
        before do
          described_class.start_workflow(workflow)
        end

        it 'should return consistent keys' do
          key1 = subject
          described_class.send(:succeed_workflow, workflow.id)
          key2 = described_class.find_workflow_key(workflow.id)

          expect(key1).to match(/_0$/)
          expect(key2).to match(/_\d{10}$/)
          expect(key1).not_to eq(key2)
        end
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
