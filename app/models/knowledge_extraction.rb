# Tracks a single long-document OCR + knowledge-extraction task that runs on the
# heavy, on-demand Unlimited-OCR backend (see LongOcr::*). Short documents keep
# the synchronous Surya path in AttachmentOcrJob and never create a row here.
class KnowledgeExtraction < ApplicationRecord
  IDEA_ATTACHMENT = "idea_attachment".freeze
  KB_FILE = "kb_file".freeze
  SOURCE_KINDS = [IDEA_ATTACHMENT, KB_FILE].freeze

  # Statuses considered "in flight" — used by the idle supervisor to decide
  # whether the heavy backend may be stopped.
  ACTIVE_STATUSES = %w[pending starting processing enriching].freeze

  belongs_to :idea, optional: true

  enum :status, {
    pending: 0,
    starting: 1,
    processing: 2,
    enriching: 3,
    complete: 4,
    failed: 5,
    canceled: 6
  }

  validates :status, presence: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES.map { |s| statuses.fetch(s) }) }

  def self.active?
    active.exists?
  end

  # Create + enqueue extraction for an idea's source attachment. Idempotent:
  # returns any in-flight extraction for the same attachment instead of duplicating.
  def self.enqueue_for_attachment(attachment, force: false)
    existing = active.find_by(attachment_id: attachment.id)
    return existing if existing && !force

    idea_id = attachment.record_type == "Idea" ? attachment.record_id : nil
    extraction = create!(
      source_kind: IDEA_ATTACHMENT,
      idea_id: idea_id,
      attachment_id: attachment.id,
      source_filename: attachment.filename.to_s,
      status: :pending
    )
    attachment.update!(ocr_status: "extracting", ocr_error: nil)
    KnowledgeExtractionJob.perform_later(extraction.id)
    extraction
  end

  # Create + enqueue extraction for a KB file on disk. Idempotent per path.
  def self.enqueue_for_kb(folder_index:, kb_path:)
    existing = active.find_by(kb_path: kb_path)
    return existing if existing

    extraction = create!(
      source_kind: KB_FILE,
      kb_folder_index: folder_index,
      kb_path: kb_path,
      source_filename: File.basename(kb_path),
      status: :pending
    )
    KnowledgeExtractionJob.perform_later(extraction.id)
    extraction
  end

  def idea_attachment?
    source_kind == IDEA_ATTACHMENT
  end

  def kb_file?
    source_kind == KB_FILE
  end

  # The source ActiveStorage attachment being extracted (idea sources only).
  def attachment
    return nil if attachment_id.blank?

    @attachment ||= ActiveStorage::Attachment.find_by(id: attachment_id)
  end

  # The generated markdown attachment produced for idea sources.
  def output_attachment
    return nil if output_attachment_id.blank?

    ActiveStorage::Attachment.find_by(id: output_attachment_id)
  end

  def progress_percent
    return 0 if page_count.to_i.zero?

    [(pages_done.to_f / page_count * 100).round, 100].min
  end

  def display_name
    source_filename.presence ||
      attachment&.filename&.to_s ||
      (kb_path && File.basename(kb_path)) ||
      "document"
  end

  def in_flight?
    ACTIVE_STATUSES.include?(status)
  end

  def mark_started!(backend:, page_count:)
    update!(status: :processing, backend: backend, page_count: page_count, started_at: Time.current, error: nil)
  end

  def mark_failed!(message)
    update!(status: :failed, error: message.to_s.truncate(2000), finished_at: Time.current)
  end
end
