# Word-box text for KB images so the viewer can lay selectable text over them.
class KbOcrController < ApplicationController
  include KbFileLookup

  before_action :set_user

  # ponytail: per-process, in-memory only (nothing private persisted); cleared on restart, FIFO-capped.
  INLINE_CACHE = {}
  INLINE_CACHE_MAX = 32
  INLINE_LOCK = Mutex.new

  # 200 {lines:, text:} | 202 {status: "running"} | 200 {status: "unavailable"}
  def show
    file = locate_kb_file
    return head(:not_found) unless file && Kb::MediaTypes.kind_for(file[:abs]) == :image

    unless Kb::ImageOcr.available?
      return render json: { status: "unavailable", fallback_text: extraction_text(file[:abs]) }
    end
    # ponytail: private projects OCR inline, uncached (no private text in app storage).
    return render json: ocr_inline(file[:abs]).merge(status: "done") if private_kb_file?(file)

    hit = Kb::ImageOcr.cached(file[:abs])
    return render json: hit.merge(status: "done") if hit

    KbImageOcrJob.perform_later(file[:abs]) if Kb::ImageOcr.claim!(file[:abs])
    render json: { status: "running" }, status: :accepted
  end

  private

  def ocr_inline(abs)
    key = [ abs, File.mtime(abs).to_f, File.size(abs) ]
    INLINE_LOCK.synchronize { INLINE_CACHE[key] } || Kb::ImageOcr.run!(abs, cache: false).tap do |result|
      INLINE_LOCK.synchronize do
        INLINE_CACHE.shift while INLINE_CACHE.size >= INLINE_CACHE_MAX
        INLINE_CACHE[key] = result
      end
    end
  rescue Kb::ImageOcr::Error => e
    { lines: [], text: "", error: e.message }
  end

  # Existing "View extracted knowledge" output stands in when tesseract is missing.
  def extraction_text(abs)
    KnowledgeExtraction.where(kb_path: abs).recent.first&.markdown
  end
end
