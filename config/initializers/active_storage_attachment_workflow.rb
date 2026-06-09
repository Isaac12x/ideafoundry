module ActiveStorageAttachmentWorkflow
  extend ActiveSupport::Concern

  included do
    serialize :ocr_metadata, coder: JSON
    before_create :assign_default_position, if: :idea_attachment?
  end

  def idea_attachment?
    record_type == "Idea" && name == "attachments"
  end

  def ocr_parts
    Array(ocr_metadata&.dig("parts")).presence || ocr_text.to_s.lines.map(&:strip).reject(&:blank?)
  end

  def ocr_complete?
    ocr_status == "complete" && ocr_text.present?
  end

  private

  def assign_default_position
    return if position.present?

    max_position = self.class.where(record: record, name: name).maximum(:position).to_i
    self.position = max_position + 1
  end
end

ActiveSupport.on_load(:active_storage_attachment) do
  include ActiveStorageAttachmentWorkflow
end
