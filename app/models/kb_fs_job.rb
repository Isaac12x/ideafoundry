class KbFsJob < ApplicationRecord
  STATUSES = %w[pending running done failed].freeze
  CONTEXT_KINDS = %w[file folder].freeze

  belongs_to :user
  has_one_attached :voice_message

  validates :source_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_path, :context_path, presence: true
  validates :context_kind, inclusion: { in: CONTEXT_KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }
  scope :visible_in_tree, -> {
    active.or(where(status: "failed", result_path: nil).where(updated_at: 7.days.ago..))
  }

  after_create_commit :broadcast_tree
  after_update_commit :broadcast_tree, if: :saved_change_to_status?

  def self.enqueue(user:, source_index:, source_path:, context_path:, context_kind:, target_dir:, prompt:, voice_message: nil)
    job = user.kb_fs_jobs.create!(
      source_index: source_index,
      source_path: KbEntryPreference.normalize_source_path(source_path),
      context_path: KbEntryPreference.normalize_relative_path(context_path),
      context_kind: context_kind,
      target_dir: KbEntryPreference.normalize_relative_path(target_dir),
      prompt: prompt.to_s.strip.presence,
      status: "pending"
    )
    job.voice_message.attach(voice_message) if voice_message.present?
    KbFsJobRunnerJob.perform_later(job.id)
    job
  end

  def pending? = status == "pending"
  def running? = status == "running"
  def done? = status == "done"
  def failed? = status == "failed"

  def request_text
    transcript.presence || prompt.presence || "Review this context and produce useful next-step information."
  end

  def label
    (prompt.presence || transcript.presence || "Voice request").truncate(44)
  end

  private

  def broadcast_tree
    Kb::TreeBroadcaster.call(user)
  end
end
