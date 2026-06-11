require 'spec_helper'

RSpec.describe SidekiqFlow::KeyManager do
  let(:connection_pool) { SidekiqFlow::Client.connection_pool }
  let(:configuration) { SidekiqFlow.configuration }
  let(:key_manager) { described_class.new(connection_pool, configuration) }
  let(:workflow_id) { 123 }
  let(:redis) { $redis }

  before do
    redis.flushdb
  end

  describe '#generate_initial_workflow_key' do
    let(:timestamp) { 1234567890 }

    context 'without redis connection parameter' do
      subject { key_manager.generate_initial_workflow_key(workflow_id, timestamp) }

      it 'should generate correct key format' do
        expect(subject).to eq("#{configuration.namespace}.#{workflow_id}_#{timestamp}_0")
      end

      it 'should store key in workflow-keys hash' do
        result = subject
        expect(redis.hget('workflow-keys', workflow_id)).to eq(result)
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.generate_initial_workflow_key(workflow_id, timestamp, redis) }

      it 'should generate correct key format' do
        expect(subject).to eq("#{configuration.namespace}.#{workflow_id}_#{timestamp}_0")
      end

      it 'should store key in workflow-keys hash' do
        result = subject
        expect(redis.hget('workflow-keys', workflow_id)).to eq(result)
      end

      it 'should not fetch from connection pool' do
        expect(connection_pool).not_to receive(:with)
        subject
      end
    end
  end

  describe '#find_workflow_key' do
    context 'without redis connection parameter' do
      subject { key_manager.find_workflow_key(workflow_id) }

      context 'when key exists in lookup hash' do
        let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

        before do
          redis.hset('workflow-keys', workflow_id, workflow_key)
        end

        it 'should return the workflow key' do
          expect(subject).to eq(workflow_key)
        end
      end

      context 'when key does not exist in lookup hash' do
        context 'but timestamps exist (legacy workflow)' do
          let(:start_timestamp) { '1234567890' }
          let(:expected_key) { "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_0" }

          before do
            redis.set("workflow-timestamps.#{workflow_id}.start", start_timestamp)
            redis.hset(expected_key, 'klass', 'TestWorkflow')
          end

          it 'should find key via timestamp fallback' do
            expect(subject).to eq(expected_key)
          end

          it 'should migrate key to lookup hash' do
            subject
            expect(redis.hget('workflow-keys', workflow_id)).to eq(expected_key)
          end
        end

        context 'and no timestamps exist' do
          it 'should return nil' do
            expect(subject).to be_nil
          end
        end

        context 'timestamps exist but workflow data missing' do
          before do
            redis.set("workflow-timestamps.#{workflow_id}.start", '1234567890')
          end

          it 'should return nil' do
            expect(subject).to be_nil
          end

          it 'should log warning' do
            expect(configuration.logger).to receive(:warn).with(/Timestamps exist but workflow data missing/)
            subject
          end
        end
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.find_workflow_key(workflow_id, redis) }

      context 'when key exists in lookup hash' do
        let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

        before do
          redis.hset('workflow-keys', workflow_id, workflow_key)
        end

        it 'should return the workflow key' do
          expect(subject).to eq(workflow_key)
        end

        it 'should not fetch from connection pool' do
          expect(connection_pool).not_to receive(:with)
          subject
        end
      end

      context 'when key does not exist but timestamps exist' do
        let(:start_timestamp) { '1234567890' }
        let(:expected_key) { "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_0" }

        before do
          redis.set("workflow-timestamps.#{workflow_id}.start", start_timestamp)
          redis.hset(expected_key, 'klass', 'TestWorkflow')
        end

        it 'should find key via timestamp fallback without using pool' do
          expect(connection_pool).not_to receive(:with)
          expect(subject).to eq(expected_key)
        end
      end
    end
  end

  describe '#lookup_workflow_key' do
    context 'without redis connection parameter' do
      subject { key_manager.lookup_workflow_key(workflow_id) }

      context 'when key exists in hash' do
        let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

        before do
          redis.hset('workflow-keys', workflow_id, workflow_key)
        end

        it 'should return the workflow key' do
          expect(subject).to eq(workflow_key)
        end
      end

      context 'when key does not exist' do
        it 'should return nil' do
          expect(subject).to be_nil
        end
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.lookup_workflow_key(workflow_id, redis) }

      context 'when key exists in hash' do
        let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

        before do
          redis.hset('workflow-keys', workflow_id, workflow_key)
        end

        it 'should return the workflow key' do
          expect(subject).to eq(workflow_key)
        end

        it 'should not fetch from connection pool' do
          expect(connection_pool).not_to receive(:with)
          subject
        end
      end
    end
  end

  describe '#store_workflow_key' do
    let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

    context 'without redis connection parameter' do
      subject { key_manager.store_workflow_key(workflow_id, workflow_key) }

      it 'should store key in workflow-keys hash' do
        subject
        expect(redis.hget('workflow-keys', workflow_id)).to eq(workflow_key)
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.store_workflow_key(workflow_id, workflow_key, redis) }

      it 'should store key in workflow-keys hash' do
        subject
        expect(redis.hget('workflow-keys', workflow_id)).to eq(workflow_key)
      end

      it 'should not fetch from connection pool' do
        expect(connection_pool).not_to receive(:with)
        subject
      end
    end
  end

  describe '#delete_workflow_key' do
    let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

    before do
      redis.hset('workflow-keys', workflow_id, workflow_key)
    end

    context 'without redis connection parameter' do
      subject { key_manager.delete_workflow_key(workflow_id) }

      it 'should remove key from workflow-keys hash' do
        subject
        expect(redis.hget('workflow-keys', workflow_id)).to be_nil
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.delete_workflow_key(workflow_id, redis) }

      it 'should remove key from workflow-keys hash' do
        subject
        expect(redis.hget('workflow-keys', workflow_id)).to be_nil
      end

      it 'should not fetch from connection pool' do
        expect(connection_pool).not_to receive(:with)
        subject
      end
    end
  end

  describe '#build_workflow_key_from_timestamps' do
    context 'without redis connection parameter' do
      subject { key_manager.build_workflow_key_from_timestamps(workflow_id) }

      context 'with start timestamp only (in-progress workflow)' do
        let(:start_timestamp) { '1234567890' }
        let(:expected_key) { "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_0" }

        before do
          redis.set("workflow-timestamps.#{workflow_id}.start", start_timestamp)
          redis.hset(expected_key, 'klass', 'TestWorkflow')
        end

        it 'should return correct key format' do
          expect(subject).to eq(expected_key)
        end
      end

      context 'with start and end timestamps (completed workflow)' do
        let(:start_timestamp) { '1234567890' }
        let(:end_timestamp) { '1234567900' }
        let(:expected_key) { "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_#{end_timestamp}" }

        before do
          redis.set("workflow-timestamps.#{workflow_id}.start", start_timestamp)
          redis.set("workflow-timestamps.#{workflow_id}.end", end_timestamp)
          redis.hset(expected_key, 'klass', 'TestWorkflow')
        end

        it 'should return correct key format' do
          expect(subject).to eq(expected_key)
        end
      end

      context 'with no timestamps' do
        it 'should return nil' do
          expect(subject).to be_nil
        end
      end

      context 'timestamps exist but workflow data missing' do
        before do
          redis.set("workflow-timestamps.#{workflow_id}.start", '1234567890')
        end

        it 'should return nil' do
          expect(subject).to be_nil
        end

        it 'should log warning' do
          expect(configuration.logger).to receive(:warn).with(/Timestamps exist but workflow data missing/)
          subject
        end
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.build_workflow_key_from_timestamps(workflow_id, redis) }

      context 'with start timestamp only' do
        let(:start_timestamp) { '1234567890' }
        let(:expected_key) { "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_0" }

        before do
          redis.set("workflow-timestamps.#{workflow_id}.start", start_timestamp)
          redis.hset(expected_key, 'klass', 'TestWorkflow')
        end

        it 'should return correct key format without using pool' do
          expect(connection_pool).not_to receive(:with)
          expect(subject).to eq(expected_key)
        end
      end
    end
  end

  describe '#workflow_key_exists?' do
    let(:workflow_key) { "#{configuration.namespace}.#{workflow_id}_1234567890_0" }

    context 'without redis connection parameter' do
      subject { key_manager.workflow_key_exists?(workflow_key) }

      context 'when key exists' do
        before do
          redis.hset(workflow_key, 'klass', 'TestWorkflow')
        end

        it 'should return true' do
          expect(subject).to be true
        end
      end

      context 'when key does not exist' do
        it 'should return false' do
          expect(subject).to be false
        end
      end
    end

    context 'with redis connection parameter (avoids nested pool)' do
      subject { key_manager.workflow_key_exists?(workflow_key, redis) }

      context 'when key exists' do
        before do
          redis.hset(workflow_key, 'klass', 'TestWorkflow')
        end

        it 'should return true' do
          expect(subject).to be true
        end

        it 'should not fetch from connection pool' do
          expect(connection_pool).not_to receive(:with)
          subject
        end
      end
    end
  end

  describe '#workflow_keys_namespace' do
    it 'should return correct namespace' do
      expect(key_manager.workflow_keys_namespace).to eq('workflow-keys')
    end
  end

  describe '#timestamp_namespace' do
    it 'should return correct namespace' do
      expect(key_manager.timestamp_namespace).to eq('workflow-timestamps')
    end
  end

  describe '#workflow_key_pattern' do
    it 'should return correct pattern' do
      expect(key_manager.workflow_key_pattern).to eq("#{configuration.namespace}.*")
    end
  end

  describe '#succeeded_workflow_key_pattern' do
    it 'should return correct pattern' do
      expect(key_manager.succeeded_workflow_key_pattern).to eq("#{configuration.namespace}.*_*_[^0]*")
    end

    it 'should match completed workflow keys' do
      completed_key = "#{configuration.namespace}.123_1234567890_1234567900"
      expect(completed_key).to match(/#{configuration.namespace}\..*_.*_[^0].*/)
    end

    it 'should not match in-progress workflow keys' do
      in_progress_key = "#{configuration.namespace}.123_1234567890_0"
      expect(in_progress_key).not_to match(/#{configuration.namespace}\..*_.*_[^0].*/)
    end
  end
end
