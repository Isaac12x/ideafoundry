require "test_helper"

class IdeaKbLinksHelperTest < ActionView::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb = Rails.root.join("tmp", "kb-idea-links-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb ], "hide_native" => true }))
    @idea = @user.ideas.create!(title: "Linked")
  end

  teardown do
    @user.update!(settings: @original_settings)
    @idea.destroy
    FileUtils.rm_rf(@kb)
  end

  test "a file inside a locked project is locked, not missing" do
    project = Kb::Project.create!(base: @kb, parent_rel: "", name: "Vault")
    File.write(File.join(project.abs, "a.md"), "x")
    @idea.kb_links.create!(source_path: File.expand_path(@kb), relative_path: "Vault/a.md")
    File.delete(File.join(project.abs, "a.md"))
    Kb::ProjectLock.write_stub(project.abs, { "private" => true, "locked" => true, "archive" => "Vault.7z" })

    entry = idea_kb_link_entries(@idea.reload, @user).first
    assert_not entry[:missing]
    assert_equal "Vault", entry[:locked].rel
    assert_equal kb_path(src: 0, project: "Vault"), idea_kb_link_href(entry)
  end

  test "a file that is really gone is still missing" do
    @idea.kb_links.create!(source_path: File.expand_path(@kb), relative_path: "nope.md")
    assert idea_kb_link_entries(@idea.reload, @user).first[:missing]
  end
end
