class KbMediaEditRunnerJob < ApplicationJob
  queue_as :default

  def perform(edit_id)
    edit = KbMediaEdit.find_by(id: edit_id)
    return unless edit&.pending?

    source = available_source(edit)
    return fail_edit!(edit, "The selected knowledge-base source is no longer available.") unless source

    absolute = safe_file(source, edit.relative_path)
    return fail_edit!(edit, "The source file is no longer available.") unless absolute

    edit.update!(status: "running", started_at: Time.current)
    result = with_replacement(edit) do |replacement_path|
      Kb::MediaEditProcessor.new(
        path: absolute,
        source_root: source,
        operations: edit.operations || {},
        replacement_path: replacement_path
      ).call
    end

    edit.update!(result.merge(status: "done", finished_at: Time.current))
    ActivityLog.record!(
      user: edit.user,
      actor: "user",
      action: "updated",
      trackable_name: edit.relative_path,
      details: {
        "kind" => "knowledge_base_media",
        "kb_media_edit_id" => edit.id,
        "source_path" => edit.source_path,
        "relative_path" => edit.relative_path,
        "operations" => edit.operations,
        "original_sha256" => edit.original_sha256,
        "result_sha256" => edit.result_sha256,
        "revision_path" => edit.revision_path
      }
    )
  rescue StandardError => error
    Rails.logger.error("KbMediaEditRunnerJob #{edit_id}: #{error.class}: #{error.message}")
    fail_edit!(edit, error.message)
  end

  private

  def available_source(edit)
    allowed = KbSource.list(edit.user).map { |source| File.expand_path(source[:path]) }
    source = File.expand_path(edit.source_path)
    allowed.include?(source) && Dir.exist?(source) ? source : nil
  end

  def safe_file(source, relative_path)
    absolute = File.expand_path(File.join(source, relative_path))
    return nil unless absolute.start_with?("#{source}/") && File.file?(absolute)

    current = source
    relative_path.split("/").each do |segment|
      current = File.join(current, segment)
      return nil if File.symlink?(current)
    end
    absolute
  end

  def with_replacement(edit)
    return yield(nil) unless edit.replacement_file.attached?

    edit.replacement_file.blob.open { |file| yield(file.path) }
  end

  def fail_edit!(edit, message)
    return unless edit

    edit.update!(status: "failed", error: message.to_s.first(4_000), finished_at: Time.current)
  end
end
