class OpsDeploy::CLI::GitHub
  attr_accessor :deployment_info

  def initialize(token, deployment_info)
    self.token = token
    self.deployment_info = deployment_info
  end

  def create_deployment_status(state)
    return unless valid?
    
    owner, repo = deployment_info[:owner], deployment_info[:repo]
    deployment_id = deployment_info[:deployment_id]
    url = "https://api.github.com/repos/#{owner}/#{repo}/deployments/#{deployment_id}"

    client = Octokit::Client.new(access_token: token)
    client.create_deployment_status(url, state, deployment_info[:options])
    
    self.deployment_info = nil
  end

  def valid?
    token && deployment_info &&
    deployment_info[:owner] && deployment_info[:repo] && deployment_info[:deployment_id]
  end

  private

  attr_accessor :token
end
