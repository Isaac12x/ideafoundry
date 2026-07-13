require "test_helper"

class KbMediaEditRunnerJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-media-job-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    File.binwrite(File.join(@kb_dir, "artifact.xyz"), "original-artifact")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [@kb_dir], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "atomically replaces an opaque file and records a checksummed human revision" do
    edit = build_edit
    edit.replacement_file.attach(io: StringIO.new("edited-artifact"), filename: "artifact.xyz", content_type: "application/octet-stream")

    assert_difference -> { ActivityLog.where(user: @user, action: "updated").count }, 1 do
      KbMediaEditRunnerJob.perform_now(edit.id)
    end

    edit.reload
    assert edit.done?
    assert_equal "edited-artifact", File.binread(File.join(@kb_dir, "artifact.xyz"))
    assert_equal Digest::SHA256.hexdigest("original-artifact"), edit.original_sha256
    assert_equal Digest::SHA256.hexdigest("edited-artifact"), edit.result_sha256
    assert_equal "original-artifact", File.binread(File.join(@kb_dir, edit.revision_path))

    activity = ActivityLog.where(user: @user, action: "updated").last
    assert_equal "user", activity.actor
    assert_equal edit.id, activity.details["kb_media_edit_id"]
    assert_equal edit.revision_path, activity.details["revision_path"]
  end

  test "fails safely when the source leaves the configured vault" do
    edit = build_edit
    edit.replacement_file.attach(io: StringIO.new("edited"), filename: "artifact.xyz", content_type: "application/octet-stream")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [], "hide_native" => true }))

    KbMediaEditRunnerJob.perform_now(edit.id)

    assert edit.reload.failed?
    assert_includes edit.error, "no longer available"
    assert_equal "original-artifact", File.binread(File.join(@kb_dir, "artifact.xyz"))
  end

  private

  def build_edit
    @user.kb_media_edits.create!(
      source_index: 0,
      source_path: @kb_dir,
      relative_path: "artifact.xyz",
      media_kind: "generic",
      operations: {},
      status: "pending"
    )
  end
end
