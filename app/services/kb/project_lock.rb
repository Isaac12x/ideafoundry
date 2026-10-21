require "open3"
require "securerandom"

module Kb
  # Password-locks a project folder on disk (Finder shows no names/contents).
  #
  # Locked layout: the folder holds ONLY `<name>.7z` (AES-256, encrypted headers,
  # everything incl. the real .kb-project.yml inside) plus a stub `.kb-project.yml`
  # { private: true, locked: true, archive: "<name>.7z" } with nothing sensitive.
  # The stub keeps Project.at / Privacy (fail closed => private) working.
  #
  # Never loses data: plaintext is only removed after the archive passes `7z t`
  # and sits inside the folder; any failure leaves the plaintext as it was.
  # Passwords are never stored or logged; they live in memory for one run (see start).
  # ponytail: 7z takes -p on argv, so it is visible to same-user `ps` for the few
  # seconds a run lasts (7z has no reliable stdin password mode). Fine on a
  # single-user machine; switch to a keyfile-derived tool (age/gpg) if that changes.
  module ProjectLock
    class Error < ArgumentError; end

    MIN_PASSWORD = 6
    SEVEN_ZIP = ([ "/opt/homebrew/bin/7z", "/usr/local/bin/7z" ].find { |p| File.executable?(p) } || "7z").freeze

    module_function

    def available?
      _out, status = Open3.capture2e(SEVEN_ZIP, "i")
      status.success?
    rescue SystemCallError
      false
    end

    def archive_name(project) = "#{project.name}.7z"

    # In-memory run state per project folder (abs path): { op: :lock|:unlock } while
    # running, { error: "..." } after a failure until the page shows it once.
    # ponytail: per-process; a multi-process server would need a shared store.
    STATE = Concurrent::Map.new
    THREADS = Concurrent::Array.new

    def busy?(abs) = STATE[abs.to_s]&.key?(:op) || false
    def op_for(abs) = STATE[abs.to_s]&.dig(:op)

    # True when path is, contains, or sits inside a project that is locking/unlocking.
    def busy_path?(path)
      path = File.expand_path(path.to_s)
      STATE.each_pair.any? { |abs, s| s.key?(:op) && (path == abs || path.start_with?("#{abs}/") || abs.start_with?("#{path}/")) }
    end

    # :busy while the project locks/unlocks, :locked once it is locked, else nil. Writers
    # (annotations, transcripts, downloads, OCR) check this and skip or refuse.
    def write_block(base, rel)
      return :busy if busy_path?(File.join(base, rel.to_s))

      :locked if Project.containing(base, rel.to_s)&.locked?
    end

    # Last failure message, shown once.
    def take_error(abs)
      state = STATE[abs.to_s]
      return unless state&.key?(:error)

      STATE.delete(abs.to_s)
      state[:error]
    end

    def wait_all = THREADS.dup.each(&:join)

    # Runs lock!/unlock! on a background thread. Passwords can't go through Solid
    # Queue (it persists job args in the DB), so the thread closes over it in memory
    # only: never stored, logged, or queued. Cheap checks (password, wrong password,
    # active writers) run here so those errors show immediately.
    # ponytail: a restart mid-run drops the thread; plaintext stays or the stub +
    # archive stay, never both lost (see lock!/unlock!). Move to a job runner if a
    # secret-free handoff (e.g. keyfile) ever exists.
    def start(op, project, password, confirmation = password, user: nil)
      abs = project.abs or raise Error, "Folder not found."
      raise Error, "Already #{op_for(abs) == :lock ? 'locking' : 'unlocking'}." if STATE.put_if_absent(abs, { op: op })

      begin
        op == :lock ? precheck_lock!(project, password, confirmation, user) : precheck_unlock!(project, password)
      rescue StandardError
        STATE.delete(abs)
        raise
      end
      THREADS << Thread.new do
        Thread.current.report_on_exception = false
        error = nil
        Rails.application.executor.wrap do
          op == :lock ? lock!(project, password, confirmation, user: user) : unlock!(project, password, user: user)
        rescue Error => e
          error = e.message
        rescue StandardError => e
          Rails.logger.error("ProjectLock #{op}: #{e.class}: #{e.message}")
          error = "Could not #{op} the project."
        ensure
          STATE.delete(abs)
          STATE[abs] = { error: error } if error
          Kb::TreeBroadcaster.call(user) if user
          THREADS.delete(Thread.current)
        end
      end
    end

    def precheck_lock!(project, password, confirmation, user)
      raise Error, "Project is already locked." if project.locked?
      raise Error, "Password must be at least #{MIN_PASSWORD} characters." if password.to_s.length < MIN_PASSWORD
      raise Error, "Passwords don't match." unless password == confirmation
      raise Error, "7-Zip is not installed." unless available?
      raise Error, "A download or edit is still writing into this project." if Derived.active_work?(user, project)

      abs = project.abs or raise Error, "Folder not found."
      raise Error, "\"#{archive_name(project)}\" already exists in the folder." if File.exist?(File.join(abs, archive_name(project)))
    end

    # Listing needs the password (headers are encrypted) and is instant: wrong password fails here.
    def precheck_unlock!(project, password)
      raise Error, "Project is not locked." unless project.locked?

      abs = project.abs or raise Error, "Folder not found."
      archive = File.join(abs, project.archive_file)
      raise Error, "Archive is missing." unless File.file?(archive)

      run!(password, "l", archive, error: "Could not open the archive.")
    end

    def lock!(project, password, confirmation = password, user: nil)
      precheck_lock!(project, password, confirmation, user)
      abs = project.abs
      archive = File.join(abs, archive_name(project))
      hist = Derived.history_dir(project.base, project.rel)

      tmp = File.join(File.dirname(abs), ".#{project.name}.lock-#{SecureRandom.hex(4)}.7z")
      committed = false
      begin
        stashed = Derived.stash!(project, user, abs)
        before = Derived.snapshot(abs)
        hist_before = Derived.snapshot(hist)
        run!(password, "a", "-t7z", "-mhe=on", "-snl", tmp, "*", chdir: abs, error: "Could not create the archive.")
        run!(password, "t", tmp, error: "Archive verification failed. Nothing was changed.")
        # Anything written while 7z ran is not in the archive: abort rather than lose it.
        unless Derived.snapshot(abs) == before && Derived.snapshot(hist) == hist_before
          raise Error, "Files changed while locking. Nothing was changed; try again."
        end
        # Rows written to the DB since the stash would be lost: abort too.
        Derived.verify!(project, user, stashed)

        File.rename(tmp, archive)
        write_stub(abs, { "private" => true, "locked" => true, "archive" => archive_name(project) })
        committed = true
        Derived.purge_ocr(abs) # while the images still exist
        # Only the entries that went into the archive are removed; late arrivals stay.
        Derived.remove_snapshot(abs, before, except: [ Project::META_FILE ])
        Derived.remove_snapshot(hist, hist_before)
        prune_empty(hist, File.join(File.expand_path(project.base), ".ideafoundry-history"))
        Derived.scrub!(project, user, stashed)
      ensure
        File.delete(tmp) if File.exist?(tmp)
        Derived.discard_stash(abs) unless committed
      end
      project
    end

    # Removes dir and its now-empty parents up to and including the history root.
    def prune_empty(dir, root)
      while dir.start_with?("#{root}") && File.directory?(dir) && Dir.empty?(dir)
        Dir.rmdir(dir)
        dir = File.dirname(dir)
      end
    end

    def unlock!(project, password, user: nil)
      raise Error, "Project is not locked." unless project.locked?

      abs = project.abs or raise Error, "Folder not found."
      archive = File.join(abs, project.archive_file)
      raise Error, "Archive is missing." unless File.file?(archive)

      out = Dir.mktmpdir([ ".#{project.name}.unlock-", "" ], File.dirname(abs))
      begin
        run!(password, "x", "-snl", "-o#{out}", archive, error: "Could not unlock the project.")
        raise Error, "Archive has no project data." unless File.file?(File.join(out, Project::META_FILE))

        Derived.restore!(project, user, out)
        # Real marker last so a crash mid-move still leaves the stub (still locked, archive kept).
        names = Dir.children(out) - [ Derived::FILE, Derived::HISTORY ]
        names.sort_by { |c| c == Project::META_FILE ? 1 : 0 }.each do |c|
          dest = File.join(abs, c)
          # Added in Finder while locked: keep both, the restored one gets a suffix.
          dest = copy_name(dest) if c != Project::META_FILE && (File.exist?(dest) || File.symlink?(dest))
          FileUtils.mv(File.join(out, c), dest, force: true)
        end
        File.delete(archive)
      ensure
        FileUtils.rm_rf(out)
      end
      project
    end

    # "a.md" -> "a (locked copy).md", then "(locked copy 2)", ...
    def copy_name(path)
      ext = File.directory?(path) ? "" : File.extname(path)
      stem = File.join(File.dirname(path), File.basename(path, ext))
      candidate = "#{stem} (locked copy)#{ext}"
      n = 1
      candidate = "#{stem} (locked copy #{n += 1})#{ext}" while File.exist?(candidate) || File.symlink?(candidate)
      candidate
    end

    # Raises Error with a generic message (or "Wrong password."); never echoes argv.
    def run!(password, *args, error:, chdir: nil)
      opts = chdir ? { chdir: chdir } : {}
      out, status = Open3.capture2e(SEVEN_ZIP, *args.first(1), "-p#{password}", "-bd", "-y", *args.drop(1), **opts)
      return if status.success?

      raise Error, "Wrong password." if out.match?(/wrong password|cannot open encrypted/i)

      raise Error, error
    rescue Errno::ENOENT
      raise Error, "7-Zip is not installed."
    end

    def write_stub(abs, data)
      path = File.join(abs, Project::META_FILE)
      tmp = "#{path}.#{SecureRandom.hex(4)}.tmp"
      File.write(tmp, YAML.dump(data))
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end
  end
end
