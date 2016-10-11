require File.expand_path('../lib/ops_deploy/version', __FILE__)

Gem::Specification.new do |s|
  s.name        = 'ops_deploy'
  s.version     = OpsDeploy::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Mahdi Bchetnia']
  s.email       = ['injekter@gmail.com']
  s.homepage    = 'http://github.com/inket/OpsDeploy'
  s.summary     = 'Perform deployment & checks on AWS OpsWorks'
  s.description = 'Perform deployment & checks on AWS OpsWorks. You can deploy, wait for deployments to finish, and check on the instances responses for a successful deployment flow. Also implements Slack notifications for each step.'

  s.required_rubygems_version = '>= 1.3.6'
  s.rubyforge_project         = 'ops_deploy'
  s.files                     = Dir['{lib}/**/*.rb', 'bin/*', 'LICENSE', '*.md']
  s.require_path              = 'lib'
  s.executables               = ['opsdeploy']
  s.license                   = 'MIT'

  s.add_dependency 'aws-sdk', '~> 2.1'
  s.add_dependency 'httparty', '~> 0.13'
  s.add_dependency 'colorize', '~> 0.7'
  s.add_dependency 'slack-notifier', '~> 1.2'
  s.add_dependency 'pusher', '~> 0.14'
  s.add_dependency 'pusher-client', '~> 0.6'
  s.add_dependency 'octokit', '~> 4.3'
end
