### OpsDeploy

A simple gem to perform deployment & checks on AWS OpsWorks. You can deploy, wait for deployments to finish, and check on the instances responses for a successful deployment flow. Also implements Slack notifications for each step.

### Usage

```shell
gem install ops_deploy
```

In your code:

```ruby
require 'ops_deploy'
ops = OpsDeploy.new(aws_config)

# Start deployment (sync)
success = ops.start_deployment(stack_id, app_id, migrate)

# Wait for deployments (async)
ops.deployments_callback = Proc.new {
  |aws_deployment_obj|
  # whatever
}
a_thread = ops.wait_for_deployments(stack_id)
a_thread.join

# Check instances (async)
ops.instances_check_callback = Proc.new {
  |aws_instance_obj, http_response, exception|
  # whatever
}
a_thread = ops.check_instances(stack_id)
a_thread.join

```

or using the CLI:

```shell
opsdeploy <tasks> --aws-region=<aws_region> --aws-profile=<...> --stack=<stack_name_or_id> --slack-webhook-url=<...> --slack-username=<...> --slack-channel=<...>
```

The tasks are:

- deploy (starts a deployment)
- migrate (will also migrate during the deployment [for Rails apps])
- wait (waits for the deployments)
- check (checks the instances)

Example:

```shell
opsdeploy deploy wait check --stack="Example" --aws-region="us-east-1"
```

Output:

```
-> Getting stack 'Example'...
-> Found stack 'Example' (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
-> Starting deployment on stack 'Example'...
✓ Deployment started on stack 'Example'
-> Checking deployments...
-> Waiting for deployments to finish...
..............................................................
✓ Deployment OK (58s)
// Deployments finished
-> Checking instances' HTTP response...
.
✓ Response from rails-app1: 200 OK
// Response check finished
```
