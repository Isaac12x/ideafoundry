require "uri"

class GithubRepositoryTracker
  def initialize(idea, client: GithubClient.new(user: idea.user))
    @idea = idea
    @client = client
  end

  def sync
    unless trackable?
      idea.github_repository&.destroy
      return nil
    end

    repository_ref = self.class.parse_repository_url(idea.github_repository_url)
    unless repository_ref
      idea.github_repository&.destroy
      return nil
    end

    update_repository!(repository_ref)
  end

  def self.parse_repository_url(raw_url)
    value = raw_url.to_s.strip
    return if value.blank?

    if value.match?(/\Agit@github\.com:/i)
      match = value.match(/\Agit@github\.com:(?<owner>[^\/]+)\/(?<name>[^\/]+?)(?:\.git)?\z/i)
      return unless match

      return repository_ref(match[:owner], match[:name])
    end

    uri = URI.parse(value)
    return unless uri.host.to_s.casecmp("github.com").zero?

    owner, name = uri.path.split("/").reject(&:blank?).first(2)
    repository_ref(owner, name)
  rescue URI::InvalidURIError
    nil
  end

  private

  attr_reader :idea, :client

  def self.repository_ref(owner, name)
    owner = owner.to_s.strip
    name = name.to_s.strip.delete_suffix(".git")
    return if owner.blank? || name.blank?

    {
      owner: owner,
      name: name,
      url: "https://github.com/#{owner}/#{name}"
    }
  end

  def trackable?
    idea.software_topology? && idea.github_repository_url.present?
  end

  def update_repository!(repository_ref)
    repository_data = client.repository(repository_ref[:owner], repository_ref[:name])
    latest_release = client.latest_release(repository_ref[:owner], repository_ref[:name])
    repository = idea.github_repository || idea.build_github_repository

    repository.update!(
      repository_url: repository_data["html_url"].presence || repository_ref[:url],
      owner: repository_ref[:owner],
      name: repository_ref[:name],
      default_branch: repository_data["default_branch"],
      private: ActiveModel::Type::Boolean.new.cast(repository_data["private"]) == true,
      has_releases: latest_release.present?,
      latest_release_tag: latest_release&.dig("tag_name"),
      latest_release_url: latest_release&.dig("html_url"),
      last_checked_at: Time.current,
      last_error: nil
    )

    repository
  rescue GithubClient::Error => e
    repository = idea.github_repository || idea.build_github_repository(
      repository_url: repository_ref[:url],
      owner: repository_ref[:owner],
      name: repository_ref[:name]
    )
    repository.update!(last_checked_at: Time.current, last_error: e.message)
    repository
  end
end
