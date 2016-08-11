require 'bundler'
Bundler.setup

gemspec = eval(File.read('ops_deploy.gemspec'))

task build: "#{gemspec.full_name}.gem"

file "#{gemspec.full_name}.gem" => gemspec.files + ['ops_deploy.gemspec'] do
  system 'gem uninstall -ax ops_deploy 2>/dev/null'
  system "rm #{gemspec.full_name}.gem 2>/dev/null"
  system 'gem build ops_deploy.gemspec'
  system "gem install ops_deploy-#{OpsDeploy::VERSION}.gem"
end
