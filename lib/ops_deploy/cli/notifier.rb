# Notifier
class OpsDeploy::CLI::Notifier
  attr_accessor :options
  attr_accessor :messages
  attr_accessor :notification_type

  def initialize(options)
    @options = options
    @options.delete(:slack) if @options[:slack].nil? || @options[:slack][:webhook_url].nil?
    @messages = OpsDeploy::CLI::Notifier::Messages.new
    @notification_type = :info
  end

  def notify(stack)
    if @notification_type == :failure
      message = @messages.failure.join("\n")
      failure_notify(stack, message)
    elsif @notification_type == :success
      message = @messages.success.join("\n")
      success_notify(stack, message)
    else
      message = @messages.info.join("\n")
      info_notify(stack, message)
    end
  end

  def info_notify(stack, message)
    return unless @options[:slack]

    OpsDeploy::CLI::Notifier::Slack.new(stack, @options[:slack])
      .notify(message)
  end

  def success_notify(stack, message)
    return unless @options[:slack]

    OpsDeploy::CLI::Notifier::Slack.new(stack, @options[:slack])
      .success_notify(message)
  end

  def failure_notify(stack, message)
    return unless @options[:slack]

    OpsDeploy::CLI::Notifier::Slack.new(stack, @options[:slack])
      .failure_notify(message) if @options[:slack]
  end

  def reset
    @messages = OpsDeploy::CLI::Notifier::Messages.new
    @notification_type = :info
  end
end

# A messages container class
class OpsDeploy::CLI::Notifier::Messages
  attr_accessor :info, :success, :failure

  def initialize
    @info = []
    @success = []
    @failure = []
  end
end

# A generic notification class from which all notification services will inherit
class OpsDeploy::CLI::Notifier::Generic
end

# A notification class for Slack
class OpsDeploy::CLI::Notifier::Slack < OpsDeploy::CLI::Notifier::Generic
  attr_accessor :slack_notifier
  attr_accessor :options

  def initialize(stack, options)
    @stack = stack
    @options = options
    @options[:username] = 'OpsDeploy' unless @options[:username]
    @slack_notifier = Slack::Notifier.new @options[:webhook_url], @options
  end

  def notify(message)
    message = message.gsub(/\[[0-9;]+?m/, '')

    recipients.each do |recipient|
      @slack_notifier.ping '', channel: recipient, attachments: [
        {
          fallback: message,
          author_name: @stack.name,
          author_link: stack_link(@stack),
          text: message
        }
      ]
    end
  end

  def success_notify(message)
    message = message.gsub(/\[[0-9;]+?m/, '')

    recipients.each do |recipient|
      @slack_notifier.ping '', channel: recipient, attachments: [
        {
          fallback: message,
          text: message,
          author_name: @stack.name,
          author_link: stack_link(@stack),
          color: 'good'
        }
      ]
    end
  end

  def failure_notify(message)
    message = message.gsub(/\[[0-9;]+?m/, '')

    recipients.each do |recipient|
      @slack_notifier.ping '', channel: recipient, attachments: [
        {
          fallback: message,
          text: "#{message} <!channel>",
          author_name: @stack.name,
          author_link: stack_link(@stack),
          color: 'danger'
        }
      ]
    end
  end

  private

  def recipients
    names = [options[:channel]]
    names << "@#{options[:notify_user]}" if options[:notify_user]
    names
  end

  def stack_link(stack)
    region = OpsDeploy::CLI.argument('aws-region', 'AWS_REGION') || 'us-east-1'
    params = "?region=#{region}#/stack/#{stack.stack_id}/stack"

    "https://console.aws.amazon.com/opsworks/home#{params}"
  end
end
