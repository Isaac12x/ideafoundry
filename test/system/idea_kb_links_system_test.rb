require "application_system_test_case"

class IdeaKbLinksSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-links-system-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "Ferment"))
    File.write(File.join(@kb_dir, "Ferment", ".kb-project.yml"), "id: p1\ngoal: Survival at 4C\nstatus: active\nprivate: true\n")
    File.write(File.join(@kb_dir, "protocol.md"), "# Protocol\n")
    FileUtils.mkdir_p(File.join(@kb_dir, "papers", "strains"))
    File.write(File.join(@kb_dir, "papers", "strains", "plantarum.md"), "# L. plantarum\n")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [@kb_dir], "hide_native" => true }))
    @idea = @user.ideas.create!(title: "Probiotic jar")
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "link a project and a file from the idea page" do
    visit idea_path(@idea)
    input = find(".idea-kb-links__input")
    input.send_keys("ferm")
    assert_selector "[role=option]", text: "Ferment"
    input.send_keys(:down, :enter)
    assert_selector ".idea-kb-links__item", text: "Ferment"
    assert_text "private"

    input = find(".idea-kb-links__input")
    input.send_keys("protocol")
    find("[role=option]", text: "protocol.md").click
    assert_selector ".idea-kb-links__item", text: "protocol.md"
    assert_equal 2, @idea.kb_links.count

    find(".idea-kb-links__item", text: "Ferment").find("a", text: "Ferment").click
    assert_selector "#kb-content .kbp-title", text: "Ferment"
    assert_text "Probiotic jar" # backlink from the project page
  end

  test "a linked folder opens expanded and revealed in the KB tree" do
    @idea.kb_links.create!(source_path: File.expand_path(@kb_dir), relative_path: "papers/strains", entry_type: "dir")
    visit kb_path
    find(".kb-dir-header", text: "papers").find(".kb-dir-toggle").click # leave it collapsed
    assert_no_selector ".kb-file-row", text: "plantarum.md"

    visit idea_path(@idea)
    click_link "strains"
    assert_selector ".kb-dir-header.is-revealed", text: "strains"
    assert_selector ".kb-file-row", text: "plantarum.md"
  end
end
