class KbFsJobRunnerJob < ApplicationJob
  queue_as :default

  def perform(kb_fs_job_id)
    task = KbFsJob.find_by(id: kb_fs_job_id)
    return unless task&.pending?

    base = available_source_path(task)
    return fail_task!(task, "The selected knowledge-base source is no longer available.", base: nil) unless base

    task.update!(status: "running", started_at: Time.current)
    transcribe_voice!(task) if task.voice_message.attached?

    context = Kb::ContextReader.new(
      base: base,
      relative_path: task.context_path,
      kind: task.context_kind
    ).call
    result = LocalAgent::PromptClient.new.call(instruction: task.request_text, context: context)
    result_path = write_result(base, task.target_dir, task, result, error: false)

    task.update!(status: "done", result_path: result_path, finished_at: Time.current)
    record_event(task, "kb_job_completed", "Completed KB job", result_path: result_path)
  rescue StandardError => error
    Rails.logger.error("KbFsJobRunnerJob #{kb_fs_job_id}: #{error.class}: #{error.message}")
    fail_task!(task, error.message, base: base)
  end

  private

  def available_source_path(task)
    allowed_paths = KbSource.list(task.user).map { |source| File.expand_path(source[:path]) }
    base = File.expand_path(task.source_path)
    allowed_paths.include?(base) && Dir.exist?(base) ? base : nil
  end

  def transcribe_voice!(task)
    blob = task.voice_message.blob
    blob.open do |file|
      result = FluidVoiceClient.transcribe(
        audio: file,
        filename: blob.filename.to_s,
        content_type: blob.content_type
      )
      transcript = result[:transcript].to_s.strip
      raise FluidVoiceClient::Error, "FluidVoice returned an empty transcript" if transcript.blank?

      task.update!(transcript: transcript)
    end
  end

  def write_result(base, target_dir, task, content, error:)
    parent = safe_directory(base, target_dir)
    raise ArgumentError, "The target folder is no longer available" unless parent

    results_dir = File.join(parent, "job_results")
    FileUtils.mkdir_p(results_dir)
    stem = task.prompt.to_s.parameterize.presence || "voice-request"
    stem = stem.first(56)
    suffix = error ? "-error" : ""
    path = unique_path(File.join(results_dir, "#{task.created_at.strftime('%Y%m%d-%H%M%S')}-#{stem}#{suffix}.md"))
    heading = error ? "KB job error" : "KB job result"
    File.write(path, "# #{heading}\n\n**Context:** `#{task.context_path}`\n\n**Request:** #{task.request_text}\n\n#{content}\n")
    path.delete_prefix("#{base}/")
  end

  def safe_directory(base, relative_dir)
    absolute = File.expand_path(File.join(base, relative_dir.to_s))
    return nil unless absolute.start_with?("#{base}/") || absolute == base
    return nil if symlink_in_path?(base, absolute)

    File.directory?(absolute) ? absolute : nil
  end

  def unique_path(path)
    return path unless File.exist?(path)

    directory = File.dirname(path)
    extension = File.extname(path)
    stem = File.basename(path, extension)
    number = 2
    number += 1 while File.exist?(File.join(directory, "#{stem}-#{number}#{extension}"))
    File.join(directory, "#{stem}-#{number}#{extension}")
  end

  def symlink_in_path?(base, absolute)
    current = base
    absolute.delete_prefix(base).delete_prefix("/").split("/").any? do |segment|
      current = File.join(current, segment)
      File.symlink?(current)
    end
  end

  def fail_task!(task, message, base:)
    return unless task

    result_path = base ? write_result(base, task.target_dir, task, "The job could not finish.\n\n#{message}", error: true) : nil
    task.update!(status: "failed", error: message.to_s, result_path: result_path, finished_at: Time.current)
    record_event(task, "kb_job_failed", "KB job failed", error: message, result_path: result_path)
  rescue StandardError => nested_error
    task.update_columns(status: "failed", error: "#{message} (could not write error result: #{nested_error.message})", finished_at: Time.current)
    Kb::TreeBroadcaster.call(task.user)
  end

  def record_event(task, event_type, summary, payload)
    task.user.agent_events.create!(
      event_type: event_type,
      summary: summary,
      payload: payload.merge(
        "kb_fs_job_id" => task.id,
        "source_path" => task.source_path,
        "context_path" => task.context_path
      )
    )
  end
end
