require "test_helper"

class Kb::TranscriptTest < ActiveSupport::TestCase
  test "sidecar sits beside the media with a .vtt extension" do
    assert_equal "/kb/a/talk.vtt", Kb::Transcript.sidecar("/kb/a/talk.mp4")
    assert_equal "/kb/a.b/clip.final.vtt", Kb::Transcript.sidecar("/kb/a.b/clip.final.mov")
  end

  test "parses whisper-style VTT with MM:SS.mmm stamps" do
    vtt = "WEBVTT\n\n00:00.000 --> 00:02.880\nHello world.\n\n00:03.000 --> 01:05.500\nSecond line.\n"
    assert_equal [ { start: 0.0, end: 2.88, text: "Hello world." }, { start: 3.0, end: 65.5, text: "Second line." } ],
                 Kb::Transcript.from_vtt(vtt)
  end

  test "downloaded captions become cues ending where the next starts" do
    cues = Kb::Transcript.from_captions("00:00 - intro\n01:30 - middle\nnot a cue\n")
    assert_equal [ [ 0, 90, "intro" ], [ 90, 180, "middle" ] ], cues.map { |c| [ c[:start], c[:end], c[:text] ] }
    assert_empty Kb::Transcript.from_captions(nil)
  end

  test "claim is exclusive until released" do
    abs = "/kb/#{SecureRandom.hex(4)}.mp4"
    assert Kb::Transcript.claim!(abs)
    assert_not Kb::Transcript.claim!(abs)
    assert Kb::Transcript.running?(abs)
  ensure
    FileUtils.rm_rf(Kb::Transcript.state_dir)
  end

  test "whisper writes the sidecar for dropped-in media" do
    skip "whisper or ffmpeg unavailable" unless Kb::Transcript.available? && system("ffmpeg -version", out: File::NULL, err: File::NULL)
    skip "tiny whisper model not cached" unless File.exist?(File.expand_path("~/.cache/whisper/tiny.pt"))
    skip "no say" unless system("say -v '?'", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      aiff = File.join(dir, "t.aiff")
      mp3 = File.join(dir, "talk.mp3")
      system("say", "-o", aiff, "Hello world. This is a transcription test.", exception: true)
      system("ffmpeg", "-y", "-loglevel", "error", "-i", aiff, mp3, exception: true)

      with_env("WHISPER_MODEL" => "tiny") { Kb::Transcript.transcribe!(mp3) }

      assert File.file?(File.join(dir, "talk.vtt"))
      assert_match(/hello world/i, Kb::Transcript.cues(mp3).map { |c| c[:text] }.join(" "))
    end
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
