class AttachmentOcrJob < ApplicationJob
  queue_as :default

  SUPPORTED_CONTENT_TYPES = %w[
    image/png image/jpeg image/webp image/tiff application/pdf text/plain
  ].freeze

  # Only multi-page formats are worth routing to the heavy pipeline.
  PAGED_CONTENT_TYPES = %w[application/pdf image/tiff].freeze

  def self.ocr_supported?(attachment)
    SUPPORTED_CONTENT_TYPES.include?(attachment.blob.content_type.to_s)
  end

  # Whether the heavy knowledge-extraction pipeline can sensibly handle this
  # attachment (multi-page documents — books, patents). Gates the manual button.
  def self.knowledge_extractable?(attachment)
    PAGED_CONTENT_TYPES.include?(attachment.blob.content_type.to_s)
  end

  def perform(attachment_id)
    attachment = ActiveStorage::Attachment.find(attachment_id)
    return unless self.class.ocr_supported?(attachment)

    if route_to_long_pipeline?(attachment)
      KnowledgeExtraction.enqueue_for_attachment(attachment)
      return
    end

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

  private

  # A document is "long" when the OCR sidecar reports more pages than the
  # configured threshold. Probe failures fall back to the normal Surya path.
  def route_to_long_pipeline?(attachment)
    return false unless PAGED_CONTENT_TYPES.include?(attachment.blob.content_type.to_s)

    OcrClient.probe_attachment(attachment).fetch("needs_long", false)
  rescue OcrClient::Error => e
    Rails.logger.warn("[long_ocr] probe failed for attachment #{attachment.id}, using normal OCR: #{e.message}")
    false
  end
end
