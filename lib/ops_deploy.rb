require 'aws-sdk'
require 'httparty'
require 'colorize'
require 'slack-notifier'
require 'pusher'
require 'pusher-client'

class OpsDeploy
  attr_accessor :waiter
  attr_accessor :deployments_callback
  attr_accessor :instances_check_callback

  def initialize(config = nil)
    config ||= {
      region: 'us-east-1'
    }

    @opsworks = Aws::OpsWorks::Client.new(config)
  end

  def stacks
    @opsworks.describe_stacks.stacks
  end

  def start_deployment(stack_id_name_or_object, application_id_name_or_object = nil, migrate = false)
    stack = find_stack(stack_id_name_or_object)
    app = find_app(stack, application_id_name_or_object)

    command = { name: 'deploy' }
    command['args'] = { migrate: ['true'] } if migrate

    resp = @opsworks.create_deployment(stack_id: stack.stack_id,
                                       app_id: app.app_id,
                                       command: command)

    (resp && resp.deployment_id)
  end

  def wait_for_deployments(stack_id_name_or_object)
    stack = find_stack(stack_id_name_or_object)

    running_deployments = @opsworks.describe_deployments(stack_id: stack.stack_id).deployments.select do |deployment|
      deployment.status == 'running'
    end

    if running_deployments.empty?
      false
    else
      waiters = []

      running_deployments.each do |deployment|
        waiters << OpsDeploy::DeploymentWaiter.new(@opsworks, deployment, @deployments_callback)
      end

      @waiter = Thread.new(waiters) do |deploy_threads|
        deploy_threads.each(&:run)
        deploy_threads.each(&:join)
      end

      @waiter.run
    end
  end

  def check_instances(stack_id_name_or_object)
    stack = find_stack(stack_id_name_or_object)

    running_instances = @opsworks.describe_instances(stack_id: stack.stack_id).instances.select do |instance|
      instance.status == 'online'
    end

    waiters = []
    running_instances.each do |instance|
      waiters << OpsDeploy::InstanceResponseWaiter.new(@opsworks, instance, @instances_check_callback)
    end

    @waiter = Thread.new(waiters) do |check_threads|
      check_threads.each(&:run)
      check_threads.each(&:join)
    end

    @waiter.run
  end

  def find_stack(stack_id_name_or_object)
    found_stack = nil

    if stack_id_name_or_object.is_a?(String)
      begin
        if stack_id_name_or_object.match(/^[0-9a-f\-]+$/)
          found_stack = @opsworks.describe_stacks(stack_ids: [stack_id_name_or_object]).stacks.first
        end
      rescue Aws::OpsWorks::Errors::ResourceNotFoundException
      end

      if found_stack.nil?
        @opsworks.describe_stacks.stacks.each do |stack|
          if stack.name == stack_id_name_or_object
            found_stack = stack
            break
          end
        end
      end
    end

    found_stack = stack_id_name_or_object if found_stack.nil?
    invalid_stack_error = StandardError.new("Invalid stack #{found_stack} (#{stack_id_name_or_object}).")
    fail invalid_stack_error unless found_stack.is_a?(Aws::OpsWorks::Types::Stack)

    found_stack
  end

  def find_app(stack, application_id_name_or_object)
    found_app = nil

    if application_id_name_or_object.is_a?(String)
      begin
        if application_id_name_or_object.match(/^[0-9a-f\-]+$/)
          found_app = @opsworks.describe_apps(app_ids: [application_id_name_or_object]).apps.first
        end
      rescue Aws::OpsWorks::Errors::ResourceNotFoundException
      end

      if found_app.nil?
        @opsworks.describe_apps(stack_id: stack.stack_id).apps.each do |app|
          if app.name == application_id_name_or_object
            found_app = app
            break
          end
        end
      end
    elsif application_id_name_or_object.nil?
      apps = @opsworks.describe_apps(stack_id: stack.stack_id).apps
      found_app = apps.first if apps.count == 1
    end

    found_app = application_id_name_or_object if found_app.nil?
    invalid_app_error = StandardError.new("Invalid app #{found_app} (#{application_id_name_or_object}).")
    fail invalid_app_error unless found_app.is_a?(Aws::OpsWorks::Types::App)

    found_app
  end
end

require_relative 'ops_deploy/waiter'
require_relative 'ops_deploy/cli'
