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
end
