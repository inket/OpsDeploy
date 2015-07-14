class OpsDeploy::Waiter < Thread
  attr_accessor :end_when, :callback, :data

  def initialize(&task)
    @task = task

    super() {
      error = nil

      begin
        until false
          @data = @task.call
          break if @end_when.call(@data)
          sleep 5
        end
      rescue StandardError => e
        error = e
      end

      @callback.call(@data, error) if @callback

      @data
    }
  end
end

class OpsDeploy::DeploymentWaiter < OpsDeploy::Waiter
  def initialize(opsworks, deployment, callback = nil)
    super() {
      deploy = opsworks.describe_deployments(deployment_ids: [deployment.deployment_id]).deployments.first

      # Retry if there's no duration
      if deploy.status != "running" and deploy.duration.nil?
        deploy = opsworks.describe_deployments(deployment_ids: [deployment.deployment_id]).deployments.first
      end

      deploy
    }

    @end_when = Proc.new {
      |deployment_obj|
      deployment_obj.status != "running"
    }

    @callback = callback
  end
end

class OpsDeploy::InstanceResponseWaiter < OpsDeploy::Waiter
  class HTTParty::Basement
    default_timeout 30
  end

  def initialize(opsworks, instance, callback = nil)
    super() {
      instance_ip = instance.public_ip || instance.private_ip
      HTTParty.get("http://#{instance_ip}", verify: false)
    }

    @end_when = Proc.new { true }
    @callback = Proc.new {
      |data, error|
      callback.call(instance, data, error)
    }
  end
end
