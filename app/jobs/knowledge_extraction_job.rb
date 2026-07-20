# Heavy, long-running OCR + knowledge extraction for extended documents (books,
# patents). Runs on the isolated :long_ocr queue so it never starves the default
# queue, and drives the on-demand Unlimited-OCR backend via LongOcr::Pipeline.
class KnowledgeExtractionJob < ApplicationJob
  queue_as :long_ocr

  def perform(extraction_id)
    extraction = KnowledgeExtraction.find_by(id: extraction_id)
    return if extraction.nil?
    return if extraction.complete? || extraction.canceled?

    LongOcr::Pipeline.new(extraction).run
  end
end
