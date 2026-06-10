class GithubRepository < ApplicationRecord
  belongs_to :idea

  validates :repository_url, :owner, :name, presence: true

  def automation_ready?
    has_releases?
  end
end
