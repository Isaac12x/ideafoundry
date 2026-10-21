#!/usr/bin/env bash
# Claude Code PreToolUse hook: block anything that could wipe a database. Exit 2 = block. Fails CLOSED.
# Best effort only (regex on shell text): the rake and initializer guards are the hard stop.
#   guard_db.sh          Bash matcher; hook JSON on stdin (or the command as $1, for tests)
#   guard_db.sh --file   Write|Edit|NotebookEdit matcher; file_path on stdin (or $1, for tests)
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
# the project's top-level storage dir: storage, ./storage, ../x/storage, /abs/storage, $PWD/storage
# (not ./lib/storage, tmp/storage, storage.yml)
STORAGE='(^|[[:space:]])((\./)+|(\.\./)+([^[:space:]]*/)?|(~|\$PWD|\$HOME)?/([^[:space:]]*/)?)?storage(/|[[:space:]]|$)'
DB="(\\.sqlite3?|${STORAGE}|recovery_passphrase)"
has() { echo "$2" | grep -Eqi -- "$1"; }                 # has REGEX TEXT
bad() { has "$1" "$2" && deny "$3"; }                    # bad REGEX TEXT MESSAGE

# --- 2. Write|Edit|NotebookEdit: database files and the project's storage/ only (config/storage.yml is fine) ---
if [ "$mode" = file ]; then
  root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"; p="${raw#./}"
  bad '\.sqlite3?(-wal|-shm|-journal)?$' "$p" "Editing a database file."
  case "$p" in storage/*|"$root"/storage/*) deny "Editing under storage/." ;; esac
  exit 0
fi

# Normalise. Prose is blanked: quoted-heredoc bodies of `git commit`/`gh` (literal text), commit/PR message
# strings and the first echo/printf string, but never a double-quoted string holding $( or a backtick (it executes).
# Quotes -> spaces so `rm -rf "storage"` and `bash -c 'rm -rf storage'` read as plain words; backticks -> `;` so their
# contents sit in command position; `>|` -> `>`; ${PWD} and $(pwd) -> $PWD.
# Heredoc bodies are dropped only for `git commit`/`gh` lines (not `$(cat ...)`, which can feed anything), and only when no
# shell/interpreter word appears anywhere (`| sh`, `sh <<EOF`, `python3 - <<EOF` would execute the body).
if ! has "${W}(sh|bash|zsh|dash|ksh|eval|source|ruby|python3?|perl|node|xargs|runner|console)${E}" "$raw"; then
  raw=$(echo "$raw" | awk '!h { print } h { l=$0; gsub(/^[ \t]+/, "", l); if (l == t) { h=0; print } }
    !h && match($0, "(git commit|gh (pr|issue))[^|;&]*<<-?[ ]*[\"\047][A-Za-z_]+[\"\047]") { t=substr($0, RSTART, RLENGTH); sub(/^.*<</, "", t); gsub(/[^A-Za-z_]/, "", t); h=1 }') || deny "Normalising failed."
fi
q="'"; str="(\"([^\"\`$]|\\\$[^(])*\"|$q[^$q]*$q)"
if has 'git commit|gh (pr|issue)' "$raw"; then raw=$(echo "$raw" | sed -E "s/(-m|--message|--body|--title|-b)[[:space:]]+$str/\1 x/g") || deny "Normalising failed."; fi
cmd=$(echo "$raw" | sed -E "s/(echo|printf)[[:space:]]+$str/\1 x/g" | tr "\"'" '  ' | tr '`' ';') || deny "Normalising failed."
cmd=${cmd//>|/>}; cmd=${cmd//\$\{PWD\}/\$PWD}; cmd=${cmd//\$(pwd)/\$PWD}; cmd=${cmd//\$\{HOME\}/\$HOME}

# --- 3. whole command (must see across pipes, loops, heredocs, interpreter snippets) ---
has "xargs[^;&]*${W}(rm|mv|shred|unlink|truncate)${E}" "$cmd" && has "$DB" "$cmd" && deny "xargs delete."
# piping code into a shell (unless `-c`) or into an interpreter that reads it from stdin (no args, `-` or `-s`)
SH='(sh|bash|zsh|dash|ksh|source|eval)'
has "\\|[[:space:]]*(sudo[[:space:]]+)?${SH}([[:space:]]|$)" "$cmd" && ! has "\\|[[:space:]]*(sudo[[:space:]]+)?${SH}[[:space:]]+-[a-z]*c" "$cmd" && deny "Piping into a shell."
bad "\\|[[:space:]]*(sudo[[:space:]]+)?(ruby|python3?|perl|node)([[:space:]]+-s?)?[[:space:]]*($|[;&|)])" "$cmd" "Piping code into an interpreter."
has "(for|while|until)[[:space:]][^;]*${DB}" "$cmd" && has "${W}(rm|mv|shred|unlink|truncate)${E}" "$cmd" && deny "Loop over database/storage files that deletes."
# interpreter snippets (ruby/python/node/perl/console); in-place sed/perl/awk text edits are not snippets (their file args are judged below)
snip=$(echo "$cmd" | tr ';&|' '\n\n\n' | grep -Ev "^[[:space:]]*(sed|perl|awk|gawk)[[:space:]].*(-[a-z]*i([[:space:]]|$)|--in-place|inplace)")
if has "(runner|console|rails c|ruby|python3?|perl|node|${W}-e${E})" "$snip"; then
  bad "DatabaseTasks|drop_table|drop_database|delete_all|destroy_all|truncate|\\.purge|${W}execute${E}|exec_[a-z]+|drop[[:space:]]+table|delete[[:space:]]+from" "$snip" "Wiping snippet."
  has "$DB" "$snip" && bad "File\\.(delete|unlink|rename)|FileUtils|rm_rf|os\\.(remove|unlink|rename|rmdir)|shutil|unlink($|[[:space:]]|\\(|Sync)|rmSync|renameSync|File\\.(write|open|binwrite)|IO\\.(write|binwrite)|open\\([^)]*,[[:space:]]*[wa]b?[[:space:]]*[,)]" "$snip" "Deleting/moving files near a database."
fi
bad 'docker(-compose)?[[:space:]]+(compose[[:space:]]+)?down[^;&|]*[[:space:]](-v|--volumes)' "$cmd" "docker down -v deletes volumes."
bad 'docker[[:space:]]+volume[[:space:]]+(rm|prune)|docker[[:space:]]+system[[:space:]]+prune[^;&|]*--volumes' "$cmd" "docker volume removal."

# --- 4. per segment (split on ; & | ( ) { } newline), judged by command position ---
while IFS= read -r seg; do
  read -ra w <<<"$seg"; w=("${w[@]#\\}")   # \rm is rm
  i=0   # skip prefixes: VAR=x, sudo/env/bash/-c/-i/then/do/!..., so `env -i bash -c rm -rf storage` is judged as rm
  while [ $i -lt ${#w[@]} ] && [[ "${w[$i]}" == *=* || "${w[$i]}" == -* || "${w[$i]}" =~ ^(sudo|command|env|exec|nohup|time|eval|bash|sh|zsh|bundle|then|do|else|elif|while|until|if|!|\$)$ ]]; do i=$((i+1)); done
  [ $i -lt ${#w[@]} ] || continue
  c="${w[$i]##*/}"; s="${w[*]:$i}"; last="${w[$((${#w[@]}-1))]}"
  files="${w[*]:$((i+1))}"; for ((j=i+1; j<${#w[@]}; j++)); do [[ "${w[$j]}" == -* ]] || { files="${w[*]:$((j+1))}"; break; }; done   # args after the first non-option (the sed/perl/awk script)

  # redirects, tee, dd of= onto a database or storage/
  bad ">>?[[:space:]]*[^[:space:]]*${DB}|tee[[:space:]][^;&|]*${DB}|of=[^[:space:]]*${DB}" "$s" "Writing to a database file."

  [[ -n "$in_storage" && "$c" =~ ^(rm|mv|cp|ln|tar|unzip|curl|wget|dd|tee|sed|perl|awk|gzip|xz|bzip2|zstd|find|truncate|shred)$ ]] && deny "Working inside storage/ (cd)."
  case "$c" in
    rails|rake)   # destructive tasks are blocked in every env, RAILS_ENV=test included
      bad 'db:(schema:load|reset|drop|purge|setup|truncate_all|seed:replant|migrate:(reset|redo|down)|rollback|fixtures:load)' "$s" "Destructive db task."
      bad 'VERSION=0+([^0-9]|$)' "$s" "Migrating down to 0."
      has 'db:' "$s" && bad 'DATABASE_URL=' "$seg" "DATABASE_URL with a db task." ;;
    setup) bad '--reset' "$s" "bin/setup --reset." ;;
    git)
      bad '^git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?clean[^;&|]*[[:space:]](-[a-z]*[xX][a-z]*|--)' "$s" "git clean -x/-X deletes ignored database files."
      bad '^git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?worktree[[:space:]]+(remove|prune)' "$s" "git worktree remove deletes its storage/."
      has '^git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(rm|mv|checkout|restore)[[:space:]]' "$s" && has "$DB" "$s" && deny "git rm/mv/checkout/restore on a database or storage/."
      bad '^git[[:space:]]+stash[^;&|]*([[:space:]]-[a-z]*[aA]|--all|--include-ignored)' "$s" "git stash --all removes ignored files." ;;
    rm|unlink|shred|truncate|rmdir|chflags|chmod|dd|trash|gzip|gunzip|bzip2|bunzip2|xz|unxz|zstd)   # delete, or replace the original
      bad "$DB" "$s" "Touching database files."
      [ "$c" = rm ] && bad "(^|[[:space:]])(/|\\.|\\.\\.|~|\\*|\\\$PWD|\\\$HOME)/?\\*?([[:space:]]|$)" "$s" "rm of a project directory."
      # recursive: home/work, parent globs, a sibling repo/worktree (../name), repos/name
      [ "$c" = rm ] && has '[[:space:]](-[a-zA-Z]*[rR]|--recursive)' "$s" && bad "(^|[[:space:]])(~/work[^[:space:]]*|\\.\\./(\\*|[^[:space:]/]+)/?|(.*/)?repos/[^[:space:]/]+/?)\\*?([[:space:]]|$)" "$s" "rm -r of a parent or sibling repo directory." ;;
    sed|perl|awk|gawk) has "$DB" "$files" && bad '[[:space:]]-[a-z]*i|--in-place|inplace' "$s" "In-place edit of a database file." ;;
    curl|wget) has "$DB" "$s" && bad '(^|[[:space:]])(-o|-O|--output|--output-document)([[:space:]=]|$)' "$s" "Download over a database file." ;;
    tar) has "$DB" "$s" && bad '(^tar[[:space:]]+[a-z]*x|[[:space:]]-[a-z]*x|--extract)' "$s" "tar extract into storage/." ;;
    unzip) has "$DB" "$s" && ! has '[[:space:]]-[a-z]*[lpt]' "$s" && deny "unzip into storage/." ;;
    cd|pushd|popd) in_storage=; has "$STORAGE" "$s" && in_storage=1 ;;   # each cd resets, then re-arms if it enters storage
    mv) bad "$DB" "$s" "Moving database files or storage/." ;;
    cp|ln|install|ditto|rsync) has "$STORAGE" "$last" && deny "Copy/link into storage/." ;;   # last arg = destination; backups out of storage/ are fine
    find) has '-delete|-exec[[:space:]]+(rm|mv|shred|unlink)' "$s" && { has "$DB" "$s" || has '^find[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(\.|\.\.|~|/)([[:space:]]|$)' "$s"; } && deny "find that deletes in storage or a project dir." ;;
    sqlite3)   # raw writes: only -readonly, or a test db (token "test" in every .sqlite3 name)
      has '(^|[[:space:]])-readonly' "$s" && continue
      has "${W}test${E}" "$(echo "$s" | grep -Eo '[^[:space:]]*\.sqlite3[^[:space:]]*' | tr '\n' ' ')" && ! has "(development|production)" "$s" && continue
      bad "(^|[;[:space:](])(insert|update|delete|drop|alter|create|replace|attach|vacuum|pragma[[:space:]]+writable_schema)[[:space:]]|\\.(restore|read|import|clone|backup|save)|<" "$s" "Writes through raw sqlite3; read with \`sqlite3 -readonly <db>\`." ;;
  esac
done < <(echo "$cmd" | tr ';&|(){}' '\n\n\n\n\n\n\n')
exit 0
