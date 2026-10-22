require "test_helper"
require "open3"

# Probe strings live only here, as data handed to the hook by Open3 (argument or stdin). Nothing is ever executed.
# One case per line; a literal \n in a line becomes a newline (heredoc bodies).
class GuardDbHookTest < ActiveSupport::TestCase
  HOOK = Rails.root.join(".claude/hooks/guard_db.sh").to_s
  FILE_HOOK = [ HOOK, "--file" ].freeze

  def self.cases(text) = text.lines.map { |l| l.chomp.gsub('\n', "\n") }.reject(&:empty?)
  def status(cmd) = Open3.capture3(HOOK, cmd)[2].exitstatus

  BLOCKED = cases(<<~'CASES')
    bin/rails db:reset
    RAILS_ENV=production bin/rails db:drop
    bundle exec rake db:schema:load:queue
    DATABASE_URL=sqlite3:x.sqlite3 bin/rails db:migrate
    DATABASE_URL=x bin/rails db:migrate
    bin/rails db:migrate VERSION=0
    bin/rails db:migrate VERSION=00
    bin/rails db:rollback STEP=3
    bin/rails db:migrate:redo
    RAILS_ENV=test bin/rails db:drop
    env -i bin/rails db:drop
    bin/rails 'db:drop'
    bin/rails "db:schema:load"
    bin/setup --reset
    rm storage/development.sqlite3
    rm -f storage/production.sqlite3-wal
    rm -rf storage/
    rm -rf storage
    rm -rf "storage"
    rm -rf 'storage'
    rm -rf ./storage
    rm -rf storage/*
    rm -rf ../idea-app/storage
    rm -rf ../../repos/idea-app/storage/x
    rm -rf $PWD/storage
    rm -rf ${PWD}/storage
    rm -rf $(pwd)/storage
    \rm -rf storage
    bash -c 'rm -rf storage'
    sh -c "rm -rf storage"
    eval "rm -rf storage"
    env -i bash -c 'rm -rf storage'
    ls storage | xargs rm
    mv storage storage.bak
    mv storage/development.sqlite3 /tmp/x
    mv x.db storage/development.sqlite3
    echo > storage/development.sqlite3
    echo x >| storage/development.sqlite3
    echo x > storage/a.sqlite3
    cat x > storage/test.sqlite3
    echo | tee storage/development.sqlite3
    dd if=/dev/zero of=storage/development.sqlite3
    cp /tmp/x.db storage/development.sqlite3
    cp x storage/a.bin
    cp x ../idea-app/storage/
    rsync -a x storage/
    ln -sf /dev/null storage/development.sqlite3
    gzip storage/development.sqlite3
    zstd --rm storage/development.sqlite3
    xz -f storage/production.sqlite3
    trash storage/development.sqlite3
    sed -i '' s/a/b/ storage/development.sqlite3
    perl -pi -e s/a/b/ storage/development.sqlite3
    awk -i inplace 1 storage/development.sqlite3
    curl -o storage/development.sqlite3 http://x
    curl --output storage/development.sqlite3 http://x
    wget -O storage/development.sqlite3 http://x
    tar xzf b.tgz -C storage
    cd storage && tar xf b.tgz
    unzip b.zip -d storage
    git clean -fdx
    git clean -fX
    git worktree remove ../other
    git stash -u --all
    git stash --include-ignored
    git rm storage/x.sqlite3
    git mv storage/x.sqlite3 y
    git checkout -- storage
    git restore storage
    find storage -delete
    find . -name '*.sqlite3' -exec rm {} \;
    find . -name '*.sqlite3' -delete
    find . -delete
    find ~ -delete
    rm -rf .
    rm -rf *
    rm -rf ./*
    rm -rf /
    rm -rf $(pwd)
    rm -rf ../idea-app
    rm -rf ../*
    rm -rf ~
    rm -rf ~/work
    rm -rf ~/work/repos/idea-app
    rm -rf $HOME
    pushd storage && rm x
    cd storage; rm x
    for f in storage/*.sqlite3; do rm "$f"; done
    if true; then rm -rf storage; fi
    { rm -rf storage; }
    ! rm -rf storage
    (rm -rf storage)
    (cd storage && rm x)
    $(rm -rf storage)
    sqlite3 storage/development.sqlite3 'DELETE FROM ideas'
    sqlite3 storage/development.sqlite3 'drop table ideas'
    sqlite3 storage/development.sqlite3 "update ideas set title=1"
    sqlite3 storage/development.sqlite3 'insert into t values (1)'
    sqlite3 storage/development.sqlite3 'select * from ideas where created_at < 1'
    sqlite3 storage/development.sqlite3 '.restore /tmp/x.db'
    sqlite3 a.db "VACUUM INTO 'storage/development.sqlite3'"
    sqlite3 storage/development.sqlite3 < x.sql
    bin/rails runner 'ActiveRecord::Tasks::DatabaseTasks.purge_all'
    bin/rails runner 'ActiveRecord::Base.connection.drop_table :ideas'
    bin/rails runner 'Idea.delete_all'
    bin/rails runner -e production 'Idea.destroy_all'
    bin/rails runner 'a; X.delete_all'
    bin/rails runner 'ActiveRecord::Base.connection.exec_query("x")'
    bin/rails runner 'ActiveRecord::Base.connection.exec_delete("x")'
    bin/rails runner 'File.delete("storage/development.sqlite3")'
    bin/rails runner 'FileUtils.rm_rf("storage")'
    bin/rails runner 'File.write("storage/a.sqlite3", 1)'
    bin/rails runner 'File.open("storage/development.sqlite3", "w")'
    bin/rails runner 'IO.binwrite("storage/a.sqlite3", "")'
    python3 -c 'import os; os.remove("storage/x.sqlite3")'
    python3 -c 'import shutil; shutil.rmtree("storage")'
    python3 -c "open('storage/x.sqlite3','w')"
    python3 -c "open('storage/x.sqlite3', 'a')"
    perl -e 'unlink "storage/development.sqlite3"'
    node -e 'require("fs").unlinkSync("storage/development.sqlite3")'
    node -e 'fs.rmSync("storage", {recursive:true})'
    node -e 'fs.renameSync("storage/a.sqlite3","b")'
    bin/rails c <<< 'Idea.delete_all'
    bin/rails console <<< 'ActiveRecord::Base.connection.execute(1)'
    bin/rails dbconsole <<< 'drop table ideas'
    bin/rails c <<EOF\nIdea.destroy_all\nEOF
    bin/rails runner - <<'EOF'\nIdea.delete_all\nEOF
    docker compose down -v
    docker-compose down --volumes
    docker volume rm idea_data
    git commit -m x && bin/rails runner 'X.delete_all'
    git commit -m "$(rm -rf storage)"
    git commit -m "x `rm -rf storage`"
    git commit --message "$(rm -rf storage)"
    git commit -m "a" -m "$(rm -rf storage)"
    echo "$(rm storage/development.sqlite3)"
    echo "`rm storage/a.sqlite3`"
    gh pr create --body "$(bin/rails db:drop)"
    gh pr create --title "$(rm -rf storage)"
    gh issue create --body "$(rm -rf storage)"
    echo `rm -rf storage`
    ls `rm -rf storage`
    git commit -m "$(cat <<'EOF' | sh\nrm -rf storage\nEOF\n)"
    echo $(cat <<'EOF'\nrm -rf storage\nEOF\n) | sh
    gh pr create --body "$(cat <<'EOF'\nx\nEOF\n)" | sh
    $(cat <<'EOF'\nrm -rf storage\nEOF\n)
    git commit -m x "$(sh <<'EOF'\nrm -rf storage\nEOF\n)"
    sh -s git commit <<'EOF'\nrm -rf storage\nEOF
    python3 - git commit <<'EOF'\nimport os; os.remove('storage/development.sqlite3')\nEOF
    echo x | sh
    echo x | bash -s
    echo x | python3
    echo x | ruby
    echo x | node -
    echo x | sudo sh
    git commit -m x # <<'EOF'\nrm -rf storage\nEOF
    git commit -m x # <<'EOF'\nbin/rails db:drop\nEOF
    echo "git commit <<'EOF'"\nrm -rf storage\nEOF
    git commit -m "a <<'EOF'"\nrm -rf storage\nEOF
    git log --grep='git commit <<"EOF"'\nrm -rf storage\nEOF
    git commit -m "$(cat <<'EOF'\nprose\nEOF\n)" && rm -rf storage
    sqlite3 storage/development.sqlite3 'select count(*) from ideas'
    sqlite3 storage/development.sqlite3 'select * from updates'
    sqlite3 storage/development.sqlite3 'select 1; delete from ideas'
    sqlite3 storage/development.sqlite3 'select 1;\ndelete from ideas'
    sqlite3 storage/production.sqlite3 .dump
    sqlite3 -readonly storage/development.sqlite3 '.shell rm -rf storage'
    sqlite3 -readonly storage/development.sqlite3 '.system touch x'
    sqlite3 -readonly storage/development.sqlite3 '.output storage/x.sqlite3'
    sqlite3 -readonly storage/development.sqlite3 '.once x'
    sqlite3 -readonly storage/development.sqlite3 '.cd /'
    sqlite3 -readonly storage/development.sqlite3 '.log x'
    nice -n 10 rm -rf storage
    nice rm -rf storage
    timeout 5 rm -rf storage
    timeout -s KILL 5 rm -rf storage
    stdbuf -oL rm -rf storage
    arch -arm64 rm -rf storage
    caffeinate -i rm -rf storage
    ionice -c 2 rm -rf storage
    sudo -u root rm -rf storage
    sudo -n rm -rf storage
    find tmp -exec sh -c 'rm -rf storage' \;
    find tmp -name x -exec env rm -rf storage \;
    find tmp -exec ruby -e x {} \;
    find tmp -exec python3 x {} \;
    rm -rf tmp/../storage
    rm -rf ./tmp/../storage/*
    rm -rf a/b/../../storage
    mv tmp/../storage x
    cp x tmp/../storage/a.bin
    python3 -c "import subprocess; subprocess.run(['rm', '-rf', 'storage'])"
    python3 -c "import os; os.system('rm -rf storage')"
    python3 -c "os.popen('rm -rf storage')"
    ruby -e 'system("rm -rf storage")'
    ruby -e 'spawn("rm -rf storage")'
    ruby -e 'exec("rm -rf storage")'
    node -e 'require("child_process").exec("rm -rf storage")'
    fish -c 'rm -rf storage'
    osascript -e 'do shell script "rm -rf storage"'
    rm -rf $HOME/work
    rm -rf $HOME/work/projects
    rm -rf /Users/someone/work
    rm -rf ~/work/projects
    gzip storage/development.sqlite3
    xz storage/production.sqlite3
    bzip2 -f storage/development.sqlite3
    zstd --rm storage/development.sqlite3
    sqlite3 storage/development.sqlite3 -readonly 'select 1'
    sqlite3 -readonly -cmd '.shell rm -rf storage' storage/development.sqlite3
    sqlite3 -cmd .tables storage/development.sqlite3
    sqlite3 -readonly storage/development.sqlite3 '.open /tmp/x'
    sqlite3 -readonly storage/development.sqlite3 '.backup /tmp/x'
    sqlite3 -readonly storage/development.sqlite3 '.save /tmp/x'
    sqlite3 -readonly storage/development.sqlite3 '.clone /tmp/x'
    sqlite3 -readonly storage/development.sqlite3 '.read /tmp/x.sql'
    printf '.tables' | sqlite3 storage/development.sqlite3
    printf '.shell rm -rf storage' | sqlite3 -readonly storage/development.sqlite3
    echo '.system touch x' | sqlite3 -readonly storage/development.sqlite3
    sqlite3 storage/test.sqlite3 storage/development.sqlite3 'delete from t'
    sqlite3 storage/test.sqlite3 .shell
    echo x > .claude/hooks/guard_db.sh
    echo x >.claude/settings.json
    echo x | tee .claude/settings.local.json
    sed -i '' s/a/b/ .claude/settings.local.json
    cp /tmp/x .claude/hooks/guard_db.sh
    mv .claude/hooks/guard_db.sh /tmp/x
    ln -sf /tmp/x config/initializers/db_wipe_guard.rb
    chmod 000 lib/tasks/db_guard.rake
    rm .claude/settings.json
    truncate -s 0 lib/tasks/db_guard.rake
    git checkout -- .claude/hooks/guard_db.sh
    git restore .claude/settings.json
    somewrapper rm -rf storage
    unknown-tool unlink storage/development.sqlite3
    strace -f rm storage/x
    echo x >storage/a.bin
    rm -rf dir=storage
    git -C . clean -fdx
    git -c core.x=y clean -fdx
    git --no-pager clean -fdx
    git --git-dir=.git clean -fdx
    git -C /tmp rm storage/x.sqlite3
    git -C . checkout -- storage
    find $PWD -delete
    find "$PWD" -delete
    find $HOME -delete
    find ./ -delete
    find * -delete
    rm -rf ../../idea-app
    rm -rf ../../../repos
  CASES

  ALLOWED = cases(<<~'CASES')
    bin/rails db:prepare
    bin/rails db:migrate
    RAILS_ENV=test bin/rails db:test:prepare
    bin/rails db:migrate:status
    DATABASE_URL=x bin/rails server
    sqlite3 -readonly storage/development.sqlite3 'select count(*) from ideas'
    sqlite3 -readonly storage/development.sqlite3 'select * from updates'
    sqlite3 -readonly storage/development.sqlite3 .dump
    sqlite3 --version
    sqlite3 :memory: 'select 1'
    sqlite3 -readonly storage/development.sqlite3 < x.sql
    sqlite3 storage/test.sqlite3 'delete from t'
    sqlite3 storage/test.sqlite3 < x.sql
    bin/backup
    ls storage/
    ls storage
    stat storage/development.sqlite3
    cp storage/development.sqlite3 ~/backups/dev.bak
    cp storage/development.sqlite3 /tmp/backup.sqlite3
    rm tmp/foo.log
    rm tmp/x
    rm -rf tmp/x
    rm -rf log/*
    rm -rf tmp/*
    rm -rf node_modules/*
    rm -rf tmp/storage
    rm -rf ./tmp/storage
    rm ./lib/storage/helper.rb
    rm app/storage_x.rb
    rm ../foo.txt
    mv config/storage.yml config/storage.yml.bak
    mv ./app/services/storage ./app/services/blobs
    sed -i '' s/a/b/ config/storage.yml
    sed -i '' s/a/b/ ./app/models/storage/x.rb
    sed -i '' 's/storage/foo/' app/models/idea.rb
    perl -pi -e 's/destroy_all/each(&:destroy)/' app/models/idea.rb
    git checkout -- config/storage.yml
    git status
    git clean -fd
    find tmp -name '*.log'
    find tmp -name '*.log' -delete
    find app -name "*.rb" -delete
    tar czf b.tgz storage/x.sqlite3
    cd storage && ls
    cd storage; cd ..; rm tmp/x
    popd
    for f in a b; do rm "$f"; done
    docker compose down
    bin/rails test
    bin/rails runner 'puts Idea.count'
    python3 -c "open('storage/x.sqlite3').read()"
    git commit -m 'rm storage/x.sqlite3'
    git commit -m "bin/rails db:drop notes"
    git commit -m "fix rm -rf storage db:reset"
    git add -A && git commit -m "fix console delete_all"
    gh pr create --body "...delete_all in runner..." --title x
    echo rm storage/x.sqlite3
    echo "rm storage/x delete_all runner"
    git commit -F - <<'EOF'\nmsg rm -rf storage\ndb:reset\nEOF
    git commit -m "$(cat <<'EOF'\nfix: rm -rf storage and db:reset\nEOF\n)"
    gh pr create --body "$(cat <<'EOF'\n## Summary\nrm -rf storage and db:reset are blocked\nEOF\n)"
    curl -s x | python3 -m json.tool
    cat a.json | python3 -c 'import json,sys; print(json.load(sys.stdin))'
    git log | ruby -ne 'puts $_'
    echo '{}' | node -e 'process.stdin.pipe(process.stdout)'
    ls | perl -pe 's/a/b/'
    rg x | xargs -n1 echo
    echo x | bash -c 'echo hi'
    gzip -c storage/development.sqlite3 > /tmp/dev.gz
    gzip -k storage/development.sqlite3
    xz --keep storage/production.sqlite3
    zstd --stdout storage/development.sqlite3 > /tmp/dev.zst
    bzip2 -ck storage/development.sqlite3 > /tmp/dev.bz2
    nice -n 10 ls storage
    timeout 5 ls storage
    sudo -u root ls storage
    find tmp -exec ls {} \;
    git log --grep='rm -rf storage'
    git commit -m x # just a comment
    gh pr create --title "x" --body "$(cat <<'EOF'\n## Summary\nrm -rf storage and db:reset\nEOF\n)"
    git commit -m "t" -m "$(cat <<'EOF'\nrm -rf storage and db:reset\nEOF\n)"
    sqlite3 -readonly storage/development.sqlite3 .tables
    sqlite3 -readonly storage/development.sqlite3 .schema
    sqlite3 -readonly storage/development.sqlite3 '.mode csv'
    sqlite3 -readonly -header storage/development.sqlite3 '.indexes'
    sqlite3 -readonly storage/development.sqlite3 '.databases'
    printf '.tables' | sqlite3 -readonly storage/development.sqlite3
    cat .claude/hooks/guard_db.sh
    cp .claude/hooks/guard_db.sh /tmp/backup.sh
    git add .claude/hooks/guard_db.sh
    git diff .claude/settings.json
    ls .claude/hooks
    git -C . status
    git --no-pager log
    git -c color.ui=never diff
    git -C . clean -fd
    find app -delete -name x
    find ./tmp -name '*.log'
    rm -rf ../tmp-copy/x
    strace -f ls storage
  CASES

  BLOCKED.each_with_index do |cmd, i|
    test "blocks ##{i} #{cmd}" do
      assert_equal 2, status(cmd), cmd
    end
  end

  ALLOWED.each_with_index do |cmd, i|
    test "allows ##{i} #{cmd}" do
      assert_equal 0, status(cmd), cmd
    end
  end

  test "fails closed on unparseable or command-less stdin" do
    [ "{not json", "", '{"tool_input":{}}' ].each do |input|
      assert_equal 2, Open3.capture3(HOOK, stdin_data: input)[2].exitstatus, input
    end
  end

  test "reads the command from hook JSON on stdin" do
    assert_equal 2, Open3.capture3(HOOK, stdin_data: '{"tool_input":{"command":"bin/rails db:drop"}}')[2].exitstatus
    assert_equal 0, Open3.capture3(HOOK, stdin_data: '{"tool_input":{"command":"ls"}}')[2].exitstatus
  end

  def file_status(path, project_dir = nil)
    env = project_dir ? { "CLAUDE_PROJECT_DIR" => project_dir } : {}
    Open3.capture3(env, *FILE_HOOK, stdin_data: %({"tool_input":{"file_path":"#{path}"}}))[2].exitstatus
  end

  test "file-edit mode blocks db files, any storage/ dir (even another checkout's) and lexical ../ tricks" do
    root = Rails.root.to_s
    [ "/r/storage/development.sqlite3", "/r/x/production.sqlite3-wal", "/r/x/x.sqlite3-shm", "/r/x/dev.sqlite3-journal",
      "storage/x.txt", "#{root}/storage/notes.txt", "/Users/someone/other-checkout/storage/x.txt", "/r/lib/storage/helper.rb",
      "tmp/../storage/x.txt", "/r/app/../storage/x.txt", "./storage/x.txt", "/r/config/recovery_passphrase.key",
      "storage/recovery_passphrase.key", "/r/x/../x/../storage", "STORAGE/x.txt", "/r/Storage/y.txt" ].each do |p|
      assert_equal 2, file_status(p, root), p
    end
  end

  test "file-edit mode blocks edits to the guards themselves (owner-edited only)" do
    root = Rails.root.to_s
    [ ".claude/hooks/guard_db.sh", "#{root}/.claude/hooks/guard_db.sh", ".claude/settings.json", "#{root}/.claude/settings.json",
      "config/initializers/db_wipe_guard.rb", "#{root}/lib/tasks/db_guard.rake", "lib/tasks/db_guard.rake",
      ".claude/hooks/../settings.json", "app/../config/initializers/db_wipe_guard.rb",
      ".claude/settings.local.json", ".claude/launch.json", ".claude/hooks/other.sh", ".claude/hooks/new_hook.sh",
      ".CLAUDE/Hooks/guard_db.sh", "/r/.Claude/Settings.JSON", "/R/Config/Initializers/DB_Wipe_Guard.rb", "LIB/Tasks/DB_GUARD.RAKE" ].each do |p|
      stdout, stderr, st = Open3.capture3(*FILE_HOOK, stdin_data: %({"tool_input":{"file_path":"#{p}"}}))
      assert_equal 2, st.exitstatus, p
      assert_match(/owner-edited only/, stderr, p)
    end
  end

  test "file-edit mode allows config/storage.yml and similar" do
    root = Rails.root.to_s
    %w[/r/config/storage.yml /r/app/models/storage_item.rb config/storage.yml /r/app/models/idea.rb
       app/../config/storage.yml /r/lib/tasks/other.rake .claude/skills/x/SKILL.md .claude/agents/a.md].each do |p|
      assert_equal 0, file_status(p, root), p
    end
  end

  test "settings.json is valid JSON and wraps both guard hooks so a missing or broken script still blocks" do
    settings = JSON.parse(File.read(Rails.root.join(".claude/settings.json")))
    guards = settings.dig("hooks", "PreToolUse").flat_map { |g| g["hooks"] }.map { |h| h["command"] }.select { |c| c.include?("guard_db.sh") }
    assert_equal 2, guards.size
    guards.each { |c| assert c.end_with?("|| exit 2"), c }
  end

  test "the wrapped hook command exits 2 when the script is missing (127) or not executable (126)" do
    command = JSON.parse(File.read(Rails.root.join(".claude/settings.json"))).dig("hooks", "PreToolUse", 0, "hooks", 0, "command")
    Dir.mktmpdir do |dir|
      assert_equal 2, Open3.capture3({ "CLAUDE_PROJECT_DIR" => dir }, "/bin/sh", "-c", command)[2].exitstatus, "missing"
      FileUtils.mkdir_p(File.join(dir, ".claude/hooks"))
      File.write(File.join(dir, ".claude/hooks/guard_db.sh"), "#!/bin/sh\nexit 0\n", perm: 0o644)
      assert_equal 2, Open3.capture3({ "CLAUDE_PROJECT_DIR" => dir }, "/bin/sh", "-c", command)[2].exitstatus, "not executable"
      File.chmod(0o755, File.join(dir, ".claude/hooks/guard_db.sh"))
      assert_equal 0, Open3.capture3({ "CLAUDE_PROJECT_DIR" => dir }, "/bin/sh", "-c", command)[2].exitstatus, "executable and allowing"
    end
  end

  test "file-edit mode fails closed" do
    assert_equal 2, Open3.capture3(*FILE_HOOK, stdin_data: "{nope")[2].exitstatus
  end
end
