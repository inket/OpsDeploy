module OpsDeploy
  # A class defining a generic 'waiter' thread that waits for tasks to finish
  class Waiter < Thread
    attr_accessor :end_when, :callback, :data

    def initialize(&task)
      @task = task

      super() do
        error = nil

        begin
          loop do
            @data = @task.call
            break if @end_when.call(@data)
            sleep 5
          end
        rescue StandardError => e
          error = e
        end

        @callback.call(@data, error) if @callback

        @data
      end
    end
  end

  # A waiter for deployments
  class DeploymentWaiter < OpsDeploy::Waiter
    def initialize(opsworks, deployment, callback = nil)
      super() do
        find_deployment(opsworks, deployment.deployment_id)
      end

      @end_when = proc do |deployment_obj|
        deployment_obj.status != 'running'
      end

      @callback = callback
    end

    private

    def find_deployment(opsworks, deployment_id)
      deploy = opsworks.describe_deployments(deployment_ids: [deployment_id])
               .deployments.first

      # Retry if there's no duration
      if deploy.status != 'running' && deploy.duration.nil?
        deploy = opsworks.describe_deployments(deployment_ids: [deployment_id])
                 .deployments.first
      end

      deploy
    end
  end

  # A waiter for instance response checks
  class InstanceResponseWaiter < OpsDeploy::Waiter
    module HTTParty
      # Overriding HTTParty's timeout
      class Basement
        default_timeout 30
      end
    end

    def initialize(_opsworks, instance, callback = nil)
      super() do
        instance_ip = instance.public_ip || instance.private_ip
        HTTParty.get("http://#{instance_ip}", verify: false)
      end

      @end_when = proc { true }
      @callback = proc do |data, error|
        callback.call(instance, data, error)
      end
    end
  end
end
