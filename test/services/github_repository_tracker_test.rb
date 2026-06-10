require "test_helper"

class GithubRepositoryTrackerTest < ActiveSupport::TestCase
  class FakeGithubClient
    def repository(owner, name)
      {
        "html_url" => "https://github.com/#{owner}/#{name}",
        "default_branch" => "main",
        "private" => false
      }
    end

    def latest_release(owner, name)
      {
        "tag_name" => "v1.0.0",
        "html_url" => "https://github.com/#{owner}/#{name}/releases/tag/v1.0.0"
      }
    end
  end

  test "tracks release state for software ideas with github urls" do
    user = users(:one)
    software = user.topologies.create!(name: "Software", topology_type: :custom)
    idea = Idea.create!(
      user: user,
      title: "Release-backed project",
      metadata: { "github_url" => "https://github.com/acme/widgets" }
    )
    idea.topologies << software

    repository = GithubRepositoryTracker.new(idea, client: FakeGithubClient.new).sync

    assert_equal idea, repository.idea
    assert_equal "https://github.com/acme/widgets", repository.repository_url
    assert_equal "acme", repository.owner
    assert_equal "widgets", repository.name
    assert_equal "main", repository.default_branch
    assert_equal true, repository.has_releases?
    assert_equal "v1.0.0", repository.latest_release_tag
    assert repository.last_checked_at.present?
  ensure
    idea&.destroy
    software&.destroy
  end
end
