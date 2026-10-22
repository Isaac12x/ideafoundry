#!/usr/bin/env bash
# Claude Code PreToolUse hook: block anything that could wipe a database. Exit 2 = block. Fails CLOSED.
# Best effort only (regex on shell text): the rake and initializer guards are the hard stop.
#   guard_db.sh          Bash matcher; hook JSON on stdin (or the command as $1, for tests)
#   guard_db.sh --file   Write|Edit|NotebookEdit matcher; file_path on stdin (or $1, for tests)
# settings.json wraps this script in `|| exit 2`, so a missing or non-executable script also blocks.
deny() { echo "BLOCKED: databases are never wiped (no opt-in). $1 Tests reset themselves (bin/rails test); never run destructive db tasks." >&2; exit 2; }

# --- 1. input (jq, else python3; anything unparseable blocks) ---
mode=bash; [ "${1:-}" = "--file" ] && { mode=file; shift; }
if [ $# -gt 0 ]; then raw="$1"
elif command -v jq >/dev/null 2>&1; then raw=$(jq -er '.tool_input | (.command // .file_path // .notebook_path)' 2>/dev/null) || deny "Unparseable hook input."
elif command -v python3 >/dev/null 2>&1; then
  raw=$(python3 -c 'import json,sys; d=json.load(sys.stdin)["tool_input"]; print(d.get("command") or d.get("file_path") or d["notebook_path"])' 2>/dev/null) || deny "Unparseable hook input."
else deny "Neither jq nor python3 available to parse hook input."; fi
[ -n "$raw" ] || deny "Empty command/path."

W='(^|[^[:alnum:]_])'; E='([^[:alnum:]_]|$)'             # word edges
# the project's top-level storage dir: storage, ./storage, ../x/storage, tmp/../storage, /abs/storage, $PWD/storage
# (not ./lib/storage, tmp/storage, storage.yml)
STORAGE='(^|[[:space:]>)=])((\./)+|([^[:space:]]*/)?(\.\./)+([^[:space:]]*/)?|(~|\$PWD|\$HOME)?/([^[:space:]]*/)?)?storage(/|[[:space:]]|$)'
DB="(\\.sqlite3?|${STORAGE}|recovery_passphrase)"
# the guards themselves: owner-edited only (hook dir, .claude/*.json, initializer, rake task, git hooks/config incl. worktree gitdirs)
GUARD='(\.claude/(hooks/|[^[:space:]/]*\.json)|config/initializers/db_wipe_guard\.rb|lib/tasks/db_guard\.rake|\.git/(hooks/|config([[:space:]]|$)|worktrees/[^/[:space:]]+/(hooks/|config)))'
# the directories themselves (rm/mv/ln/git rm/checkout of .claude, .git or .git/hooks)
DIRGUARD='(^|[[:space:]/])(\.claude|\.git(/hooks)?)(/|[[:space:]]|$)'
has() { echo "$2" | grep -Eqi -- "$1"; }                 # has REGEX TEXT
bad() { has "$1" "$2" && deny "$3"; }                    # bad REGEX TEXT MESSAGE

normpath() {   # collapse "." and ".." lexically (no filesystem access), so tmp/../storage cannot hide
  local seg out=() IFS=/ segs
  read -ra segs <<<"$1"
  for seg in "${segs[@]}"; do
    case "$seg" in ""|.) ;; ..) [ ${#out[@]} -gt 0 ] && unset 'out[${#out[@]}-1]' ;; *) out+=("$seg") ;; esac
  done
  [[ "$1" == /* ]] && printf '/'
  printf '%s' "${out[*]}"
}

# --- 2. Write|Edit|NotebookEdit: database files, anything under a storage/ dir, the guards themselves ---
if [ "$mode" = file ]; then
  shopt -s nocasematch   # APFS is case-insensitive: .Claude/Hooks/ is the same directory
  p=$(normpath "$raw")
  case "$p" in
    storage|*/storage|storage/*|*/storage/*) deny "Editing under storage/." ;;
    *recovery_passphrase*) deny "Editing the recovery passphrase." ;;
    .claude/hooks/*|*/.claude/hooks/*|.claude/*.json|*/.claude/*.json|\
    config/initializers/db_wipe_guard.rb|*/config/initializers/db_wipe_guard.rb|lib/tasks/db_guard.rake|*/lib/tasks/db_guard.rake|\
    .git/hooks/*|*/.git/hooks/*|.git/config|*/.git/config|*/.git/worktrees/*/config*|*/.git/worktrees/*/hooks/*)
      deny "guard files are owner-edited only." ;;
  esac
  bad '\.sqlite3?(-wal|-shm|-journal)?$' "$p" "Editing a database file."
  exit 0
fi

# Normalise. Prose is blanked: quoted-heredoc bodies of `git commit`/`gh` (literal text), commit/PR message
# strings and the first echo/printf string, but never a double-quoted string holding $( or a backtick (it executes).
# Quotes -> spaces so `rm -rf "storage"` and `bash -c 'rm -rf storage'` read as plain words; backticks -> `;` so their
# contents sit in command position; `>|` -> `>`; ${PWD} and $(pwd) -> $PWD.
# Heredoc bodies are dropped only when a line STARTS with `git commit`/`gh pr|issue` (only whole quoted values, no #, $
# or pipe before the heredoc, except the `"$(cat` form), and only when no shell/interpreter word appears anywhere (`| sh`,
# `sh <<EOF`, `python3 - <<EOF` would execute the body).
if ! has "${W}(sh|bash|zsh|dash|ksh|fish|eval|source|ruby|python3?|perl|node|xargs|runner|console)${E}" "$raw"; then
  raw=$(echo "$raw" | awk '!h { print } h { l=$0; gsub(/^[ \t]+/, "", l); if (l == t) { h=0; print } }
    !h && match($0, "^[ \t]*(git commit|gh (pr|issue))([^|;&#$\"\047]|\"[^\"$]*\"|\047[^\047]*\047)*(\"[$][(]cat[ \t]*)?<<-?[ ]*[\"\047][A-Za-z_]+[\"\047]") { t=substr($0, RSTART, RLENGTH); sub(/^.*<</, "", t); gsub(/[^A-Za-z_]/, "", t); h=1 }') || deny "Normalising failed."
fi
q="'"; str="(\"([^\"\`$]|\\\$[^(])*\"|$q[^$q]*$q)"
if has 'git commit|gh (pr|issue)' "$raw"; then raw=$(echo "$raw" | sed -E "s/(-m|--message|--body|--title|-b)[[:space:]]+$str/\1 x/g") || deny "Normalising failed."; fi
blank="s/(echo|printf)[[:space:]]+$str/\1 x/g"; has "${W}sqlite3${E}" "$raw" && blank='s/^$//'   # sqlite3 may read its dot-commands from the pipe
cmd=$(echo "$raw" | sed -E "$blank" | tr "\"'" '  ' | tr '`' ';') || deny "Normalising failed."
cmd=${cmd//>|/>}; cmd=${cmd//>/> }; cmd=${cmd//\$\{PWD\}/\$PWD}; cmd=${cmd//\$(pwd)/\$PWD}; cmd=${cmd//\$\{HOME\}/\$HOME}

# --- 3. whole command (must see across pipes, loops, heredocs, interpreter snippets) ---
has "xargs[^;&]*${W}(rm|mv|shred|unlink|truncate)${E}" "$cmd" && has "$DB" "$cmd" && deny "xargs delete."
# piping code into a shell (unless `-c`) or into an interpreter that reads it from stdin (no args, `-` or `-s`)
SH='(sh|bash|zsh|dash|ksh|fish|source|eval)'
has "\\|[[:space:]]*(sudo[[:space:]]+)?${SH}([[:space:]]|$)" "$cmd" && ! has "\\|[[:space:]]*(sudo[[:space:]]+)?${SH}[[:space:]]+-[a-z]*c" "$cmd" && deny "Piping into a shell."
bad "\\|[[:space:]]*(sudo[[:space:]]+)?(ruby|python3?|perl|node)([[:space:]]+-s?)?[[:space:]]*($|[;&|)])" "$cmd" "Piping code into an interpreter."
# sqlite3 dot-commands can run shells and write files: only read-only ones, anywhere in the command (printf '.x' | sqlite3 ...)
if has "${W}sqlite3${E}" "$cmd"; then
  bad "(writefile|readfile|edit\\(|load_extension|vacuum[[:space:]]+into|${W}attach${E})" "$cmd" "sqlite3 function or statement that reads/writes files or loads code."
  has '\|[[:space:]]*sqlite3' "$cmd" && ! has '(echo|printf)[^|]*\|[[:space:]]*sqlite3' "$cmd" && deny "Only echo/printf may be piped into sqlite3."
  while read -ra toks; do
    for t in "${toks[@]}"; do
      [[ "$t" =~ ^\.[a-z]+$ && ! "$t" =~ ^\.(tables|schema|dump|headers|mode|help|indexes|databases)$ ]] && deny "sqlite3 dot-command $t is not on the read-only allowlist."
    done
  done <<<"$cmd"
fi
has "(for|while|until)[[:space:]][^;]*${DB}" "$cmd" && has "${W}(rm|mv|shred|unlink|truncate)${E}" "$cmd" && deny "Loop over database/storage files that deletes."
# interpreter snippets (ruby/python/node/perl/console); in-place sed/perl/awk text edits are not snippets (their file args are judged below)
snip=$(echo "$cmd" | tr ';&|' '\n\n\n' | grep -Ev "^[[:space:]]*(sed|perl|awk|gawk)[[:space:]].*(-[a-z]*i([[:space:]]|$)|--in-place|inplace)")
if has "(runner|console|rails c|ruby|python3?|perl|node|osascript|${W}-e${E})" "$snip"; then
  bad "DatabaseTasks|drop_table|drop_database|delete_all|destroy_all|truncate|\\.purge|${W}execute${E}|exec_[a-z]+|drop[[:space:]]+table|delete[[:space:]]+from" "$snip" "Wiping snippet."
  has "(${DB}|${GUARD})" "$snip" && bad "File\\.(delete|unlink|rename)|FileUtils|rm_rf|os\\.(remove|unlink|rename|rmdir)|shutil|unlink($|[[:space:]]|\\(|Sync)|rmSync|renameSync|File\\.(write|open|binwrite)|IO\\.(write|binwrite)|open\\([^)]*,[[:space:]]*[wa]b?[[:space:]]*[,)]|subprocess|system[[:space:]]*\\(|popen|spawn|exec[[:space:]]*\\(|do shell script" "$snip" "Deleting/moving files near a database."
fi
bad 'docker(-compose)?[[:space:]]+(compose[[:space:]]+)?down[^;&|]*[[:space:]](-v|--volumes)' "$cmd" "docker down -v deletes volumes."
bad 'docker[[:space:]]+volume[[:space:]]+(rm|prune)|docker[[:space:]]+system[[:space:]]+prune[^;&|]*--volumes' "$cmd" "docker volume removal."

# --- 4. per segment (split on ; & | ( ) { } newline), judged by command position ---
while IFS= read -r seg; do
  read -ra w <<<"$seg"; w=("${w[@]#\\}")   # \rm is rm
  # skip prefixes: VAR=x, sudo/env/bash/-c/-i/then/do/!..., and wrappers with their options (nice -n 10, timeout 5, sudo -u root),
  # so `env -i bash -c rm -rf storage` is judged as rm
  i=0; wrapper=""; prev=""
  while [ $i -lt ${#w[@]} ]; do
    x="${w[$i]}"
    if [[ -n "$prev" && "$wrapper:$prev" =~ ^(sudo:-[ugphCDRT]|nice:-n|timeout:-[sk]|ionice:-[cnp]|caffeinate:-[tw])$ ]]; then prev=""   # option argument
    elif [[ "$x" == *=* || "$x" == -* ]]; then prev="$x"
    elif [[ "$x" =~ ^(sudo|command|env|exec|nohup|time|eval|bash|sh|zsh|fish|bundle|then|do|else|elif|while|until|if|!|\$|nice|timeout|stdbuf|arch|caffeinate|ionice)$ ]]; then wrapper="$x"; prev=""
    elif [[ -n "$wrapper" && "$x" =~ ^[0-9.]+[smhd]?$ ]]; then prev=""   # timeout 5, nice 10
    else break; fi
    i=$((i+1))
  done
  [ $i -lt ${#w[@]} ] || continue
  c="${w[$i]##*/}"; s="${w[*]:$i}"; last="${w[$((${#w[@]}-1))]}"
  files="${w[*]:$((i+1))}"; for ((j=i+1; j<${#w[@]}; j++)); do [[ "${w[$j]}" == -* ]] || { files="${w[*]:$((j+1))}"; break; }; done   # args after the first non-option (the sed/perl/awk script)

  # GIT_* environment can make git run programs (GIT_SSH_COMMAND, GIT_EXTERNAL_DIFF, ...), also via export/env
  for t in "${w[@]}"; do
    [[ "$t" =~ ^GIT_[A-Za-z0-9_]*= && ! "$t" =~ ^GIT_(AUTHOR|COMMITTER)_ && "$t" != GIT_PAGER=cat ]] && deny "GIT_* environment can make git run programs."
  done
  # redirects, tee, dd of= onto a database, storage/ or a guard file
  bad ">>?[[:space:]]*[^[:space:]]*(${DB}|${GUARD})|tee[^;&|]*(${DB}|${GUARD})|of=[^[:space:]]*(${DB}|${GUARD})" "$s" "Writing to a database file or a guard file."
  # fallback whatever wraps it: a delete-class word plus a database/storage path in one segment
  [[ ! "$c" =~ ^(echo|printf|grep|rg|git|gh|sqlite3)$ ]] && has "${W}(rm|unlink|shred|truncate)${E}" "$s" && has "$DB" "$s" && deny "Delete with a database/storage path."
  # guard files are owner-edited only: no delete, move, chmod, copy-over or in-place edit
  case "$c" in
    rm|unlink|shred|truncate|rmdir|chmod|chown|chflags|mv|dd|trash) bad "(${GUARD}|${DIRGUARD})" "$s" "guard files are owner-edited only." ;;
    cp|ln|install|ditto|rsync) has "(${GUARD}|${DIRGUARD})" "$last" && deny "guard files are owner-edited only." ;;
    sed|perl|awk|gawk) has "$GUARD" "$files" && has '[[:space:]]-[a-z]*i|--in-place|inplace' "$s" && deny "guard files are owner-edited only." ;;
  esac

  [[ -n "$in_storage" && "$c" =~ ^(rm|mv|cp|ln|tar|unzip|curl|wget|dd|tee|sed|perl|awk|gzip|xz|bzip2|zstd|find|truncate|shred)$ ]] && deny "Working inside storage/ (cd)."
  case "$c" in
    rails|rake)   # destructive tasks are blocked in every env, RAILS_ENV=test included
      bad 'db:(schema:load|reset|drop|purge|setup|truncate_all|seed:replant|migrate:(reset|redo|down)|rollback|fixtures:load)' "$s" "Destructive db task."
      bad 'VERSION=0+([^0-9]|$)' "$s" "Migrating down to 0."
      has 'db:' "$s" && bad 'DATABASE_URL=' "$seg" "DATABASE_URL with a db task." ;;
    setup) bad '--reset' "$s" "bin/setup --reset." ;;
    git)
      # git must not be told to run programs: no -c/--config-env, no config writes, no --exec style options, no ext:: remotes
      read -ra g <<<"$s"; k=1   # skip global options (-C dir, --git-dir=...) to reach the subcommand
      while [ $k -lt ${#g[@]} ] && [[ "${g[$k]}" == -* ]]; do
        [[ "${g[$k]}" == -c || "${g[$k]}" == --config-env* || "${g[$k]}" == --exec-path* ]] && deny "git -c/--config-env/--exec-path can make git run programs."
        [[ "${g[$k]}" =~ ^-(C|-git-dir|-work-tree|-namespace)$ ]] && k=$((k+1)); k=$((k+1))
      done
      gs="git ${g[*]:$k}"
      bad '^git[[:space:]]+(push|fetch|pull|clone|ls-remote)([[:space:]].*)?[[:space:]]--(rece[a-z-]*|upl[a-z-]*|exe[a-z-]*)([[:space:]=]|$)' "$gs" "git remote command that runs a program."
      bad '^git[[:space:]]+clone([[:space:]].*)?[[:space:]]-u[[:space:]]' "$gs" "git clone -u runs a program (--upload-pack)."
      bad '^git[[:space:]]+rebase([[:space:]].*)?[[:space:]](-x|--ex[a-z-]*)([[:space:]=]|$)' "$gs" "git rebase --exec runs commands."
      bad '^git[[:space:]]+bisect[[:space:]]+run|^git[[:space:]]+submodule([[:space:]].*)?[[:space:]]foreach|^git[[:space:]]+init([[:space:]].*)?[[:space:]]--te[a-z-]*' "$gs" "git bisect run / submodule foreach / init --template run programs."
      bad 'ext::' "$gs" "git ext:: remotes run programs."
      if has '^git[[:space:]]+config([[:space:]]|$)' "$gs"; then   # config is read-only: --get/--list style, or a bare key
        nonopt=0; readflag=""
        read -ra gc <<<"${gs#git config}"
        for t in "${gc[@]}"; do
          case "$t" in
            --get|--get-all|--get-regexp|--list|-l|--show-origin|--show-scope|--name-only) readflag=1 ;;
            -*) ;;
            *) nonopt=$((nonopt+1)) ;;
          esac
        done
        has '[[:space:]](--add|--unset|--unset-all|--replace-all|--edit|-e|--rename-section|--remove-section)([[:space:]]|$)' "$gs" && deny "git config writes are not allowed."
        { [ -n "$readflag" ] || [ "$nonopt" -le 1 ]; } || deny "git config writes are not allowed (read with --get/--list)."
      fi
      bad '^git[[:space:]]+clean[^;&|]*[[:space:]](-[a-z]*[xX][a-z]*|--)' "$gs" "git clean -x/-X deletes ignored database files."
      bad '^git[[:space:]]+worktree[[:space:]]+(remove|prune)' "$gs" "git worktree remove deletes its storage/."
      has '^git[[:space:]]+(rm|mv|checkout|restore)[[:space:]]' "$gs" && has "(${DB}|${GUARD}|${DIRGUARD})" "$gs" && deny "git rm/mv/checkout/restore on a database, storage/ or a guard file."
      bad '^git[[:space:]]+stash[^;&|]*([[:space:]]-[a-z]*[aA]|--all|--include-ignored)' "$gs" "git stash --all removes ignored files." ;;
    gh)
      bad '^gh[[:space:]]+alias[[:space:]]+(set|import)' "$s" "gh aliases can run shell commands."
      bad '^gh[[:space:]]+(extension|extensions|ext)[[:space:]]+(install|exec|upgrade)' "$s" "gh extensions run arbitrary code." ;;
    gzip|gunzip|bzip2|bunzip2|xz|unxz|zstd)   # replace the original, unless it is kept (-k/--keep) or streamed (-c/--stdout): a backup
      has '[[:space:]](-[a-z]*[ck][a-z]*|--keep|--stdout)([[:space:]]|$)' "$s" && continue
      bad "$DB" "$s" "Compressing a database file in place." ;;
    rm|unlink|shred|truncate|rmdir|chflags|chmod|dd|trash)   # delete
      bad "$DB" "$s" "Touching database files."
      [ "$c" = rm ] && bad "(^|[[:space:]])(/|\\.|\\.\\.|~|\\*|\\\$PWD|\\\$HOME)/?\\*?([[:space:]]|$)" "$s" "rm of a project directory."
      # recursive: home/work, parent globs, a sibling repo/worktree (../name), repos/name
      [ "$c" = rm ] && has '[[:space:]](-[a-zA-Z]*[rR]|--recursive)' "$s" && bad "(^|[[:space:]])((~|\\\$HOME|/Users/[^[:space:]/]+)/work[^[:space:]]*|(\\.\\./)+(\\*|[^[:space:]/]+)/?|(.*/)?repos/[^[:space:]/]+/?)\\*?([[:space:]]|$)" "$s" "rm -r of a parent or sibling repo directory." ;;
    sed|perl|awk|gawk) has "$DB" "$files" && bad '[[:space:]]-[a-z]*i|--in-place|inplace' "$s" "In-place edit of a database file." ;;
    curl|wget) has "$DB" "$s" && bad '(^|[[:space:]])(-o|-O|--output|--output-document)([[:space:]=]|$)' "$s" "Download over a database file." ;;
    tar) has "$DB" "$s" && bad '(^tar[[:space:]]+[a-z]*x|[[:space:]]-[a-z]*x|--extract)' "$s" "tar extract into storage/." ;;
    unzip) has "$DB" "$s" && ! has '[[:space:]]-[a-z]*[lpt]' "$s" && deny "unzip into storage/." ;;
    cd|pushd|popd) in_storage=; has "$STORAGE" "$s" && in_storage=1 ;;   # each cd resets, then re-arms if it enters storage
    mv) bad "$DB" "$s" "Moving database files or storage/." ;;
    cp|ln|install|ditto|rsync) has "$STORAGE" "$last" && deny "Copy/link into storage/." ;;   # last arg = destination; backups out of storage/ are fine
    find)
      bad '-exec(dir)?[[:space:]]+(sh|bash|zsh|env|ruby|python3?|perl|node)([[:space:]]|$)' "$s" "find -exec of a shell/interpreter."
      has '-delete|-exec[[:space:]]+(rm|mv|shred|unlink)' "$s" && { has "$DB" "$s" || has '^find[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(\.|\./|\.\.|~|/|\*|\./\*|\$PWD|\$HOME)([[:space:]]|$)' "$s"; } && deny "find that deletes in storage or a project dir." ;;
    sqlite3)   # on a real database -readonly must come BEFORE the db path; a test db (every .sqlite3 name has the token "test") may be written
      bad '(^|[[:space:]])-(cmd|init)([[:space:]]|$)' "$s" "sqlite3 -cmd/-init can run dot-commands."
      bad '<' "$s" "sqlite3 stdin redirects can carry dot-commands."
      ro=""; for t in "${w[@]:$((i+1))}"; do [[ "$t" == -* ]] || break; [ "$t" = -readonly ] && ro=1; done
      [ -n "$ro" ] && continue
      has "$DB" "$s" || continue
      names=$(echo "$s" | grep -Eo '[^[:space:]]*\.sqlite3?[^[:space:]]*')
      [ -n "$names" ] || deny "Raw sqlite3 on storage/ needs -readonly: sqlite3 -readonly <db>."
      while read -r t; do
        has "${W}test${E}" "$t" && ! has "(development|production)" "$t" || deny "Raw sqlite3 on a real database needs -readonly before the db path: sqlite3 -readonly <db>."
      done <<<"$names" ;;
  esac
done < <(echo "$cmd" | tr ';&|(){}' '\n\n\n\n\n\n\n')
exit 0
