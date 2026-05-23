require "json"
require "net/http"
require "uri"

class GithubClient
  class Error < StandardError; end
  class NotFound < Error; end

  def initialize(user:)
    @user = user
  end

  def repository(owner, name)
    get_json("/repos/#{owner}/#{name}")
  end

  def latest_release(owner, name)
    Array(get_json("/repos/#{owner}/#{name}/releases?per_page=1")).first
  end

  private

  attr_reader :user

  def get_json(path)
    uri = URI.join(api_base_url, path)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["Authorization"] = "Bearer #{user.github_token}" if user.github_token.present?

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end

    case response.code.to_i
    when 200
      JSON.parse(response.body)
    when 404
      raise NotFound, "GitHub repository or release endpoint was not found"
    else
      raise Error, "GitHub API returned #{response.code}: #{response.body.to_s.truncate(160)}"
    end
  end

  def api_base_url
    user.github_settings["api_base_url"]
  end
end
