require "application_system_test_case"

# Real Chrome, real key presses: locking covers the page in the same task as the trigger, before any request,
# and the server really is locked afterwards. Unlocks with a genuine authenticator code.
class ImmediateLockSystemTest < ApplicationSystemTestCase
  setup do
    skip "ffmpeg unavailable" unless system("ffmpeg -version", out: File::NULL, err: File::NULL)
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @secret = AuthenticatorApp.generate_secret
    @kb_dir = Rails.root.join("tmp", "kb-lock-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    File.write(File.join(@kb_dir, "note.md"), "# Secret heading\n\nconfidential body")
    system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=d=60:s=160x90:r=10", "-c:v", "libx264", "-pix_fmt", "yuv420p",
           "-movflags", "+faststart", File.join(@kb_dir, "v.mp4"), exception: true)
    @user.update!(settings: (@user.settings || {}).merge(
      "authenticator_app" => { "enabled" => true, "secret" => @secret },
      "kb" => { "folders" => [ @kb_dir ], "hide_native" => true }
    ))
    page.driver.browser.manage.window.resize_to(1280, 900)
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def unlock!(target, settle: true)
    visit target
    if page.has_selector?("#authenticator_code", wait: 3)
      begin
        find("#authenticator_code").send_keys(AuthenticatorApp.code(@secret), :enter)
      rescue Selenium::WebDriver::Error::UnknownError # node swapped by the navigation we just caused
        sleep 0.3
      end
      begin
        assert_no_selector "#authenticator_code", wait: 10
      rescue Selenium::WebDriver::Error::UnknownError # same race while the page is swapping
        sleep 0.3
        assert_no_selector "#authenticator_code", wait: 10
      end
    end
    sleep 1 if settle # lets every lazily imported controller connect; the early-key tests below pass settle: false
  end

  # Records, inside the page and in the same task as the trigger, whether the cover/paused state/fetch order holds.
  def instrument(trigger_selector_or_key)
    page.execute_script(<<~JS)
      window.__lock = { fetchesBeforeCover: 0, snapshots: [], removed: 0 };
      sessionStorage.removeItem("__t0"); sessionStorage.removeItem("__lockLog");
      const persist = () => sessionStorage.setItem("__lockLog", JSON.stringify(window.__lock)); // survives the navigation to the lock page
      const snap = (why) => {
        const c = document.getElementById("typing-lock-cover");
        const s = c && getComputedStyle(c), r = c && c.getBoundingClientRect();
        const v = document.querySelector("video");
        window.__lock.snapshots.push({ why, cover: !!c, bg: s && s.backgroundColor, opacity: s && s.opacity,
          full: !!c && r.width >= innerWidth && r.height >= innerHeight,
          top: !!c && document.elementFromPoint(innerWidth / 2, innerHeight / 2) === c,
          paused: v ? v.paused : null, t: performance.now() });
        persist();
      };
      const realFetch = window.fetch;
      window.fetch = function (...a) {
        if (!document.getElementById("typing-lock-cover")) { window.__lock.fetchesBeforeCover += 1; persist(); }
        if (window.__blockLock && String(a[0]).includes("/typing-lock/lock")) return Promise.reject(new TypeError("blocked"));
        return realFetch.apply(this, a);
      };
      // Registered after the controller's own capture listener, so it runs later in the same dispatch.
      const mark = (e) => { sessionStorage.setItem("__t0", String(Date.now())); snap(e.type); };
      document.addEventListener("keydown", (e) => { if (e.ctrlKey && e.key === "l") mark(e) }, true);
      document.addEventListener("submit", (e) => mark(e));

      new MutationObserver((muts) => muts.forEach((m) => m.removedNodes.forEach((n) => { if (n.id === "typing-lock-cover") { window.__lock.removed += 1; persist(); } })))
        .observe(document.documentElement, { childList: true });
    JS
  end

  def lock_log
    Timeout.timeout(10) do
      loop do
        raw = begin
          page.evaluate_script(%(sessionStorage.getItem("__lockLog")))
        rescue Selenium::WebDriver::Error::WebDriverError # mid-navigation
          nil
        end
        return JSON.parse(raw) if raw
        sleep 0.05
      end
    end
  end

  def assert_covered_at_trigger(log, label)
    first = log["snapshots"].first or flunk("#{label}: trigger never observed")
    assert first["cover"], "#{label}: no cover in the same task as the trigger"
    assert_equal "rgb(11, 11, 15)", first["bg"], "#{label}: cover not opaque"
    assert_equal "1", first["opacity"]
    assert first["full"] && first["top"], "#{label}: cover does not fill and top the viewport"
    assert_equal 0, log["fetchesBeforeCover"], "#{label}: a request was made before the cover existed"
    assert first["paused"], "#{label}: video still playing under the cover" unless first["paused"].nil?
  end

  def assert_locked_page_and_server(label)
    assert_selector "#authenticator_code", wait: 10
    probe = page.evaluate_script(<<~JS)
      (async () => { const r = await fetch("/knowledge-base", { redirect: "manual", credentials: "same-origin" }); return [r.type, r.status]; })()
    JS
    assert_equal "opaqueredirect", probe.first, "#{label}: server still serves app pages after the lock (#{probe})"
    elapsed = page.evaluate_script(%(Date.now() - Number(sessionStorage.getItem("__t0"))))
    puts "LOCK-TIMING #{label}: trigger -> lock page #{elapsed}ms"
  end

  test "Ctrl+L from a text input covers at once and locks the server" do
    unlock!(new_idea_path)
    input = first("input[type=text]:not([readonly]), input[name*=title]", minimum: 1)
    input.click
    instrument(:key)
    input.send_keys("abc", [ :control, "l" ])
    log = lock_log
    assert_covered_at_trigger(log, "input")
    assert_equal 0, log["removed"]
    assert_locked_page_and_server("input shortcut")
  end

  test "Ctrl+L from the markdown editor textarea" do
    unlock!(kb_edit_path(src: 0, file: "note.md"))
    ta = find("form.kb-editor textarea")
    ta.click
    instrument(:key)
    ta.send_keys("typed ", [ :control, "l" ])
    log = lock_log
    assert_covered_at_trigger(log, "textarea")
    assert_locked_page_and_server("textarea shortcut")
  end

  test "Ctrl+L while a video plays pauses it under the cover" do
    unlock!(kb_path(src: 0, file: "v.mp4"))
    start_video
    instrument(:key)
    press_lock
    log = lock_log
    assert_covered_at_trigger(log, "video")
    assert_locked_page_and_server("video shortcut")
  end

  test "the lock button covers at once too" do
    unlock!(kb_path(src: 0, file: "v.mp4"))
    start_video
    instrument(:click)
    find(".nav-lock-button").click
    log = lock_log
    assert_covered_at_trigger(log, "button")
    assert_locked_page_and_server("button")
  end

  test "a blocked lock request keeps the cover up and still ends locked" do
    unlock!(new_idea_path)
    instrument(:key)
    page.execute_script("window.__blockLock = true")
    press_lock
    sleep 0.8 # inside the retry window: every attempt fails
    assert page.evaluate_script("!!document.getElementById('typing-lock-cover')"), "cover came off after the request failed"
    assert_equal 0, lock_log["removed"]
    assert_selector "#authenticator_code", wait: 10 # falls back to a plain form post
  end

  test "truly offline: the cover stays, says so quietly, shows no workspace text, and the lock lands when back online" do
    unlock!(kb_path(src: 0, file: "note.md"))
    assert_text "confidential body"
    page.driver.browser.network_conditions = { offline: true, latency: 0, download_throughput: 0, upload_throughput: 0 }
    begin
      press_lock
      assert_selector "#typing-lock-cover", text: "Locked. Offline, retrying", visible: :all, wait: 10
      assert_equal "Locked. Offline, retrying", page.evaluate_script(%(document.getElementById("typing-lock-cover").textContent))
      assert_equal "rgb(11, 11, 15)", page.evaluate_script(%(getComputedStyle(document.getElementById("typing-lock-cover")).backgroundColor))
    ensure
      page.driver.browser.network_conditions = { offline: false, latency: 0, download_throughput: -1, upload_throughput: -1 }
    end
    assert_selector "#authenticator_code", wait: 25
  end

  test "browser back after locking does not reveal the page, and unlocking leaves no stale cover" do
    unlock!(kb_path(src: 0, file: "note.md"))
    assert_text "confidential body"
    visit new_idea_path
    instrument(:key)
    press_lock
    assert_selector "#authenticator_code", wait: 10
    page.go_back
    sleep 1.5
    assert_no_text "confidential body"
    assert page.has_selector?("#authenticator_code") || page.has_selector?("#typing-lock-cover"),
           "back showed neither the lock page nor a cover (url #{current_url})"
    visit new_idea_path
    code = AuthenticatorApp.code(@secret)
    find("#authenticator_code").send_keys(code, :enter) if page.has_selector?("#authenticator_code", wait: 3)
    assert_no_selector "#authenticator_code", wait: 10
    assert_no_selector "#typing-lock-cover"
    find("input[type=text]:not([readonly])", match: :first).send_keys("works")
    assert_equal "works", find("input[type=text]:not([readonly])", match: :first).value
    assert_equal 0, page.evaluate_script("document.querySelectorAll('#typing-lock-cover').length")
  end

  test "a key pressed the moment the page has loaded locks, with no settling time and no retry" do
    unlock!(new_idea_path, settle: false)
    page.driver.browser.action.key_down(:control).send_keys("l").key_up(:control).perform # exactly one real press
    assert_selector "#authenticator_code", wait: 10
  end

  test "the same holds right after a Turbo navigation" do
    unlock!(kb_path(src: 0, file: "note.md"))
    page.execute_script("Turbo.visit(arguments[0])", new_idea_path)
    assert_selector "input[type=text]:not([readonly])", wait: 10
    page.driver.browser.action.key_down(:control).send_keys("l").key_up(:control).perform
    assert_selector "#authenticator_code", wait: 10
  end

  test "locking while a Turbo visit is in flight covers the page and ends locked, never on the destination" do
    unlock!(kb_path(src: 0, file: "note.md"))
    instrument(:key)
    # Hold the visit's response open so the lock lands in the middle of the navigation.
    page.execute_script(<<~JS)
      const realFetch = window.fetch; window.__release = null;
      window.fetch = function (input, ...rest) {
        if (String(input).includes("/ideas/new")) return new Promise((resolve) => { window.__release = () => resolve(realFetch.call(window, input, ...rest)); });
        return realFetch.call(this, input, ...rest);
      };
      Turbo.visit("/ideas/new");
    JS
    press_lock
    assert page.evaluate_script("!!document.getElementById('typing-lock-cover')") || page.has_selector?("#authenticator_code", wait: 0)
    page.execute_script("window.__release && window.__release()") rescue nil # the late response must not be rendered
    assert_selector "#authenticator_code", wait: 10
    assert_no_current_path new_idea_path
  end

  test "Ctrl+S never locks, from any page" do
    unlock!(new_idea_path)
    page.driver.browser.action.key_down(:control).send_keys("s").key_up(:control).perform
    sleep 0.5
    assert_no_selector "#typing-lock-cover", visible: :all
    assert_no_selector "#authenticator_code"
  end

  test "no CSP or console errors from the cover" do
    unlock!(new_idea_path)
    page.driver.browser.logs.get(:browser)
    press_lock
    assert_selector "#authenticator_code", wait: 10
    severe = page.driver.browser.logs.get(:browser).select { |l| l.level == "SEVERE" }.map(&:message)
    assert_empty severe.grep(/Content Security Policy|Refused to apply inline style/i), severe.join("\n")
  end

  # Under a loaded machine the lazily imported controller can connect late; a key before that is simply not heard.
  def press_lock
    5.times do
      page.driver.browser.action.key_down(:control).send_keys("l").key_up(:control).perform
      return if page.has_selector?("#typing-lock-cover, #authenticator_code", wait: 2, visible: :all)
    end
  end

  def start_video
    assert_selector "video", wait: 10
    page.execute_script("const v = document.querySelector('video'); v.muted = true; v.play()")
    wait_until_playing
  end

  def wait_until_playing
    Timeout.timeout(8) { sleep 0.05 until page.evaluate_script("!document.querySelector('video').paused && document.querySelector('video').currentTime > 0.1") }
  end
end
