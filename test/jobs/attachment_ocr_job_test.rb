require "test_helper"

class AttachmentOcrJobTest < ActiveJob::TestCase
  test "stores extracted text returned by local OCR service" do
    idea = User.first.ideas.create!(title: "Scanned receipt", state: :idea_new)
    idea.attachments.attach(
      io: StringIO.new("fake image"),
      filename: "receipt.png",
      content_type: "image/png"
    )
    attachment = idea.attachments.last

    OcrClient.stub :extract, { "text" => "Part A\nPart B", "parts" => ["Part A", "Part B"] } do
      AttachmentOcrJob.perform_now(attachment.id)
    end

    attachment.reload
    assert_equal "complete", attachment.ocr_status
    assert_equal "Part A\nPart B", attachment.ocr_text
    assert_equal ["Part A", "Part B"], attachment.ocr_metadata["parts"]
  end
end
