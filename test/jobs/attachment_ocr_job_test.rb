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

    ocr_result = {
      "text" => "Part A\nPart B",
      "html" => "<div>Part A</div><div>Part B</div>",
      "parts" => ["Part A", "Part B"],
      "pages" => [
        {
          "page" => 1,
          "html" => "<div>Part A</div><div>Part B</div>",
          "blocks" => [{ "label" => "Text", "html" => "<div>Part A</div>" }]
        }
      ]
    }

    OcrClient.stub :extract, ocr_result do
      AttachmentOcrJob.perform_now(attachment.id)
    end

    attachment.reload
    assert_equal "complete", attachment.ocr_status
    assert_equal "Part A\nPart B", attachment.ocr_text
    assert_equal ["Part A", "Part B"], attachment.ocr_metadata["parts"]
    assert_equal "<div>Part A</div><div>Part B</div>", attachment.ocr_metadata["html"]
    assert_equal "<div>Part A</div><div>Part B</div>", attachment.ocr_metadata["pages"].first["html"]
  end
end
