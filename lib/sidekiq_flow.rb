require 'json'
require 'active_support/all'
require 'connection_pool'
require 'redis'
require 'sidekiq'
require 'sinatra/base'
require 'sprockets'
require 'uglifier'

require "sidekiq_flow/version"
require "sidekiq_flow/configuration"
require "sidekiq_flow/client"
require "sidekiq_flow/model"
require "sidekiq_flow/task"
require "sidekiq_flow/workflow"
require "sidekiq_flow/worker"
require "sidekiq_flow/errors"
require "sidekiq_flow/task_trigger_rules/base"
require "sidekiq_flow/task_trigger_rules/all_succeeded"
require "sidekiq_flow/task_trigger_rules/one_succeeded"
require "sidekiq_flow/front/app"
require "sidekiq_flow/front/serializers/workflow_serializer"

module SidekiqFlow
  def self.configure
    yield(configuration)
  end

  def self.configuration
    @configuration ||= Configuration.new
  end
end
