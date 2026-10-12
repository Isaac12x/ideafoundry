require "test_helper"

class IdeaShowMediaTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first
    @idea = @user.ideas.create!(title: "Media page", state: :idea_new)
  end

  test "detail page renders cards, dropzone, viewer modal and pdf page-one preview" do
    @idea.attachments.attach(io: file_fixture("sample.pdf").open, filename: "spec.pdf",
                             content_type: "application/pdf")
    @idea.attachments.attach(io: StringIO.new("Chapter One\nThe opening lines of the memo.\n"),
                             filename: "memo.txt", content_type: "text/plain")
    doc = @idea.attachments_attachments.find { |a| a.filename.to_s == "memo.txt" }
    doc.update!(ocr_status: "complete", ocr_text: "Chapter One\nThe opening lines of the memo.")

    pdf_att = @idea.attachments_attachments.find { |a| a.filename.to_s == "spec.pdf" }
    assert pdf_att.previewable?, "PDF should be previewable (poppler present?)"
    assert pdf_att.thumbnail_source, "PDF should yield a thumbnail source"
    assert_equal "Chapter One\nThe opening lines of the memo.", doc.text_peek

    get idea_url(@idea)
    assert_response :success

    assert_select "article.attachment-card", 2
    assert_select "[data-attachment-list='document']"
    assert_select "dialog.attachment-viewer-modal"
    assert_select "[data-dropzone-upload-url-value*='variant=card']"
    assert_select ".attachment-card__peek", text: /Chapter One/
    # PDF card must point at a rendered preview image, not a generic icon.
    assert_select "img.attachment-card__thumb"
    refute_match(/target="_blank"/, css_select(".attachment-card").to_s)
  end
end
