class IdeaAttachmentsController < ApplicationController
  before_action :set_user
  before_action :set_idea

  def create
    files = Array(params[:files]).compact_blank
    return render json: { error: "No files provided" }, status: :bad_request if files.empty?

    existing_ids = @idea.attachments_attachments.pluck(:id)
    new_attachments = []

    Idea.without_history_tracking do
      @idea.attachments.attach(files)
      @idea.reload

      new_attachments = @idea.attachments_attachments.where.not(id: existing_ids).order(:position, :created_at).to_a
      new_attachments.each do |a|
        next unless AttachmentOcrJob.ocr_supported?(a)
        a.update!(ocr_status: "queued")
        AttachmentOcrJob.perform_later(a.id)
      end
    end
    @idea.record_history!("Updated media", automatic: true) if new_attachments.any?

    html = new_attachments.map { |attachment|
      render_to_string(partial: "idea_attachments/item", formats: [:html], locals: { attachment: attachment, idea: @idea })
    }.join

    render json: { success: true, html: html }
  end

  def destroy
    attachment = @idea.attachments_attachments.find(params[:id])
    attachment.purge
    head :no_content
  end

  def update
    attachment = @idea.attachments_attachments.find(params[:id])

    if params[:filename].present?
      attachment.blob.update!(filename: params[:filename])
    end

    if params[:file].present?
      position = attachment.position
      attachment.purge
      @idea.attachments.attach(params[:file])
      @idea.reload
      attachment = @idea.attachments_attachments.order(created_at: :desc).first
      attachment.update!(position: position)
    end

    html = render_to_string(partial: "idea_attachments/item", formats: [:html], locals: { attachment: attachment, idea: @idea })
    render json: { success: true, html: html }
  end

  def reorder
    ids = Array(params[:attachment_ids]).map(&:to_i)
    attachments = @idea.attachments.attachments.where(id: ids).index_by(&:id)

    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, index|
        attachment = attachments.fetch(id)
        attachment.update!(position: index + 1)
      end
    end

    render json: { success: true, attachment_ids: @idea.ordered_attachments.map(&:id) }
  end

  def ocr
    attachment = @idea.attachments.attachments.find(params[:id])
    attachment.update!(ocr_status: "queued", ocr_error: nil)
    AttachmentOcrJob.perform_later(attachment.id)

    redirect_to edit_idea_path(@idea), notice: "OCR extraction queued for #{attachment.filename}."
  end

  # Manual override: force the heavy long-document pipeline regardless of size.
  def extract_knowledge
    attachment = @idea.attachments.attachments.find(params[:id])
    extraction = KnowledgeExtraction.enqueue_for_attachment(attachment)

    respond_to do |format|
      format.html { redirect_to edit_idea_path(@idea), notice: "Knowledge extraction queued for #{attachment.filename}." }
      format.json { render json: { success: true, extraction_id: extraction.id, status: extraction.status } }
    end
  end

  # Live progress for the knowledge sidebar / item status (polled).
  def extraction_status
    attachment = @idea.attachments.attachments.find(params[:id])
    extraction = KnowledgeExtraction.where(attachment_id: attachment.id).recent.first

    render json: {
      status: extraction&.status || attachment.ocr_status,
      pages_done: extraction&.pages_done,
      page_count: extraction&.page_count,
      progress: extraction&.progress_percent,
      error: extraction&.error
    }
  end

  # Attachment search across extracted OCR / knowledge text for this idea.
  def search
    query = params[:q].to_s.strip.downcase
    results = query.present? ? search_attachments(query) : []
    render json: { results: results }
  end

  private

  def search_attachments(query)
    @idea.ordered_attachments.filter_map do |attachment|
      text = attachment.ocr_text.to_s
      next if text.blank?

      index = text.downcase.index(query)
      next if index.nil?

      {
        attachment_id: attachment.id,
        filename: attachment.filename.to_s,
        kind: attachment.image? ? "image" : "document",
        url: rails_blob_path(attachment, disposition: "inline"),
        snippet: snippet_for(text, index, query.length)
      }
    end
  end

  def snippet_for(text, index, length, window: 60)
    start = [index - window, 0].max
    finish = [index + length + window, text.length].min
    snippet = text[start...finish].to_s.gsub(/\s+/, " ").strip
    snippet = "…#{snippet}" if start.positive?
    snippet = "#{snippet}…" if finish < text.length
    snippet
  end

  def set_user
    @user = User.first
  end

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end
end
