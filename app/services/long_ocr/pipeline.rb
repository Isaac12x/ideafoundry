module LongOcr
  # Drives one KnowledgeExtraction end to end: brings up the heavy backend,
  # rasterizes the document page by page (via the cheap ocr_service), OCRs each
  # page on the heavy model, assembles markdown, writes the output beside the
  # source (KB) or attaches it to the idea, then runs enrichment for ideas.
  class Pipeline
    EXTENSION_CONTENT_TYPES = {
      ".pdf" => "application/pdf",
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".webp" => "image/webp",
      ".tif" => "image/tiff",
      ".tiff" => "image/tiff"
    }.freeze

    def initialize(extraction, backend: nil, client: nil, supervisor: nil, logger: Rails.logger)
      @extraction = extraction
      @backend = backend || Backend.current
      @client = client || Client.new(backend: @backend)
      @supervisor = supervisor || ServiceSupervisor.new(backend: @backend, client: @client, logger: logger)
      @logger = logger
    end

    def run
      bytes, filename, content_type = source

      @extraction.update!(status: :starting, backend: @backend.to_s, source_filename: filename, error: nil)
      @supervisor.ensure_up!

      page_count = probe_page_count(bytes, filename, content_type)
      @extraction.mark_started!(backend: @backend.to_s, page_count: page_count)

      markdown = ocr_all_pages(bytes, filename, content_type, page_count)

      @extraction.update!(markdown: markdown)
      deliver(markdown)
      @extraction.update!(status: :complete, finished_at: Time.current)
    rescue StandardError => e
      @logger&.error("[long_ocr] extraction #{@extraction.id} failed: #{e.class}: #{e.message}")
      @extraction.mark_failed!(e.message)
      mark_source_failed
      raise
    end

    private

    # Rasterize the document and OCR it via the heavy model. The recipe's
    # multi-image (base mode) path: all pages go in ONE request by default.
    # OCR_LONG_PAGES_PER_REQUEST caps images per request when VRAM can't hold
    # the whole document — the model only guarantees ~8 GB for single images,
    # so very large books may need a small cap; results are concatenated.
    def ocr_all_pages(bytes, filename, content_type, page_count)
      per_request = pages_per_request
      per_request = page_count if per_request.zero?

      markdown = []
      done = 0
      (1..page_count).each_slice(per_request) do |page_numbers|
        images = page_numbers.map do |page|
          OcrClient.render_page(bytes: bytes, filename: filename, content_type: content_type, page: page)
        end
        markdown << @client.ocr_pages(images)
        done += images.length
        @extraction.update_columns(pages_done: done, updated_at: Time.current)
      end
      markdown.reject(&:blank?).join("\n\n")
    end

    def pages_per_request
      [ENV.fetch("OCR_LONG_PAGES_PER_REQUEST", "0").to_i, 0].max
    end

    def deliver(markdown)
      if @extraction.kb_file?
        deliver_kb(markdown)
      else
        deliver_idea(markdown)
      end
    end

    # KB: write "<book>.md" beside the source so it appears in the KB tree.
    def deliver_kb(markdown)
      output = kb_output_path
      File.write(output, markdown)
      @extraction.update!(output_path: output)
    end

    # Idea: attach the markdown as a new document, mirror it onto the source
    # attachment's ocr_text (so sidebar search finds the book), then enrich.
    def deliver_idea(markdown)
      idea = @extraction.idea
      source = @extraction.attachment
      parts = markdown.lines.map(&:strip).reject(&:blank?)

      output_attachment = nil
      Idea.without_history_tracking do
        idea.attachments.attach(
          io: StringIO.new(markdown),
          filename: extracted_filename,
          content_type: "text/markdown"
        )
        idea.reload
        output_attachment = idea.attachments_attachments.order(created_at: :desc).first
        output_attachment&.update!(
          ocr_status: "complete",
          ocr_text: markdown,
          ocr_metadata: { "parts" => parts, "engine" => "long_ocr", "backend" => @backend.to_s }
        )
      end

      source&.update!(
        ocr_status: "complete",
        ocr_text: markdown,
        ocr_metadata: { "parts" => parts, "engine" => "long_ocr", "backend" => @backend.to_s },
        ocr_error: nil
      )
      @extraction.update!(output_attachment_id: output_attachment&.id)

      run_enrichment(idea)
    end

    def run_enrichment(idea)
      return unless idea

      @extraction.update!(status: :enriching)
      IdeaEnrichmentService.new(idea).enrich
    rescue StandardError => e
      # Enrichment is best-effort; a failure here must not fail the extraction.
      @logger&.warn("[long_ocr] enrichment failed for idea #{idea&.id}: #{e.message}")
    end

    def mark_source_failed
      @extraction.attachment&.update!(ocr_status: "failed", ocr_error: @extraction.error)
    rescue StandardError
      nil
    end

    def source
      if @extraction.kb_file?
        bytes = File.binread(@extraction.kb_path)
        filename = File.basename(@extraction.kb_path)
        [bytes, filename, content_type_for(filename)]
      else
        attachment = @extraction.attachment
        raise "source attachment missing" unless attachment

        [attachment.blob.download, attachment.filename.to_s, attachment.blob.content_type]
      end
    end

    def probe_page_count(bytes, filename, content_type)
      result = OcrClient.probe(bytes: bytes, filename: filename, content_type: content_type)
      [result["page_count"].to_i, 1].max
    end

    def kb_output_path
      dir = File.dirname(@extraction.kb_path)
      base = File.basename(@extraction.kb_path, File.extname(@extraction.kb_path))
      candidate = File.join(dir, "#{base}.md")
      candidate = File.join(dir, "#{base}.extracted.md") if File.exist?(candidate)
      candidate
    end

    def extracted_filename
      base = File.basename(@extraction.source_filename.to_s, File.extname(@extraction.source_filename.to_s))
      base = "document" if base.blank?
      "#{base}.extracted.md"
    end

    def content_type_for(filename)
      EXTENSION_CONTENT_TYPES[File.extname(filename).downcase] || "application/octet-stream"
    end
  end
end
