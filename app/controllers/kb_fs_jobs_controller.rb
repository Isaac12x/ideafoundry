class KbFsJobsController < ApplicationController
  MAX_VOICE_BYTES = 25.megabytes

  before_action :set_user

  def create
    source_index = params[:src].to_i
    source = KbSource.list(@user)[source_index]
    return render_error("Knowledge-base source is not available.") unless source

    base = File.expand_path(source[:path])
    context_path = KbEntryPreference.normalize_relative_path(params[:path])
    context_kind = params[:context_kind].to_s
    absolute = safe_context(base, context_path, context_kind)
    return render_error("The selected file or folder is no longer available.") unless absolute

    voice_message = params[:voice_message]
    prompt = params[:prompt].to_s.strip
    return render_error("Type a request or record a voice message.") if prompt.blank? && voice_message.blank?
    return render_error("Voice messages must be audio files.") if voice_message.present? && !voice_message.content_type.to_s.start_with?("audio/")
    return render_error("Voice messages must be smaller than 25 MB.") if voice_message.present? && voice_message.size > MAX_VOICE_BYTES

    target_dir = context_kind == "folder" ? context_path : File.dirname(context_path)
    target_dir = "" if target_dir == "."
    task = KbFsJob.enqueue(
      user: @user,
      source_index: source_index,
      source_path: base,
      context_path: context_path,
      context_kind: context_kind,
      target_dir: target_dir,
      prompt: prompt,
      voice_message: voice_message
    )
    @user.agent_events.create!(
      event_type: "kb_job_queued",
      summary: "Queued KB job for #{context_path}",
      payload: { "kb_fs_job_id" => task.id, "source_path" => base, "context_path" => context_path }
    )

    render_tree(notice: "AI job queued. Its result will appear in job_results.")
  rescue ActiveRecord::RecordInvalid => error
    render_error(error.record.errors.full_messages.to_sentence)
  end

  private

  def safe_context(base, relative_path, kind)
    return nil unless %w[file folder].include?(kind)

    absolute = File.expand_path(File.join(base, relative_path))
    return nil unless absolute.start_with?("#{base}/")
    return nil if path_contains_symlink?(base, absolute)

    kind == "folder" ? (absolute if File.directory?(absolute)) : (absolute if File.file?(absolute))
  end

  def path_contains_symlink?(base, absolute)
    current = base
    absolute.delete_prefix(base).delete_prefix("/").split("/").any? do |segment|
      current = File.join(current, segment)
      File.symlink?(current)
    end
  end

  def render_error(message)
    flash.now[:alert] = message
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("flash", partial: "layouts/flash"), status: :unprocessable_content
      end
      format.json { render json: { error: message }, status: :unprocessable_content }
      format.html { redirect_to kb_path, alert: message }
    end
  end

  def render_tree(notice:)
    flash.now[:notice] = notice
    streams = [
      turbo_stream.update("flash", partial: "layouts/flash"),
      turbo_stream.replace(
        "kb-sidebar-tree",
        partial: "kb/tree",
        locals: {
          folders: Kb::TreeBuilder.new(@user).call,
          selected_file: params[:sel_file].presence,
          selected_folder_index: params[:sel_src].presence&.to_i
        }
      )
    ]
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.json { render json: { ok: true }, status: :accepted }
      format.html { redirect_to kb_path, notice: notice }
    end
  end
end
