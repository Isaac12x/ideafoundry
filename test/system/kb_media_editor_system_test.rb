require "application_system_test_case"

class KbMediaEditorSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-media-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    FileUtils.cp(Rails.root.join("public", "icon.png"), File.join(@kb_dir, "evidence.png"))
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [@kb_dir], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "media tools stay dormant in view mode and activate after Edit" do
    visit kb_path(src: 0, file: "evidence.png")

    assert_no_selector ".kb-media-editor"
    assert_selector ".kb-image-preview"
    click_link "Edit"

    assert_selector "form.kb-media-editor"
    assert_selector "canvas[data-kb-media-editor-target=canvas]"
    assert_button "Crop"
    assert_button "Draw"
    assert_button "Save edit"
    assert page.evaluate_script("document.querySelector('[data-kb-media-editor-target=canvas]').width") > 0

    click_link "Cancel"
    assert_no_selector ".kb-media-editor"
    assert_selector ".kb-image-preview"
  end
end
