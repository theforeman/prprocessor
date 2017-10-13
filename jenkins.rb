require 'rest_client'

class Jenkins

  def initialize
  end

  def build(repo, pr_number)
    params = [
      "token=#{token}",
      "cause=#{URI.encode("GitHub PR trigger: #{repo} ##{pr_number}")}",
      "project=#{repo}",
      "pr_number=#{pr_number}"
    ]

    RestClient.post("https://ci.theforeman.org/job/pull_request_scanner/buildWithParameters?#{params.join('&')}", '') do |response, request, result, &block|
      case response.code
      when 302
        "repo #{repo} scan triggered"
      else
        response.return!(request, result, &block)
        "repo #{repo} scan may have been triggered"
      end
    end
  end

  def token
    ENV['JENKINS_TOKEN']
  end

end
