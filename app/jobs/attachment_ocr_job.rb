class AttachmentOcrJob < ApplicationJob
  queue_as :default

  SUPPORTED_CONTENT_TYPES = %w[
    image/png image/jpeg image/webp image/tiff application/pdf text/plain
  ].freeze

  def self.ocr_supported?(attachment)
    SUPPORTED_CONTENT_TYPES.include?(attachment.blob.content_type.to_s)
  end

  def perform(attachment_id)
    attachment = ActiveStorage::Attachment.find(attachment_id)
    return unless self.class.ocr_supported?(attachment)

    attachment.update!(ocr_status: "processing", ocr_error: nil)
    result = OcrClient.extract(attachment)
    text = result.fetch("text", "").to_s
    parts = Array(result["parts"]).map(&:to_s).map(&:strip).reject(&:blank?)
    parts = text.lines.map(&:strip).reject(&:blank?) if parts.empty?

    attachment.update!(
      ocr_status: "complete",
      ocr_text: text,
      ocr_metadata: result.merge("parts" => parts),
      ocr_error: nil
    )
  rescue => e
    attachment&.update!(ocr_status: "failed", ocr_error: e.message)
    raise
  end
end
