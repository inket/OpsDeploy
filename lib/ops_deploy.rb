require "aws-sdk"
require "httparty"
require "colorize"
require "slack-notifier"
require "pusher"
require "pusher-client"

class OpsDeploy
  attr_accessor :waiter
  attr_accessor :deployments_callback
  attr_accessor :instances_check_callback

  def initialize(config = nil)
    config = config || {
      region: "us-east-1"
    }

    @opsworks = Aws::OpsWorks::Client.new(config)
  end

  def stacks
    @opsworks.describe_stacks.stacks
  end

  def start_deployment(stack_id_name_or_object, application_id_name_or_object = nil, migrate = false)
    stack = find_stack(stack_id_name_or_object)
    app = find_app(stack, application_id_name_or_object)

    command = { name: "deploy" }
    command["args"] = { migrate: ["true"] } if migrate

    resp = @opsworks.create_deployment({
      stack_id: stack.stack_id,
      app_id: app.app_id,
      command: command
    })

    return (resp && resp.deployment_id)
  end

  def wait_for_deployments(stack_id_name_or_object)
    stack = find_stack(stack_id_name_or_object)

    running_deployments = @opsworks.describe_deployments(stack_id: stack.stack_id).deployments.select {
      |deployment|

      deployment.status == "running"
    }

    if running_deployments.empty?
      false
    else
      waiters = []

      running_deployments.each {
        |deployment|

        waiters << OpsDeploy::DeploymentWaiter.new(@opsworks, deployment, @deployments_callback)
      }

      @waiter = Thread.new(waiters) {
        |deploy_threads|

        deploy_threads.each(&:run)
        deploy_threads.each(&:join)
      }

      @waiter.run
    end
  end

  def check_instances(stack_id_name_or_object)
    stack = find_stack(stack_id_name_or_object)

    running_instances = @opsworks.describe_instances(stack_id: stack.stack_id).instances.select {
      |instance|

      instance.status == "online"
    }

    waiters = []
    running_instances.each {
      |instance|

      waiters << OpsDeploy::InstanceResponseWaiter.new(@opsworks, instance, @instances_check_callback)
    }

    @waiter = Thread.new(waiters) {
      |check_threads|

      check_threads.each(&:run)
      check_threads.each(&:join)
    }

    @waiter.run
  end

  def find_stack(stack_id_name_or_object)
    found_stack = nil

    if stack_id_name_or_object.kind_of?(String)
      begin
        if stack_id_name_or_object.match(/^[0-9a-f\-]+$/)
          found_stack = @opsworks.describe_stacks(stack_ids: [stack_id_name_or_object]).stacks.first
        end
      rescue Aws::OpsWorks::Errors::ResourceNotFoundException
      end

      if found_stack.nil?
        @opsworks.describe_stacks.stacks.each {
          |stack|

          if stack.name == stack_id_name_or_object
            found_stack = stack
            break
          end
        }
      end
    end

    found_stack = stack_id_name_or_object if found_stack.nil?
    invalid_stack_error = StandardError.new("Invalid stack #{found_stack} (#{stack_id_name_or_object}).")
    raise invalid_stack_error unless found_stack.kind_of?(Aws::OpsWorks::Types::Stack)

    found_stack
  end

  def find_app(stack, application_id_name_or_object)
    found_app = nil

    if application_id_name_or_object.kind_of?(String)
      begin
        if application_id_name_or_object.match(/^[0-9a-f\-]+$/)
          found_app = @opsworks.describe_apps({
            app_ids: [application_id_name_or_object]
          }).apps.first
        end
      rescue Aws::OpsWorks::Errors::ResourceNotFoundException
      end

      if found_app.nil?
        @opsworks.describe_apps(stack_id: stack.stack_id).apps.each {
          |app|

          if app.name == application_id_name_or_object
            found_app = app
            break
          end
        }
      end
    elsif application_id_name_or_object.nil?
      apps = @opsworks.describe_apps(stack_id: stack.stack_id).apps
      found_app = apps.first if apps.count == 1
    end

    found_app = application_id_name_or_object if found_app.nil?
    invalid_app_error = StandardError.new("Invalid app #{found_app} (#{application_id_name_or_object}).")
    raise invalid_app_error unless found_app.kind_of?(Aws::OpsWorks::Types::App)

    found_app
  end
end

require_relative "ops_deploy/waiter"
require_relative "ops_deploy/cli"
