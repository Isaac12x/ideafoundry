require "application_system_test_case"

# Covers the parts of the import flow that only exist in the browser: the
# dropzone hands the file to the form, which auto-submits into the mapping screen.
class LicensorImportSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "li-sys@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Foldable Solar Kettle", for_licensing: true)
  end

  test "uploading a sheet lands on the mapping screen with columns guessed" do
    visit new_idea_licensor_import_path(@idea)
    assert_text "Drop a CSV or Excel file"

    attach_file("file", Rails.root.join("test/fixtures/files/licensors.csv"), make_visible: true)

    assert_text "Map licensors.csv"
    assert_selector ".import-grid td", text: "Acme Publishing"
    assert_equal "company", find("select[name='mapping[0]']").value
    assert_equal "contact_email", find("select[name='mapping[2]']").value

    click_button "Import 5 rows"

    assert_text "3 licensors imported, 1 skipped as duplicates, and 1 email dropped as unreadable."
    assert_selector ".crm-card", text: "Acme Publishing"
  end

  test "the licensing flag can be flipped from the idea page" do
    @idea.update!(for_licensing: false)
    visit idea_path(@idea)

    find(".idea-actions-menu__trigger").click
    click_button "Track for licensing"

    # Wait for the reload before reading the record back.
    assert_text "Tracking this idea for licensing."
    assert_text "Potential Licensors"
    assert @idea.reload.for_licensing?
  end
end
