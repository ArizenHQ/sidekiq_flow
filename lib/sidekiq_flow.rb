require 'json'
require 'dry-types'
require 'dry-struct'
require 'active_support/all'
require 'connection_pool'
require 'redis'
require 'sidekiq'

require "sidekiq_flow/version"
require "sidekiq_flow/types"
require "sidekiq_flow/configuration"
require "sidekiq_flow/client"
require "sidekiq_flow/model"
require "sidekiq_flow/task"
require "sidekiq_flow/workflow"
require "sidekiq_flow/worker"

module SidekiqFlow
  def self.configure
    yield(configuration)
  end

  def self.configuration
    @configuration ||= Configuration.new
  end
end
