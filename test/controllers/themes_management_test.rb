require "test_helper"

class ThemesManagementTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @a = @user.themes.create!(name: "Alpha #{SecureRandom.hex(3)}", color: Theme::PALETTE.first)
    @b = @user.themes.create!(name: "Beta #{SecureRandom.hex(3)}")
  end

  test "settings page lists themes with swatches and delete" do
    @user.ideas.create!(title: "Tagged", themes: [ @a ])
    get settings_themes_path
    assert_response :success
    assert_select "#theme_#{@a.id} input[name='theme[name]'][value='#{@a.name}']"
    assert_select "#theme_#{@a.id} .theme-swatch input[type=radio]", Theme::PALETTE.size
    assert_select "#theme_#{@a.id} input[type=radio][checked]", 1
    assert_select "#theme_#{@a.id} form[data-turbo-confirm]"
    assert_select "#theme_#{@a.id} .theme-manage__count", text: "1 idea"
  end

  test "rename and recolor" do
    patch theme_path(@a), params: { theme: { name: "Shipping", color: Theme::PALETTE.last } }
    assert_redirected_to ideas_path
    assert_equal [ "Shipping", Theme::PALETTE.last ], @a.reload.values_at(:name, :color)
  end

  test "rename onto an existing name is rejected" do
    patch theme_path(@a), params: { theme: { name: @b.name.upcase } }
    assert_not_equal @b.name.upcase, @a.reload.name
  end

  test "delete keeps the ideas" do
    idea = @user.ideas.create!(title: "Keep me", themes: [ @a ])
    delete theme_path(@a)
    assert_nil Theme.find_by(id: @a.id)
    assert Idea.exists?(idea.id)
  end

  test "grouped index shows color marks, serif headings data and the no-theme group last" do
    @user.ideas.create!(title: "Colored", themes: [ @a ])
    @user.ideas.create!(title: "Plain")
    get ideas_path(group: "theme")
    assert_select ".theme-group[style*='#{Theme::PALETTE.first}'] .theme-group__name", text: @a.name
    assert_select ".theme-group--none .theme-group__name", text: "No theme"
    assert_select ".theme-group:last-of-type.theme-group--none"
    assert_select ".idea-card .theme-badge[style*='#{Theme::PALETTE.first}']", text: @a.name
  end

  test "grouped index teaches when no theme exists" do
    @user.themes.destroy_all
    @user.ideas.create!(title: "Loose")
    get ideas_path(group: "theme")
    assert_select ".theme-hint", text: /Add a theme to an idea to group it here/
  end
end
