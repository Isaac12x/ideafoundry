require "test_helper"

class Kb::ProjectLockTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PW = "correct horse".freeze

  setup do
    skip "7z not installed" unless Kb::ProjectLock.available?
    @base = Dir.mktmpdir
    @project = Kb::Project.create!(base: @base, parent_rel: "", name: "Secret", goal: "hidden goal")
    FileUtils.mkdir_p(File.join(@base, "Secret/sub"))
    File.write(File.join(@base, "Secret/notes.md"), "top secret")
    File.write(File.join(@base, "Secret/sub/deep.txt"), "deep")
    @id = @project.id
  end
  teardown do
    Kb::ProjectLock.wait_all
    Kb::ProjectLock::STATE.clear
    FileUtils.rm_rf(@base) if @base
  end

  def children = Dir.children(File.join(@base, "Secret")).sort

  test "lock leaves only archive and stub, unlock restores everything" do
    Kb::ProjectLock.lock!(@project, PW)
    assert_equal [ ".kb-project.yml", "Secret.7z" ], children
    locked = Kb::Project.at(@base, "Secret")
    assert locked.locked?
    assert Kb::Privacy.private?(@base, "Secret/Secret.7z")
    assert_no_match(/hidden goal/, File.read(File.join(@base, "Secret/.kb-project.yml")))
    assert_not_includes File.binread(File.join(@base, "Secret/Secret.7z")), "notes.md" # encrypted headers

    Kb::ProjectLock.unlock!(locked, PW)
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
    assert_equal "top secret", File.read(File.join(@base, "Secret/notes.md"))
    reopened = Kb::Project.at(@base, "Secret")
    assert_not reopened.locked?
    assert_equal "hidden goal", reopened.goal
    assert_equal @id, reopened.id
    assert Dir.children(@base).none? { |c| c.start_with?(".Secret.") }
  end

  test "wrong password changes nothing" do
    Kb::ProjectLock.lock!(@project, PW)
    before = children
    error = assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Secret"), "nope-nope") }
    assert_equal "Wrong password.", error.message
    assert_equal before, children
    assert Kb::Project.at(@base, "Secret").locked?
    assert Dir.children(@base).none? { |c| c.start_with?(".Secret.") }
  end

  test "failure keeps plaintext" do
    original = Kb::ProjectLock::SEVEN_ZIP
    Kb::ProjectLock.send(:remove_const, :SEVEN_ZIP)
    Kb::ProjectLock.const_set(:SEVEN_ZIP, "/usr/bin/false")
    begin
      Kb::ProjectLock.stub(:available?, true) do
        assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.lock!(@project, PW) }
      end
    ensure
      Kb::ProjectLock.send(:remove_const, :SEVEN_ZIP)
      Kb::ProjectLock.const_set(:SEVEN_ZIP, original)
    end
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
    assert_not Kb::Project.at(@base, "Secret").locked?
    assert Dir.children(@base).none? { |c| c.start_with?(".Secret.") }
  end

  test "rejects short or mismatched passwords" do
    assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.lock!(@project, "abc") }
    assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.lock!(@project, PW, "different") }
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
  end

  def user = (@user ||= User.first || User.create!(email: "test@example.com", name: "Test"))

  test "history, annotations, transcripts and digests leave the app on lock and return on unlock" do
    hist = File.join(@base, ".ideafoundry-history/Secret/notes.md")
    FileUtils.mkdir_p(hist)
    File.write(File.join(hist, "rev1.md"), "old plaintext")
    src = File.expand_path(@base)
    note = user.kb_annotations.create!(source_path: src, relative_path: "Secret/notes.md", quote: "top secret", start_offset: 0, end_offset: 3)
    other = user.kb_annotations.create!(source_path: src, relative_path: "Other/x.md", quote: "unrelated", start_offset: 0, end_offset: 3)
    dl = user.kb_downloads.create!(source_index: 0, source_path: src, dir: "Secret", url: "https://example.com/v", filename: "v.mp4",
                                   status: "done", transcript: "spoken secret")
    digest = MediaDigest.create!(user: user, kb_download: dl, pipeline: "transcript_v1", body: "digest secret")

    Kb::ProjectLock.lock!(@project, PW, user: user)

    assert_not File.exist?(File.join(@base, ".ideafoundry-history/Secret"))
    assert_not KbAnnotation.exists?(note.id)
    assert KbAnnotation.exists?(other.id)
    assert_nil dl.reload.transcript
    assert_not MediaDigest.exists?(digest.id)
    assert_equal [ ".kb-project.yml", "Secret.7z" ], children

    Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Secret"), PW, user: user)

    assert_equal "old plaintext", File.read(File.join(hist, "rev1.md"))
    assert_equal "top secret", KbAnnotation.find(note.id).quote
    assert_equal "spoken secret", dl.reload.transcript
    assert_equal "digest secret", MediaDigest.find(digest.id).body
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
  end

  test "a file written while 7z runs aborts the lock and nothing is deleted" do
    real = Kb::ProjectLock.method(:run!)
    late = File.join(@base, "Secret/late.md")
    racing = lambda do |pw, *args, **kw|
      File.write(late, "late") if args.first == "a"
      real.call(pw, *args, **kw)
    end
    Kb::ProjectLock.stub(:run!, racing) do
      error = assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.lock!(@project, PW) }
      assert_match(/changed while locking/, error.message)
    end
    assert_equal [ ".kb-project.yml", "late.md", "notes.md", "sub" ], children
    assert_equal "late", File.read(late)
    assert_not Kb::Project.at(@base, "Secret").locked?
  end

  test "remove_snapshot only deletes what was snapshotted and unchanged" do
    dir = File.join(@base, "Secret")
    snap = Kb::ProjectLock::Derived.snapshot(dir)
    File.write(File.join(dir, "new.md"), "new")
    File.write(File.join(dir, "sub/new.txt"), "new")
    File.write(File.join(dir, "notes.md"), "edited after snapshot")
    Kb::ProjectLock::Derived.remove_snapshot(dir, snap, except: [ ".kb-project.yml" ])
    assert_equal [ ".kb-project.yml", "new.md", "notes.md", "sub" ], children
    assert_equal [ "new.txt" ], Dir.children(File.join(dir, "sub"))
  end

  test "unlock keeps both when Finder added a same-named file while locked" do
    Kb::ProjectLock.lock!(@project, PW)
    File.write(File.join(@base, "Secret/notes.md"), "added while locked")
    FileUtils.mkdir_p(File.join(@base, "Secret/sub"))
    File.write(File.join(@base, "Secret/sub/other.txt"), "mine")

    Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Secret"), PW)

    assert_equal "added while locked", File.read(File.join(@base, "Secret/notes.md"))
    assert_equal "top secret", File.read(File.join(@base, "Secret/notes (locked copy).md"))
    assert_equal "mine", File.read(File.join(@base, "Secret/sub/other.txt"))
    assert_equal "deep", File.read(File.join(@base, "Secret/sub (locked copy)/deep.txt"))
    assert_not Kb::Project.at(@base, "Secret").locked?
  end

  test "start runs in the background, blocks the project meanwhile, and keeps the password out of the queue" do
    gate = Queue.new
    broadcasts = Concurrent::Array.new
    Kb::TreeBroadcaster.stub(:call, ->(u) { broadcasts << u }) do
      Kb::ProjectLock.stub(:lock!, ->(*_a, **_k) { gate.pop }) do
        assert_no_enqueued_jobs do
          Kb::ProjectLock.start(:lock, @project, PW, user: user)
          assert Kb::ProjectLock.busy_path?(File.join(@base, "Secret/notes.md"))
          assert Kb::ProjectLock.busy_path?(File.join(@base, "Secret"))
          assert Kb::ProjectLock.busy_path?(@base)
          assert_not Kb::ProjectLock.busy_path?(File.join(@base, "Elsewhere"))
          assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.start(:lock, @project, PW, user: user) }
          gate << 1
          Kb::ProjectLock.wait_all
        end
      end
    end
    assert_not Kb::ProjectLock.busy_path?(File.join(@base, "Secret"))
    assert_equal [ user ], broadcasts.to_a
  end

  test "a failed background run keeps the plaintext and reports the error once" do
    Kb::ProjectLock.stub(:lock!, ->(*_a, **_k) { raise Kb::ProjectLock::Error, "boom" }) do
      Kb::ProjectLock.start(:lock, @project, PW)
      Kb::ProjectLock.wait_all
    end
    assert_equal "boom", Kb::ProjectLock.take_error(@project.abs)
    assert_nil Kb::ProjectLock.take_error(@project.abs)
    assert_not Kb::ProjectLock.busy?(@project.abs)
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
  end

  test "wrong password is rejected before any background work starts" do
    Kb::ProjectLock.lock!(@project, PW)
    error = assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.start(:unlock, Kb::Project.at(@base, "Secret"), "nope-nope") }
    assert_equal "Wrong password.", error.message
    assert_not Kb::ProjectLock.busy?(File.join(@base, "Secret"))
  end

  def src = File.expand_path(@base)

  test "a DB row created between stash and archive aborts the lock and nothing is lost" do
    real = Kb::ProjectLock.method(:run!)
    late = nil
    racing = lambda do |pw, *args, **kw|
      late = user.kb_annotations.create!(source_path: src, relative_path: "Secret/notes.md", quote: "late", start_offset: 0, end_offset: 3) if args.first == "a"
      real.call(pw, *args, **kw)
    end
    Kb::ProjectLock.stub(:run!, racing) do
      error = assert_raises(Kb::ProjectLock::Error) { Kb::ProjectLock.lock!(@project, PW, user: user) }
      assert_equal "Changes happened while locking, try again.", error.message
    end
    assert KbAnnotation.exists?(late.id)
    assert_not Kb::Project.at(@base, "Secret").locked?
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
  end

  test "scrub only removes stashed rows" do
    a = user.kb_annotations.create!(source_path: src, relative_path: "Secret/notes.md", quote: "old", start_offset: 0, end_offset: 3)
    data = Kb::ProjectLock::Derived.collect(@project, user)
    newer = user.kb_annotations.create!(source_path: src, relative_path: "Secret/notes.md", quote: "newer", start_offset: 0, end_offset: 3)
    Kb::ProjectLock::Derived.scrub!(@project, user, data)
    assert_not KbAnnotation.exists?(a.id)
    assert KbAnnotation.exists?(newer.id)
  end

  test "active_work covers transcribing rows and running whisper" do
    assert_not Kb::ProjectLock::Derived.active_work?(user, @project)
    dl = user.kb_downloads.create!(source_index: 0, source_path: src, dir: "Secret", url: "https://e.com/v", filename: "v.mp4", status: "done", transcript_status: "transcribing")
    assert Kb::ProjectLock::Derived.active_work?(user, @project)
    dl.update!(transcript_status: "done")
    assert_not Kb::ProjectLock::Derived.active_work?(user, @project)
    media = File.join(@base, "Secret/a.mp3")
    File.binwrite(media, "x")
    FileUtils.mkdir_p(Kb::Transcript.state_dir)
    FileUtils.touch(Kb::Transcript.state_file(media, "lock"))
    assert Kb::ProjectLock::Derived.active_work?(user, @project)
  ensure
    FileUtils.rm_rf(Kb::Transcript.state_dir)
  end

  test "cached OCR text of the project's images is deleted on lock; old entries are evicted" do
    FileUtils.cp(Rails.root.join("test/fixtures/files/ocr_sample.png"), File.join(@base, "Secret/pic.png"))
    pic = File.join(src, "Secret/pic.png")
    FileUtils.mkdir_p(Kb::ImageOcr.cache_dir)
    keyed = Kb::ImageOcr.cache_dir.join("#{Kb::ImageOcr.key(pic)}.json")
    File.write(keyed, JSON.generate(lines: [], text: "SECRET OCR")) # legacy entry without a path
    pathed = Kb::ImageOcr.cache_dir.join("pathed.json")
    File.write(pathed, JSON.generate(lines: [], text: "SECRET OCR 2", path: File.join(src, "Secret/gone.png")))
    other = Kb::ImageOcr.cache_dir.join("other.json")
    File.write(other, JSON.generate(lines: [], text: "x", path: File.join(src, "Elsewhere/x.png")))

    Kb::ProjectLock.lock!(@project, PW, user: user)

    assert_not File.exist?(keyed)
    assert_not File.exist?(pathed)
    assert File.exist?(other)

    File.utime(40.days.ago.to_time, 40.days.ago.to_time, other)
    Kb::ImageOcr.evict!
    assert_not File.exist?(other)
  ensure
    FileUtils.rm_rf(Kb::ImageOcr.cache_dir)
  end

  test "fs-job text, reference lists and extraction errors are scrubbed and restored" do
    job = user.kb_fs_jobs.create!(source_index: 0, source_path: src, context_path: "Secret/notes.md", context_kind: "file", target_dir: "Secret",
                                  prompt: "SECRET PROMPT", transcript: "SECRET SPOKEN", status: "done")
    dl = user.kb_downloads.create!(source_index: 0, source_path: src, dir: "Secret", url: "https://e.com/p", filename: "p.pdf", status: "done",
                                   reference_list: [ { "url" => "https://secret.example" } ])
    ext = KnowledgeExtraction.create!(source_kind: KnowledgeExtraction::KB_FILE, kb_folder_index: 0, kb_path: File.join(src, "Secret/notes.md"), error: "SECRET ERR")

    Kb::ProjectLock.lock!(@project, PW, user: user)
    assert_nil job.reload.prompt
    assert_nil job.transcript
    assert_equal [], dl.reload.reference_list
    assert_nil ext.reload.error

    Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Secret"), PW, user: user)
    assert_equal [ "SECRET PROMPT", "SECRET SPOKEN" ], job.reload.values_at(:prompt, :transcript)
    assert_equal [ { "url" => "https://secret.example" } ], dl.reload.reference_list
    assert_equal "SECRET ERR", ext.reload.error
  end

  test "the history folder is removed entirely when empty" do
    hist = File.join(@base, ".ideafoundry-history/Secret/notes.md")
    FileUtils.mkdir_p(hist)
    File.write(File.join(hist, "r.md"), "old")
    Kb::ProjectLock.lock!(@project, PW, user: user)
    assert_not File.exist?(File.join(@base, ".ideafoundry-history"))
  end

  test "unlock survives a deleted download row and a failing DB section" do
    dl = user.kb_downloads.create!(source_index: 0, source_path: src, dir: "Secret", url: "https://e.com/v", filename: "v.mp4", status: "done", transcript: "spoken")
    MediaDigest.create!(user: user, kb_download: dl, pipeline: "transcript_v1", body: "digest")
    note = user.kb_annotations.create!(source_path: src, relative_path: "Secret/notes.md", quote: "q", start_offset: 0, end_offset: 3)
    Kb::ProjectLock.lock!(@project, PW, user: user)
    dl.destroy!

    Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Secret"), PW, user: user)
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
    assert KbAnnotation.exists?(note.id)
    assert_equal 0, MediaDigest.where(body: "digest").count

    Kb::ProjectLock.lock!(Kb::Project.at(@base, "Secret"), PW, user: user)
    KbAnnotation.stub(:insert_all, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Secret"), PW, user: user)
    end
    assert_equal [ ".kb-project.yml", "notes.md", "sub" ], children
    assert_not Kb::Project.at(@base, "Secret").locked?
  end

  test "annotations follow the project folder when it was renamed while locked" do
    note = user.kb_annotations.create!(source_path: src, relative_path: "Secret/sub/deep.txt", quote: "q", start_offset: 0, end_offset: 3)
    Kb::ProjectLock.lock!(@project, PW, user: user)
    FileUtils.mv(File.join(@base, "Secret"), File.join(@base, "Renamed"))

    Kb::ProjectLock.unlock!(Kb::Project.at(@base, "Renamed"), PW, user: user)
    assert_equal "Renamed/sub/deep.txt", KbAnnotation.find(note.id).relative_path
  end

  test "write_block reports busy and locked projects" do
    assert_nil Kb::ProjectLock.write_block(@base, "Secret")
    Kb::ProjectLock.lock!(@project, PW)
    assert_equal :locked, Kb::ProjectLock.write_block(@base, "Secret/sub")
    Kb::ProjectLock::STATE[File.join(src, "Secret")] = { op: :unlock }
    assert_equal :busy, Kb::ProjectLock.write_block(@base, "Secret")
  end
end
