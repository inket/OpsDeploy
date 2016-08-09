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

If you want to post info about the latest commit to slack:
WARNING: This posts the latest commit in the current local git branch, not the latest one on github

```shell
opsdeploy deploy wait check --stack="Example" --aws-region="us-east-1" --post-latest-commit=true
```

Output:

```
-> Getting stack 'Example'...
-> Found stack 'Example' (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
-> Latest commit:  commit b5fed5c32df0613df06a8e1452d194cafabc22bc
Author: Martin Morava <martin.morava@example.com>
Date:   Tue Aug 9 11:49:56 2016 +0200

    Enable Slack notifications about the latest commit
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
