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
  CASES

  ALLOWED = cases(<<~'CASES')
    bin/rails db:prepare
    bin/rails db:migrate
    RAILS_ENV=test bin/rails db:test:prepare
    bin/rails db:migrate:status
    DATABASE_URL=x bin/rails server
    sqlite3 storage/development.sqlite3 'select count(*) from ideas'
    sqlite3 storage/development.sqlite3 'select * from updates'
    sqlite3 -readonly storage/development.sqlite3 .dump
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

  test "file-edit mode blocks db files and the project's storage/" do
    root = Rails.root.to_s
    [ "/r/storage/development.sqlite3", "/r/x/production.sqlite3-wal", "/r/x/x.sqlite3-shm", "/r/x/dev.sqlite3-journal",
      "storage/x.txt", "#{root}/storage/notes.txt" ].each do |p|
      assert_equal 2, file_status(p, root), p
    end
  end

  test "file-edit mode allows config/storage.yml and similar" do
    root = Rails.root.to_s
    %w[/r/config/storage.yml /r/app/models/storage_item.rb config/storage.yml /r/lib/storage/helper.rb /r/app/models/idea.rb].each do |p|
      assert_equal 0, file_status(p, root), p
    end
  end

  test "file-edit mode fails closed" do
    assert_equal 2, Open3.capture3(*FILE_HOOK, stdin_data: "{nope")[2].exitstatus
  end
end
