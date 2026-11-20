# A NEED worth solving ("slippery train tracks"). Lives in the native KB as Problems/<slug>/problem.md; research
# (Wikipedia/Grokipedia articles + .source.json sidecars) lands next to it via ProblemLookupJob. Ideas link to the
# folder through IdeaKbLink. Facts (IPF/BPF) are observations that spark ideas; a Problem is the need an idea answers.
class Problem < ApplicationRecord
  include SemanticIndexable
  semantic_index type: "problem", owner: ->(r) { r.user_id }, sections: ->(r) { [ r.title, r.need, *SemanticIndex.split(r.result) ] }
  STATUSES = %w[pending running done failed].freeze

  belongs_to :user

  before_validation :set_folder, on: :create
  validates :title, presence: true, length: { maximum: 200 }
  validates :folder, uniqueness: { scope: :user_id, message: "already exists" }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def abs_dir = File.join(KbSource::NATIVE_PATH, folder)

  def busy? = %w[pending running].include?(status)

  def idea_links = IdeaKbLink.where(source_path: KbSource::NATIVE_PATH, relative_path: folder, idea_id: user.ideas.select(:id))

  # Queue (or re-queue) the lookup; never blocks the request.
  def find_sources!
    update!(status: "pending", result: nil)
    ProblemLookupJob.perform_later(id)
  end

  private

  def set_folder
    slug = title.to_s.parameterize.first(60)
    self.folder = "Problems/#{slug}" if slug.present?
  end
end
