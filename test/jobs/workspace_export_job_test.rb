require "test_helper"
require "tmpdir"

class WorkspaceExportJobTest < ActiveJob::TestCase
  test "exports every user owned active storage file" do
    user = users(:one)
    idea = ideas(:one)

    idea.attachments.attach(io: StringIO.new("idea attachment"), filename: "idea.txt", content_type: "text/plain")

    drawing = idea.drawings.create!(title: "Sketch", content: { "elements" => [] })
    drawing.rendered_png.attach(io: StringIO.new("png"), filename: "sketch.png", content_type: "image/png")

    build_item = user.build_items.create!(title: "Build item")
    build_item.images.attach(io: StringIO.new("image"), filename: "build.png", content_type: "image/png")

    submission = user.submissions.create!(title: "Submission", body: "Incoming")
    submission.files.attach(io: StringIO.new("submission file"), filename: "submission.txt", content_type: "text/plain")

    other_user_item = users(:two).build_items.create!(title: "Other user item")
    other_user_item.images.attach(io: StringIO.new("other"), filename: "other.png", content_type: "image/png")

    exported_keys = [
      idea.attachments.last.blob.key,
      drawing.rendered_png.blob.key,
      build_item.images.last.blob.key,
      submission.files.last.blob.key
    ]
    other_key = other_user_item.images.last.blob.key

    Dir.mktmpdir do |dir|
      temp_dir = Pathname.new(dir)
      job = WorkspaceExportJob.new

      job.send(:export_files, user, temp_dir)

      exported_keys.each do |key|
        assert File.exist?(temp_dir.join("files", key[0..1], key)), "expected #{key} to be exported"
      end

      refute File.exist?(temp_dir.join("files", other_key[0..1], other_key))
      assert_equal exported_keys.size, job.send(:count_user_attachments, user)
    end
  end

  test "fails the export on tar failure without damaging an existing archive" do
    Dir.mktmpdir do |dir|
      job = WorkspaceExportJob.new
      user = users(:one)
      user.update!(settings: user.settings.merge("backup" => { "auto_cleanup" => "true", "max_backups" => "1", "retention_days" => "1" }))
      existing_archive = File.join(dir, "previous_good_backup.tar.gz")
      File.write(existing_archive, "previous good backup")
      previous_backup = user.export_jobs.create!(
        kind: :backup,
        status: :completed,
        progress: 100,
        file_path: existing_archive,
        created_at: 2.days.ago
      )
      export_job = user.export_jobs.create!(kind: :backup)
      output_dir = File.join(dir, "exports", "backup")

      Rails.stub(:root, Pathname.new(dir)) do
        job.stub(:export_database_data, nil) do
          job.stub(:export_files, nil) do
            job.stub(:create_manifest, nil) do
              job.stub(:create_readme, nil) do
                job.stub(:system, ->(_command, _flag, archive_path, *_args) { File.write(archive_path, "partial archive"); false }) do
                  job.perform(export_job)
                end
              end
            end
          end
        end
      end

      assert export_job.reload.failed?
      assert_equal "previous good backup", File.read(existing_archive)
      assert user.export_jobs.exists?(previous_backup.id)
      assert_empty Dir.glob(File.join(output_dir, "*.tar.gz"))
      refute export_job.file_exists?
    end
  end

  test "completes an attached idea backup before applying retention" do
    user = users(:one)
    idea = ideas(:one)
    idea.attachments.attach(io: StringIO.new("idea attachment payload"), filename: "idea.txt", content_type: "text/plain")
    blob_key = idea.attachments.last.blob.key
    user.update!(settings: user.settings.merge("backup" => { "auto_cleanup" => "true", "max_backups" => "1", "retention_days" => "365" }))

    Dir.mktmpdir do |dir|
      previous_file = File.join(dir, "previous.tar.gz")
      File.write(previous_file, "previous backup")
      previous_backup = user.export_jobs.create!(kind: :backup, status: :completed, progress: 100, file_path: previous_file)
      manual_export = user.export_jobs.create!(kind: :export, status: :completed, progress: 100, file_path: previous_file)
      unshared_file = File.join(dir, "unshared.tar.gz")
      File.write(unshared_file, "unshared old backup")
      unshared_backup = user.export_jobs.create!(kind: :backup, status: :completed, progress: 100, file_path: unshared_file)
      newer_missing_backup = user.export_jobs.create!(
        kind: :backup,
        status: :completed,
        progress: 100,
        file_path: File.join(dir, "missing.tar.gz"),
        created_at: 1.day.from_now
      )
      export_job = user.export_jobs.create!(kind: :backup)

      Rails.stub(:root, Pathname.new(dir)) do
        WorkspaceExportJob.new.perform(export_job)
      end

      assert export_job.reload.completed?
      refute user.export_jobs.exists?(previous_backup.id)
      refute user.export_jobs.exists?(unshared_backup.id)
      refute user.export_jobs.exists?(newer_missing_backup.id)
      assert File.exist?(unshared_file) == false
      assert_equal "previous backup", File.read(previous_file)
      assert user.export_jobs.exists?(manual_export.id)

      extract_dir = File.join(dir, "extracted")
      FileUtils.mkdir_p(extract_dir)
      assert system("tar", "-xzf", export_job.file_path, "-C", extract_dir)
      data = JSON.parse(File.read(File.join(extract_dir, "data.json")))
      attachment = data.fetch("ideas").find { |item| item.fetch("id") == idea.id }.fetch("attachments").compact.first
      assert_equal blob_key, attachment.fetch("key")
      assert File.file?(File.join(extract_dir, "files", blob_key[0..1], blob_key))
    ensure
      FileUtils.rm_f(export_job.file_path) if export_job&.file_path
    end
  end
end
