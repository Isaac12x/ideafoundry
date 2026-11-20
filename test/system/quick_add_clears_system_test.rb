require "application_system_test_case"

# Criterion: after adding a maxim / problem / fact (or an idea's competitor / tool) the field is empty again,
# and on the KB forms it holds focus so the next one can be typed straight away.
class QuickAddClearsSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first
    @original_settings = @user.settings.deep_dup
  end

  teardown { @user.update!(settings: @original_settings) }

  def active_field_name = page.evaluate_script("document.activeElement && (document.activeElement.name || document.activeElement.id)")

  def add_and_check(tab, form, field, text, list)
    visit kb_path(tab: tab)
    within("##{form}") { find(field).set(text) }
    assert_equal text, find("##{form} #{field}").value
    within("##{form}") { find("input[type=submit]").click }
    assert_selector "##{list} .kb-fact-card, ##{list} .kb-maxim-card", text: text
    assert_equal "", find("##{form} #{field}").value
    assert_selector "##{form} #{field}:focus"
  end

  test "maxim field is empty and focused after adding" do
    add_and_check("maxims", "maxim_form", "textarea", "Keep the constraint visible #{SecureRandom.hex(3)}", "maxims-list")
  end

  test "fact field is empty and focused after adding" do
    add_and_check("facts", "fact_form", "textarea", "Landfills fill with leather #{SecureRandom.hex(3)}", "facts-list")
  end

  test "problem fields are empty and the first is focused after adding" do
    title = "Slippery tracks #{SecureRandom.hex(3)}"
    visit kb_path(tab: "problems")
    within("#problem_form") do
      find("input[name='problem[title]']").set(title)
      find("textarea[name='problem[need]']").set("Drivers cannot stop")
      find("input[type=submit]").click
    end
    assert_selector "#problems-list .kb-fact-card", text: title
    assert_equal "", find("#problem_form input[name='problem[title]']").value
    assert_equal "", find("#problem_form textarea[name='problem[need]']").value
    assert_selector "#problem_form input[name='problem[title]']:focus"
  end

  test "typed text does not come back after a reload (draft restored only when unsent)" do
    visit kb_path(tab: "maxims")
    text = "Sent maxim #{SecureRandom.hex(3)}"
    find("#maxim_form textarea").set(text)
    find("#maxim_form input[type=submit]").click
    assert_selector "#maxims-list .kb-maxim-card", text: text
    sleep 0.5 # past the draft-keeper debounce
    visit kb_path(tab: "maxims")
    assert_equal "", find("#maxim_form textarea").value
    assert_no_selector ".draft-note"
  end

  test "competitor and tool quick-add forms clear after adding" do
    idea = ideas(:one)
    idea.update!(user: @user)
    @user.update!(settings: (@user.settings || {}).merge("idea_tabs" => { "competitor" => true, "tool" => true }))
    visit idea_path(idea)
    find("button[data-tab-name='general']").click

    { "competitor" => "Rival #{SecureRandom.hex(3)}", "tool" => "Hammer #{SecureRandom.hex(3)}" }.each do |kind, name|
      panel = "#idea_entries_tab_#{idea.id}_#{kind}"
      find("#{panel} .idea-entries-add__toggle", visible: :all).click
      within(panel) do
        fill_in placeholder: /name/i, with: name, match: :first
        find("input[type=submit]").click
      end
      assert_selector "#idea_entries_list_#{idea.id}_#{kind}", text: name
      assert_equal "", find("#{panel} input[name='idea_entry[name]']", visible: :all).value
    end
  end

  test "a maxim chip link opens the tab, scrolls to the card and highlights it" do
    maxim = @user.maxims.create!(body: "Chip target #{SecureRandom.hex(3)}")
    30.times { |i| @user.maxims.create!(body: "Filler #{i}") }
    visit kb_path(tab: "maxims", anchor: "maxim_#{maxim.id}")
    assert_selector "#maxim_#{maxim.id}.is-ref-target"
    assert_selector ".tab-button.active", text: "Maxims"
    assert page.evaluate_script("(() => { const r = document.getElementById('maxim_#{maxim.id}').getBoundingClientRect(); return r.top >= 0 && r.bottom <= window.innerHeight })()")
  end

  test "?tab=problems opens the problems tab" do
    visit kb_path(tab: "problems")
    assert_selector ".tab-button.active", text: "Problems"
  end
end
