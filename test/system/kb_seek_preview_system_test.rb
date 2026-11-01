require "application_system_test_case"

# Real headless Chrome, real mouse: the seek bar shows a decoded frame under the cursor (hover and drag),
# the main video only seeks on release, and click / keyboard seeking still work.
class KbSeekPreviewSystemTest < ApplicationSystemTestCase
  DURATION = 10

  setup do
    skip "ffmpeg unavailable" unless system("ffmpeg -version", out: File::NULL, err: File::NULL)
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-seek-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    # Hue rotates a full turn over the clip, so every second has its own colour; the second clip is grey-ish.
    make_video("a.mp4", "color=c=red:s=320x180:d=#{DURATION}:r=10,hue=h=t*36")
    make_video("b.mp4", "color=c=0x30a030:s=240x180:d=#{DURATION}:r=10,hue=s=0")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    page.driver.browser.manage.window.resize_to(1280, 900)
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def make_video(name, source)
    system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", source, "-c:v", "libx264", "-pix_fmt", "yuv420p",
           "-g", "5", "-movflags", "+faststart", File.join(@kb_dir, name), exception: true)
  end

  def open_video(name)
    visit kb_path(src: 0, file: name)
    assert_selector "video.kb-video-player", wait: 10
    wait_for { page.evaluate_script("document.querySelector('video.kb-video-player').duration") .to_f > 1 }
  end

  def wait_for(timeout = 8)
    Timeout.timeout(timeout) { sleep 0.05 until yield }
  rescue Timeout::Error
    flunk "timed out waiting for condition"
  end

  def seek_input = find("input.kb-vplayer__seek")

  # Real mouse move to a fraction of the seek bar (offset is from the element centre).
  def mouse_to(fraction, chain = nil)
    el = seek_input
    x = ((fraction - 0.5) * el.native.size.width).round
    (chain || page.driver.browser.action).move_to(el.native, x, 0)
  end

  def thumb_state
    page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector(".kb-vplayer__thumb"), c = t.querySelector("canvas");
        const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
        let r = 0, g = 0, b = 0, n = 0;
        for (let i = 0; i < d.length; i += 4) { r += d[i]; g += d[i + 1]; b += d[i + 2]; n++; }
        const box = t.getBoundingClientRect(), p = document.querySelector(".kb-vplayer").getBoundingClientRect();
        return { hidden: t.hidden, stamp: t.querySelector("span").textContent, mean: [r / n, g / n, b / n],
                 left: box.left - p.left, right: p.right - box.right, w: box.width };
      })()
    JS
  end

  def bright?(state) = state["mean"].max > 40

  def main_time = page.evaluate_script("document.querySelector('video.kb-video-player').currentTime").to_f

  def stamp_seconds(state) = state["stamp"].split(":").map(&:to_i).inject { |m, s| m * 60 + s }

  test "hover shows a decoded frame at the pointer, differing by time, clamped at both ends, no console errors" do
    open_video("a.mp4")
    mouse_to(0.25).perform
    wait_for { !thumb_state["hidden"] && bright?(thumb_state) }
    first = thumb_state
    assert_in_delta 2.5, stamp_seconds(first), 1.0
    mouse_to(0.75).perform
    wait_for { s = thumb_state; bright?(s) && (s["mean"].zip(first["mean"]).sum { |x, y| (x - y).abs } > 30) }
    assert_in_delta 7.5, stamp_seconds(thumb_state), 1.0
    assert_in_delta 0.0, main_time, 0.01, "hover must not move the main video"

    mouse_to(0.003).perform
    s = thumb_state
    assert_operator s["left"], :>=, -0.5, "thumbnail overflows the left edge"
    assert_equal "0:00", s["stamp"]
    mouse_to(0.997).perform
    s = thumb_state
    assert_operator s["right"], :>=, -0.5, "thumbnail overflows the right edge"
    assert_operator stamp_seconds(s), :>=, 9

    severe = page.driver.browser.logs.get(:browser).select { |l| l.level == "SEVERE" }.map(&:message)
    assert_empty severe.grep(/Content Security Policy|tainted|Refused|SecurityError/i), severe.join("\n")
  end

  # In-page recorder: samples the thumbnail every 50ms and logs the main video's seeking events and the pointerup.
  def record_drag
    page.execute_script(<<~JS)
      window.__log = { samples: [], seeks: [], up: null };
      const v = document.querySelector("video.kb-video-player"), t = document.querySelector(".kb-vplayer__thumb"), c = t.querySelector("canvas");
      v.addEventListener("seeking", () => window.__log.seeks.push({ at: performance.now(), to: v.currentTime }));
      document.addEventListener("pointerup", () => { window.__log.up ||= performance.now() }, true);
      setInterval(() => {
        if (t.hidden) return;
        const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
        window.__log.samples.push({ stamp: t.querySelector("span").textContent, r: d[0], g: d[1], b: d[2], mid: [d[(c.width * (c.height >> 1) + (c.width >> 1)) * 4], d[(c.width * (c.height >> 1) + (c.width >> 1)) * 4 + 1], d[(c.width * (c.height >> 1) + (c.width >> 1)) * 4 + 2]] });
      }, 50);
    JS
  end

  test "dragging updates the preview live and the main video seeks only on release" do
    open_video("a.mp4")
    record_drag
    page.driver.browser.action.move_to(seek_input.native, ((0.2 - 0.5) * seek_input.native.size.width).round, 0)
      .click_and_hold.pause(duration: 0.8)
      .move_to(seek_input.native, ((0.6 - 0.5) * seek_input.native.size.width).round, 0).pause(duration: 0.8)
      .release.perform
    wait_for { (main_time - 6.0).abs < 1.0 }
    log = page.evaluate_script("window.__log")
    stamps = log["samples"].map { |x| x["stamp"] }.uniq
    assert (stamps & %w[0:01 0:02]).any?, "preview never showed the 20% position: #{stamps}"
    assert (stamps & %w[0:05 0:06]).any?, "preview never showed the 60% position: #{stamps}"
    assert_in_delta stamp_seconds("stamp" => stamps.last), main_time, 1.5, "commit differs from the last previewed time"
    mids = log["samples"].map { |x| x["mid"] }.uniq
    assert mids.any? { |m| m.max > 40 }, "preview frames were blank during the drag"
    assert_operator mids.size, :>, 1, "preview frame never changed during the drag"
    during = log["seeks"].select { |x| x["at"] < log["up"] }
    assert_empty during, "main video seeked while dragging: #{during}"
    assert_operator log["seeks"].size, :>=, 1, "release must commit the seek"
  end

  test "dragging past the bar ends keeps following and clamps" do
    open_video("a.mp4")
    record_drag
    el = seek_input
    page.driver.browser.action.move_to(el.native, 0, 0).click_and_hold.pause(duration: 0.3)
      .move_to(el.native, el.native.size.width / 2 + 120, 0).pause(duration: 0.8).release.perform
    log = page.evaluate_script("window.__log")
    assert_operator log["samples"].last["stamp"], :>=, "0:09", "preview stopped following outside the bar"
    wait_for { main_time > 8.5 }
  end

  test "click and keyboard seeking still work" do
    open_video("a.mp4")
    mouse_to(0.8).click.perform
    wait_for { (main_time - 8.0).abs < 1.0 }
    seek_input.send_keys(:arrow_left)
    before = main_time
    wait_for { main_time < 8.0 }
    assert_operator main_time, :<, before + 0.01
    find(".kb-vplayer").click # focus inside the player, then the player-level seek key
    page.driver.browser.action.send_keys(:arrow_right).perform
    wait_for { main_time > before - 0.5 }
  end

  test "switching to another video shows that video's frames, not the previous cache" do
    open_video("a.mp4")
    mouse_to(0.5).perform
    wait_for { bright?(thumb_state) }
    open_video("b.mp4")
    mouse_to(0.5).perform
    wait_for { s = thumb_state; !s["hidden"] && bright?(s) }
    mean = thumb_state["mean"]
    assert_in_delta mean[0], mean[2], 25, "frame is still the previous (red-hue) video's: #{mean.inspect}"
  end

  test "preview works in fullscreen" do
    open_video("a.mp4")
    find("[data-kb-video-controls-target=fullscreen]").click
    unless (page.evaluate_script("!!document.fullscreenElement") rescue false)
      sleep 0.5
      skip "headless Chrome did not enter fullscreen" unless page.evaluate_script("!!document.fullscreenElement")
    end
    mouse_to(0.5).perform
    wait_for { bright?(thumb_state) }
    assert page.evaluate_script("document.fullscreenElement.contains(document.querySelector('.kb-vplayer__thumb'))")
  end
end
