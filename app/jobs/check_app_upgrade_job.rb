require "net/http"

class CheckAppUpgradeJob < ApplicationJob
  queue_as :default

  REPO = "isaac12x/ideafoundry".freeze
  API_URL = "https://api.github.com/repos/#{REPO}/releases/latest".freeze

  def perform
    user = User.first
    return unless user

    current_version = Rails.application.config.app_version
    response = fetch_latest_release(user)
    return unless response

    tag = response["tag_name"].to_s
    return if tag.blank? || tag == current_version

    body = response["body"].to_s.lines.first.to_s.strip
    dist = SemverCompare.distance(current_version, tag)
    sev  = SemverCompare.severity(current_version, tag, response["body"].to_s)

    user.settings ||= {}
    user.settings["upgrade"] = {
      "latest_version" => tag,
      "release_url"    => response["html_url"],
      "release_body"   => body,
      "is_security"    => sev == "red",
      "severity"       => sev,
      "versions_behind" => { "major" => dist[:major], "minor" => dist[:minor], "patch" => dist[:patch] },
      "checked_at"     => Time.current.iso8601
    }
    user.save!
  end

  private

  def fetch_latest_release(user)
    headers = { "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28" }
    token = user.settings&.dig("github", "token").presence
    headers["Authorization"] = "Bearer #{token}" if token

    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Get.new(uri, headers)
    res = http.request(req)
    return nil unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  rescue => e
    Rails.logger.warn("[CheckAppUpgradeJob] Failed to fetch release: #{e.message}")
    nil
  end
end
