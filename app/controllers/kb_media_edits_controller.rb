class KbMediaEditsController < ApplicationController
  MAX_REPLACEMENT_BYTES = 1.gigabyte

  before_action :set_user

  def create
    source_index = params[:src].to_i
    source = KbSource.list(@user)[source_index]
    return render_error("Knowledge-base source is not available.") unless source

    source_root = File.expand_path(source[:path])
    relative_path = KbEntryPreference.normalize_relative_path(params[:file])
    absolute = safe_file(source_root, relative_path)
    return render_error("The source file is no longer available.") unless absolute

    kind = Kb::MediaTypes.kind_for(absolute).to_s
    return render_error("Markdown uses the document editor.") if kind == "markdown"
    if @user.kb_media_edits.active.exists?(source_path: source_root, relative_path: relative_path)
      return render_error("An edit for this file is already in progress.", status: :conflict)
    end

    replacement = replacement_upload(absolute)
    return if performed?
    if replacement_required?(kind, absolute) && replacement.blank?
      return render_error("Choose or create the edited replacement before saving.")
    end

    edit = @user.kb_media_edits.create!(
      source_index: source_index,
      source_path: source_root,
      relative_path: relative_path,
      media_kind: kind,
      operations: operation_params.to_h,
      status: "pending"
    )
    edit.replacement_file.attach(replacement) if replacement.present?
    KbMediaEditRunnerJob.perform_later(edit.id)

    render json: {
      id: edit.id,
      status: edit.status,
      status_url: kb_media_edit_path(edit),
      file_url: kb_file_path(src: source_index, file: relative_path)
    }, status: :accepted
  rescue ActiveRecord::RecordNotUnique
    render_error("An edit for this file is already in progress.", status: :conflict)
  rescue ActiveRecord::RecordInvalid => error
    render_error(error.record.errors.full_messages.to_sentence)
  end

  def show
    edit = @user.kb_media_edits.find(params[:id])
    render json: {
      id: edit.id,
      status: edit.status,
      error: edit.error,
      revision_path: edit.revision_path,
      file_url: kb_file_path(src: edit.source_index, file: edit.relative_path)
    }
  end

  private

  def replacement_upload(absolute)
    upload = params[:rendered_file] || params[:replacement_file]
    if upload.blank? && params[:source_content].present? && %w[.html .htm].include?(File.extname(absolute).downcase)
      upload = {
        io: StringIO.new(params[:source_content].to_s),
        filename: File.basename(absolute),
        content_type: "text/html"
      }
    end
    return if upload.blank?

    size = upload.respond_to?(:size) ? upload.size : upload.fetch(:io).size
    if size > MAX_REPLACEMENT_BYTES
      render_error("Edited files must be smaller than 1 GB.", status: :content_too_large)
      return
    end
    upload
  end

  def replacement_required?(kind, absolute)
    return true if %w[image long_doc generic].include?(kind)
    return true if kind == "embed" && !%w[.html .htm].include?(File.extname(absolute).downcase)

    false
  end

  def operation_params
    permitted = params.fetch(:operations, {}).permit(
      :trim_start, :trim_end, :speed, :volume, :fade_in, :fade_out,
      :rotate, :flip_horizontal, :flip_vertical, :mute, :normalize, :mono,
      :brightness, :contrast, :saturation, :grayscale, :crop_aspect, :resolution,
      :page_sequence, :pdf_rotation, :pdf_quality, :client_recipe
    )
    permitted[:client_recipe] = permitted[:client_recipe].to_s.first(100_000) if permitted[:client_recipe].present?
    permitted
  end

  def safe_file(source_root, relative_path)
    return if relative_path.blank?

    absolute = File.expand_path(File.join(source_root, relative_path))
    return unless absolute.start_with?("#{source_root}/") && File.file?(absolute)

    current = source_root
    relative_path.split("/").each do |segment|
      current = File.join(current, segment)
      return if File.symlink?(current)
    end
    absolute
  end

  def render_error(message, status: :unprocessable_content)
    render json: { error: message }, status: status
  end
end
