# A pending/running background download into a KB folder, created when a user
# "creates a file" whose name is a URL. KbDownloadJob does the fetching; status
# changes broadcast a tree row via Turbo so the sidebar updates live.
class KbDownload < ApplicationRecord
  belongs_to :user

  STATUSES = %w[pending running done failed].freeze
  FORMATS  = %w[auto video audio].freeze

  validates :url, presence: true, format: { with: %r{\Ahttps?://\S+\z}i }
  validates :status, inclusion: { in: STATUSES }
  validates :format, inclusion: { in: FORMATS }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[pending running]) }

  after_create_commit :broadcast_tree
  after_update_commit :broadcast_tree, if: :saved_change_to_status?

  # Create the record and enqueue the fetch. dir is relative to the source root.
  def self.enqueue(user:, source_index:, dir:, url:, format: "auto")
    source = KbSource.list(user)[source_index]
    raise ArgumentError, "KB source is not available" unless source

    download = user.kb_downloads.create!(
      source_index: source_index,
      source_path: File.expand_path(source[:path]),
      dir: dir.to_s,
      url: url.to_s.strip,
      format: FORMATS.include?(format.to_s) ? format.to_s : "auto",
      status: "pending"
    )
    KbDownloadJob.perform_later(download.id)
    download
  end

  def done?   = status == "done"
  def failed? = status == "failed"

  # Path of the finished file relative to its source root (for kb_file links).
  def file_rel
    return nil if filename.blank?
    dir.present? ? File.join(dir, filename) : filename
  end

  def label = filename.presence || url

  private

  def broadcast_tree
    Kb::TreeBroadcaster.call(user)
  end
end
