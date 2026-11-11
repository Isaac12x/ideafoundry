require "application_system_test_case"
require "cgi"

# Artifacts use inline JavaScript inside an opaque sandbox. Their nested srcdoc
# frames need to inherit the script policy while staying isolated from the app.
class KbArtifactRuntimeSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-artifact-runtime-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    nested = CGI.escapeHTML('<!doctype html><html><body>Nested<script>document.body.dataset.nestedRan="yes"</script></body></html>')
    File.write(File.join(@kb_dir, "artifact.html"), <<~HTML)
      <!doctype html>
      <html><head><meta name="idea-capture-artifacts" content="1"></head>
      <body><h1>Artifact</h1>
        <script>
          document.body.dataset.scriptRan = "yes";
          try { parent.document.body.dataset.parentAccessible = "yes"; }
          catch (_) { document.body.dataset.parentBlocked = "yes"; }
        </script>
        <iframe sandbox="allow-scripts" srcdoc="#{nested}"></iframe>
      </body></html>
    HTML
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "marked artifact script and nested srcdoc run without app origin access" do
    visit kb_file_path(src: 0, file: "artifact.html")

    assert_selector "iframe.kb-embed[sandbox='allow-scripts']"
    within_frame(find("iframe.kb-embed")) do
      assert_selector "body[data-script-ran='yes'][data-parent-blocked='yes']"
      within_frame(find("iframe")) do
        assert_selector "body[data-nested-ran='yes']"
        assert_text "Nested"
      end
    end

    assert_nil page.evaluate_script("document.body.dataset.parentAccessible")
  end

  test "raw artifact response runs scripts with an opaque origin" do
    visit kb_path
    page.execute_script("document.cookie = 'artifact-sandbox-probe=secret; path=/'")
    visit kb_raw_path(src: 0, file: "artifact.html")

    assert_selector "body[data-script-ran='yes']"
    access = page.evaluate_script(<<~JS)
      (() => {
        let cookie;
        let storage;
        try { cookie = document.cookie.includes("artifact-sandbox-probe") ? "readable" : "empty"; }
        catch (_) { cookie = "blocked"; }
        try { localStorage.setItem("artifact-sandbox-probe", "secret"); storage = "readable"; }
        catch (_) { storage = "blocked"; }
        return { cookie, storage };
      })()
    JS
    assert_includes [ "empty", "blocked" ], access["cookie"]
    assert_equal "blocked", access["storage"]
  end
end
