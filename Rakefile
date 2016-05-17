require 'bundler'
Bundler.setup

gemspec = eval(File.read('ops_deploy.gemspec'))

task build: "#{gemspec.full_name}.gem"

file "#{gemspec.full_name}.gem" => gemspec.files + ['ops_deploy.gemspec'] do
  system 'gem uninstall -x ops_deploy'
  system "rm #{gemspec.full_name}.gem"
  system 'gem build ops_deploy.gemspec'
  system "gem install ops_deploy-#{OpsDeploy::VERSION}.gem"
end
