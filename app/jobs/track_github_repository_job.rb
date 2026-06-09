class TrackGithubRepositoryJob < ApplicationJob
  queue_as :default

  def perform(idea_id)
    idea = Idea.includes(:user, :topologies, :github_repository).find_by(id: idea_id)
    return unless idea

    GithubRepositoryTracker.new(idea).sync
  end
end
