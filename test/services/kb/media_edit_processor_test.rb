require "test_helper"

class KbMediaEditProcessorTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp", "kb-media-processor-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@root)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "replacement preserves the original in hidden revision history" do
    source = File.join(@root, "image.png")
    replacement = File.join(@root, "replacement.bin")
    File.binwrite(source, "before")
    File.binwrite(replacement, "after")

    result = Kb::MediaEditProcessor.new(
      path: source,
      source_root: @root,
      operations: {},
      replacement_path: replacement
    ).call

    assert_equal "after", File.binread(source)
    assert_equal Digest::SHA256.hexdigest("before"), result[:original_sha256]
    assert_equal Digest::SHA256.hexdigest("after"), result[:result_sha256]
    assert_equal "before", File.binread(File.join(@root, result[:revision_path]))
    assert_match(%r{\A\.ideafoundry-history/image\.png/}, result[:revision_path])
  end

  test "video recipe becomes a shell-safe ffmpeg command" do
    source = File.join(@root, "clip.mp4")
    File.binwrite(source, "video")
    commands = []
    runner = lambda do |*command|
      commands << command
      if command.first == "ffprobe"
        ['{"format":{"duration":"12.0"},"streams":[{"codec_type":"video","width":1920,"height":1080},{"codec_type":"audio","channels":2}]}', "", success_status]
      else
        File.binwrite(command.last, "rendered-video")
        ["", "", success_status]
      end
    end

    Kb::MediaEditProcessor.new(
      path: source,
      source_root: @root,
      operations: {
        trim_start: "1", trim_end: "9", speed: "1.25", crop_aspect: "1:1",
        rotate: "90", brightness: "0.2", contrast: "1.1", saturation: "0.8",
        volume: "1.2", fade_in: "0.5", fade_out: "1", resolution: "720"
      },
      runner: runner
    ).call

    ffmpeg = commands.find { |command| command.first == "ffmpeg" }
    assert_includes ffmpeg, "-ss"
    assert_includes ffmpeg, "-vf"
    video_filters = ffmpeg[ffmpeg.index("-vf") + 1]
    assert_includes video_filters, "crop="
    assert_includes video_filters, "transpose=1"
    assert_includes video_filters, "eq=brightness=0.2"
    assert_includes video_filters, "setpts=PTS/1.25"
    assert_includes video_filters, "scale=-2:720"
    audio_filters = ffmpeg[ffmpeg.index("-af") + 1]
    assert_includes audio_filters, "atempo=1.25"
    assert_includes audio_filters, "volume=1.2"
    assert_equal "rendered-video", File.binread(source)
  end

  test "invalid pdf page expressions fail before invoking a local command" do
    source = File.join(@root, "paper.pdf")
    File.binwrite(source, "%PDF")
    called = false
    runner = ->(*) { called = true }

    error = assert_raises(Kb::MediaEditProcessor::Error) do
      Kb::MediaEditProcessor.new(
        path: source,
        source_root: @root,
        operations: { page_sequence: "1-3; rm -rf /" },
        runner: runner
      ).call
    end

    assert_includes error.message, "Page sequence"
    assert_not called
    assert_equal "%PDF", File.binread(source)
  end

  private

  def success_status
    Object.new.tap { |status| status.define_singleton_method(:success?) { true } }
  end
end
