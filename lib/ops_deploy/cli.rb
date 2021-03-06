# encoding: utf-8
class OpsDeploy::CLI
  def initialize
    config = {
      region: OpsDeploy::CLI.argument('aws-region', 'AWS_REGION', true)
    }

    profile = OpsDeploy::CLI.argument('aws-profile', 'AWS_PROFILE')
    config[:credentials] = Aws::SharedCredentials.new(profile_name: profile) if profile

    aws_access_key_id = OpsDeploy::CLI.argument('aws-access-key-id', 'AWS_ACCESS_KEY_ID')
    aws_secret_access_key = OpsDeploy::CLI.argument('aws-secret-access-key', 'AWS_SECRET_ACCESS_KEY')
    if aws_access_key_id && aws_secret_access_key
      config[:access_key_id] = aws_access_key_id
      config[:secret_access_key] = aws_secret_access_key
    end

    @main = OpsDeploy.new(config)
    @stacks = {}

    github_token = OpsDeploy::CLI.argument('github-token', 'GITHUB_TOKEN')
    auto_inactive = OpsDeploy::CLI.argument('github-deployment-auto-inactive')
    auto_inactive = [nil, "", "1", "true", "TRUE"].include?(auto_inactive)

    @github = OpsDeploy::CLI::GitHub.new(github_token, {
      owner: OpsDeploy::CLI.argument('github-deployment-owner'),
      repo: OpsDeploy::CLI.argument('github-deployment-repo'),
      deployment_id: OpsDeploy::CLI.argument('github-deployment-deployment-id'),
      options: {
        log_url: OpsDeploy::CLI.argument('github-deployment-log-url'),
        description: OpsDeploy::CLI.argument('github-deployment-description'),
        environment_url: OpsDeploy::CLI.argument('github-deployment-environment-url'),
        auto_inactive: auto_inactive
      }
    })

    @notifier = OpsDeploy::CLI::Notifier.new(slack: {
      webhook_url: OpsDeploy::CLI.argument('slack-webhook-url', 'SLACK_WEBHOOK_URL'),
      username: OpsDeploy::CLI.argument('slack-username', 'SLACK_USERNAME'),
      channel: OpsDeploy::CLI.argument('slack-channel', 'SLACK_CHANNEL'),
      notify_user: OpsDeploy::CLI.argument('slack-notify-user', 'SLACK_NOTIFY_USER')
    })

    @notification_messages = {
      info: [],
      success: [],
      failure: []
    }
    @notification_success = false
    @notification_failure = false
  end

  def post_latest_commit(stack_id_name_or_object)
    stack = find_stack(stack_id_name_or_object)
    latest_commit_description = `git log -1 --pretty=medium`
    step_msg('Latest commit: ', latest_commit_description)
    send_notification(stack)
  end

  def start_deployment(stack_id_name_or_object, application_id = nil, migrate = false)
    stack = find_stack(stack_id_name_or_object)

    step_msg('Starting deployment on stack', "'#{stack.name.blue}'...")

    if @main.start_deployment(stack, application_id, migrate)
      success_msg('Deployment started on stack', "'#{stack.name.green}'")
      send_notification(stack)

      true
    else
      failure_msg("Couldn't start deployment on stack", "'#{stack.name.red}'")
      send_notification(stack)

      false
    end
  end

  def wait_for_deployments(stack_id_name_or_object, via_proxy = false)
    stack = find_stack(stack_id_name_or_object)

    if via_proxy
      Pusher.url = OpsDeploy::CLI.argument('pusher-url', 'PUSHER_URL', true)
      Pusher.trigger('OpsDeploy', 'wait_for_deployments', stack: stack.stack_id,
                                                          slack: @notifier.options[:slack],
                                                          github: @github.deployment_info)
    else
      step_msg('Checking deployments...')

      github = @github.dup

      @main.deployments_callback = proc { |deployment|
        puts
        if (deployment.status == 'successful')
          success_msg('Deployment', 'OK'.green.bold,
                      deployment.duration ? "(#{deployment.duration}s)" : '')
          github.create_deployment_status("success")
        else
          failure_msg('Deployment', 'Failed'.red.bold,
                      deployment.duration ? "(#{deployment.duration}s)" : '')
          github.create_deployment_status("error")
        end
      }

      waiter = @main.wait_for_deployments(stack)
      if waiter
        step_msg('Waiting for deployments to finish...')

        print '.'.blue
        print '.'.blue until waiter.join(1)

        info_msg('Deployments finished')
      else
        info_msg('No running deployments on stack', "'#{stack_id_name_or_object.blue}'")
      end

      send_notification(stack)
    end
  end

  def check_instances(stack_id_name_or_object, via_proxy = false)
    stack = find_stack(stack_id_name_or_object)

    if via_proxy
      Pusher.url = OpsDeploy::CLI.argument('pusher-url', 'PUSHER_URL', true)
      Pusher.trigger('OpsDeploy', 'check_instances', stack: stack.stack_id,
                                                     slack: @notifier.options[:slack])
    else
      @main.instances_check_callback = proc { |instance, response, error|
        puts
        if error.nil? && response.code == 200
          success_msg('Response from', "#{instance.hostname.green}:", '200 OK'.green)
        elsif error.nil?
          failure_msg('Response from', "#{instance.hostname.red}:", "#{response.code}".red)
        else
          failure_msg('Error checking', "#{instance.hostname.red}:", error.to_s)
        end
      }

      waiter = @main.check_instances(stack)
      if waiter
        step_msg("Checking instances' HTTP response...")

        print '.'.blue
        print '.'.blue until waiter.join(1)

        info_msg('Response check finished')
      else
        info_msg('No online instances on stack', "'#{stack_id_name_or_object.blue}'")
      end

      send_notification(stack)
    end
  end

  def start_server
    pusher_comp = URI.parse(OpsDeploy::CLI.argument('pusher-url', 'PUSHER_URL', true))
    PusherClient.logger.level = Logger::ERROR
    socket = PusherClient::Socket.new(pusher_comp.user, secure: true)
    socket.subscribe('OpsDeploy')

    socket['OpsDeploy'].bind('check_instances') do |data|
      begin
        info = data
        info = symbolize_keys(JSON.parse(data)) if data.is_a?(String)

        with_slack(info[:slack]) do
          check_instances(info[:stack])
        end
      rescue StandardError => e
        puts e
      end
    end

    socket['OpsDeploy'].bind('wait_for_deployments') do |data|
      begin
        info = data
        info = symbolize_keys(JSON.parse(data)) if data.is_a?(String)

        @github.deployment_info = info[:github]

        with_slack(info[:slack]) do
          wait_for_deployments(info[:stack])
        end
      rescue StandardError => e
        puts e
      end
    end

    info_msg("Started OpsDeploy server #{OpsDeploy::VERSION}")
    socket.connect
  end

  def with_slack(slack_options = nil)
    old_notifier = @notifier
    @notifier = OpsDeploy::CLI::Notifier.new(slack: slack_options) if slack_options

    yield

    @notifier = old_notifier
  end

  def self.argument(argv_name, env_name = nil, required = false)
    value = nil
    value = ENV[env_name] if env_name

    if value.nil?
      value = ARGV.include?(argv_name) ? true : nil
      return value if value

      ARGV.each do |arg|
        if arg.start_with?("--#{argv_name}=")
          value = arg.split("--#{argv_name}=").last
        end
      end
    end

    if required && value.nil?
      env_name_message = env_name ? "the environment variable #{env_name} or " : ''
      error = "Argument '#{argv_name}' unspecified."
      suggestion = "Please set #{env_name_message}the argument --#{argv_name}=<value>"
      fail StandardError.new("#{error} #{suggestion}")
    end

    value
  end

  private

  def find_stack(stack_id_name_or_object)
    if stack_id_name_or_object.is_a?(String)
      hash = stack_id_name_or_object.hash

      if @stacks[hash].nil?
        step_msg('Getting stack', "'#{stack_id_name_or_object.blue}'...")
        stack = @main.find_stack(stack_id_name_or_object)
        step_msg('Found stack', "'#{stack.name.blue}' (#{stack.stack_id})")

        @notifier.messages.info.pop
        @notifier.messages.info.pop

        @stacks[hash] = stack
      end

      @stacks[hash]
    else
      @main.find_stack(stack_id_name_or_object)
    end
  end

  def success_msg(*args)
    message = '✓ '.green + args.join(' ')
    @notifier.messages.success << message
    @notifier.notification_type = :success unless @notifier.notification_type == :failure
    puts message
    message
  end

  def info_msg(*args)
    message = '// '.blue + args.join(' ')
    @notifier.messages.info << message
    puts message
    message
  end

  def failure_msg(*args)
    message = '╳  '.red + args.join(' ')
    @notifier.messages.failure << message
    @notifier.notification_type = :failure
    puts message
    message
  end

  def step_msg(*args)
    message = '-> '.cyan + args.join(' ')
    @notifier.messages.info << message
    puts message
    message
  end

  def send_notification(stack)
    @notifier.notify(stack)
    @notifier.reset
  end

  def puts(message = nil)
    $stdout.puts(message)
    $stdout.flush
  end

  def print(message = nil)
    $stdout.print(message)
    $stdout.flush
  end

  def symbolize_keys(hash)
    hash.inject({}){|result, (key, value)|
      new_key = case key
                when String then key.to_sym
                else key
                end
      new_value = case value
                  when Hash then symbolize_keys(value)
                  else value
                  end
      result[new_key] = new_value
      result
    }
  end
end

require_relative 'cli/github'
require_relative 'cli/notifier'
