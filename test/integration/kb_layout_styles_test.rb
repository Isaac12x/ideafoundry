require "test_helper"

class KbLayoutStylesTest < ActiveSupport::TestCase
  test "kb and facts tabs share the full-height page layout" do
    view = Rails.root.join("app/views/kb/index.html.erb").read
    css = Rails.root.join("app/assets/stylesheets/kb.css").read

    assert_includes view, '<div class="kb-shell" data-controller="tabs" data-tabs-default-tab-value="kb">'
    assert_includes view, 'data-tab-panel="facts" class="kb-panel-full kb-facts-panel-full hidden"'

    body_rule = css_rule(css, "body.kb-page")
    assert_includes body_rule, "min-height: 100dvh;"
    assert_includes body_rule, "overflow: hidden;"

    app_main_rule = css_rule(css, "body.kb-page .app-main")
    assert_includes app_main_rule, "height: calc(100dvh - 60px);"
    assert_includes app_main_rule, "min-height: calc(100dvh - 60px);"
    assert_includes app_main_rule, "width: 100%;"
    assert_includes app_main_rule, "display: flex;"
    assert_includes app_main_rule, "flex-direction: column;"

    shell_rule = css_rule(css, ".kb-shell")
    assert_includes shell_rule, "display: flex;"
    assert_includes shell_rule, "flex: 1;"
    assert_includes shell_rule, "flex-direction: column;"
    assert_includes shell_rule, "height: 100%;"

    hidden_panel_rule = css_rule(css, ".kb-panel-full.hidden")
    assert_includes hidden_panel_rule, "display: none;"

    facts_panel_rule = css_rule(css, ".kb-facts-panel-full")
    assert_includes facts_panel_rule, "align-items: center;"
    assert_includes facts_panel_rule, "overflow-y: auto;"

    facts_container_rule = css_rule(css, ".kb-facts-container")
    assert_includes facts_container_rule, "max-width: 820px;"
    assert_includes facts_container_rule, "padding: 2.5rem 2rem;"
  end

  private

  def css_rule(css, selector)
    css[/#{Regexp.escape(selector)}\s*\{(?<body>[^}]*)\}/m, :body].to_s
  end
end
