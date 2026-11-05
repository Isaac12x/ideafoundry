require "application_system_test_case"

# Real Chrome: clicking another video in the tree re-points the player already on screen (no waiting for the frame),
# the frame that follows keeps that very <video> element, and everything bound to the file follows the click.
class KbVideoSwitchSystemTest < ApplicationSystemTestCase
  setup do
    skip "ffmpeg unavailable" unless system("ffmpeg -version", out: File::NULL, err: File::NULL)
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-switch-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    make_video("a.mp4", "faststart")
    make_video("b.mp4", "faststart")
    make_video("c.mp4", nil) # index (moov) at the end of the file, as yt-dlp style downloads can be
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    page.driver.browser.manage.window.resize_to(1280, 900)
  end

  teardown do
    # The browser outlives the test: put back the window size and the storage this test changed.
    page.driver.browser.manage.window.resize_to(1400, 1400)
    begin
      page.execute_script("localStorage.clear()")
    rescue Selenium::WebDriver::Error::WebDriverError
      nil # not on an app page
    end
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def make_video(name, movflags)
    args = [ "ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=d=30:s=160x90:r=10", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "10" ]
    args += [ "-movflags", "+#{movflags}" ] if movflags
    system(*args, File.join(@kb_dir, name), exception: true)
  end

  def open_video(name)
    visit kb_path(src: 0, file: name)
    assert_selector "video.kb-video-player", wait: 10
    wait_for { js("document.querySelector('video.kb-video-player').readyState") >= 2 }
  end

  def js(script) = page.evaluate_script(script)

  def wait_for(timeout = 10)
    Timeout.timeout(timeout) { sleep 0.05 until yield }
  rescue Timeout::Error
    flunk "timed out waiting for condition"
  end

  def play!
    page.execute_script("const v = document.querySelector('video.kb-video-player'); v.muted = true; v.play()")
    wait_for { js("!document.querySelector('video.kb-video-player').paused && document.querySelector('video.kb-video-player').currentTime > 0.3") }
  end

  def click_video(name) = find(".kb-file-link", text: name, exact_text: true).click

  def mark_player = page.execute_script("window.__player = document.querySelector('video.kb-video-player')")

  # The frame for `name` has fully rendered: its panels carry that file.
  def assert_frame_for(name)
    assert_selector ".kb-video-view[data-kb-transcript-url-value*='#{name}']", wait: 10
  end

  test "the live player is re-pointed at once, then kept when the frame arrives" do
    open_video("a.mp4")
    play!
    mark_player
    click_video("b.mp4")
    # Before (or without waiting for) the frame: the same element already plays the new file.
    wait_for { js("document.querySelector('video.kb-video-player').currentSrc.includes('b.mp4')") }
    assert_frame_for("b.mp4")
    assert js("document.querySelector('video.kb-video-player') === window.__player"), "the frame replaced the playing <video> (rebuffer)"
    assert_equal "0:b.mp4", js("document.querySelector('video.kb-video-player').dataset.kbResumeKeyValue")
    assert_equal 1, js("document.querySelectorAll('video.kb-video-player').length")
    wait_for { js("!document.querySelector('video.kb-video-player').paused && document.querySelector('video.kb-video-player').currentTime > 0.2") }
    assert_selector ".kb-file-row.is-active", text: "b.mp4"
    # Controls, seek preview and transcript panel still drive this element.
    page.execute_script("document.querySelector('[data-kb-video-controls-target=play]').click()") # the bar shows on hover only
    wait_for { js("document.querySelector('video.kb-video-player').paused") }
    assert_selector "[data-controller~=kb-transcript]"
  end

  test "autoplay state follows the old player" do
    open_video("a.mp4") # paused
    click_video("b.mp4")
    assert_frame_for("b.mp4")
    sleep 0.6
    assert js("document.querySelector('video.kb-video-player').paused"), "a paused player started playing on its own"
    play!
    click_video("a.mp4")
    assert_frame_for("a.mp4")
    wait_for { js("!document.querySelector('video.kb-video-player').paused && document.querySelector('video.kb-video-player').currentTime > 0.2") }
  end

  test "the resume position stays with its own file" do
    visit kb_path
    page.execute_script("localStorage.setItem('kb-resume:0:b.mp4', '12')")
    open_video("a.mp4")
    play!
    sleep 1.2
    click_video("b.mp4")
    assert_frame_for("b.mp4")
    wait_for { js("document.querySelector('video.kb-video-player').currentTime") >= 11.5 }
    assert js("parseFloat(localStorage.getItem('kb-resume:0:a.mp4') || '0')") > 0.5, "a.mp4 lost where it was left"
    assert_in_delta 12, js("parseFloat(localStorage.getItem('kb-resume:0:b.mp4'))"), 2
  end

  test "rapid switching ends on the last clicked and never clobbers a saved position" do
    visit kb_path
    page.execute_script("localStorage.setItem('kb-resume:0:a.mp4', '9')")
    open_video("c.mp4")
    play!
    %w[a.mp4 b.mp4 c.mp4 a.mp4 b.mp4].each { |name| click_video(name) }
    assert_frame_for("b.mp4")
    sleep 0.8
    assert_includes js("document.querySelector('video.kb-video-player').currentSrc"), "b.mp4"
    assert_equal "0:b.mp4", js("document.querySelector('video.kb-video-player').dataset.kbResumeKeyValue")
    assert_equal 1, js("document.querySelectorAll('.kb-file-row.is-active').length")
    assert_selector ".kb-file-row.is-active", text: "b.mp4"
    assert_operator js("parseFloat(localStorage.getItem('kb-resume:0:a.mp4'))"), :>=, 8.9, "a quick switch overwrote a.mp4's saved position"
    assert_equal 1, js("document.querySelectorAll('video.kb-video-player').length")
  end

  test "a video with its index at the end still switches and plays" do
    open_video("a.mp4")
    play!
    click_video("c.mp4")
    assert_frame_for("c.mp4")
    wait_for { js("!document.querySelector('video.kb-video-player').paused && document.querySelector('video.kb-video-player').currentTime > 0.2") }
  end

  test "opening a new download leaves the tree in place" do
    KbDownload.create!(user: @user, source_index: 0, url: "https://example.com/b", status: "done", source_path: File.expand_path(@kb_dir), dir: "", filename: "b.mp4")
    visit kb_path
    assert_selector ".kb-file-row.is-new", text: "b.mp4"
    page.execute_script("window.__tree = document.getElementById('kb-sidebar-tree')")
    click_video("b.mp4")
    assert_frame_for("b.mp4")
    wait_for { KbDownload.where(filename: "b.mp4").pick(:opened_at) }
    assert js("document.getElementById('kb-sidebar-tree') === window.__tree"), "the tree was re-rendered"
    assert_no_selector ".kb-file-row.is-new"
  end
end
