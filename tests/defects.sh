#!/usr/bin/env bash
# The defect list for this repository, read by `t.sh falsify`. Every entry breaks one guard
# of t.sh on purpose and requires this repository's own behaviour suite to notice:
#
#   ./t.sh falsify --worktree -- env T_CHECK_NESTED=1 ./check.sh behaviour
#
# --worktree is not optional here. The file being edited is the harness running the edit:
# bash reads a script as it executes it, so a mutant written into the t.sh in front of you
# can be read by the very run applying it. A worktree gives the mutant a file of its own.
#
# T_CHECK_NESTED=1 leaves out the gate's own planted-defect pass. Without it every mutant
# would carry a full copy-per-plant run inside it, and the copies would be proving a t.sh
# this list has already broken.
#
# Each entry names what should do the catching with `expect caught`, so a red run is only
# credited to the guard whose failure message is actually in it: a suite that went red for
# another reason has said nothing about this defect.
#
# Two plants stay in check.sh rather than moving here: the pair that declares an
# associative array and reads markers with mapfile. They are planted only where
# CHECK_BASH32 says which bash this is, on a macOS runner under the 3.2 it ships, and a
# list has no way to say "only where the interpreter is old".

defect 'crlf' 't.sh' \
  "$(
    cat <<'EOF'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
EOF
  )" \
  '  while IFS= read -r line || [[ -n "$line" ]]; do' \
  'a repository whose marker files carry Windows line endings has every healthy run reported as a failure, and the team learns to disbelieve the verdict' \
  --and 't.sh' "$(
    cat <<'EOF'
    # CRLF would otherwise carry a carriage return into every value
    line="${line%$'\r'}"
EOF
  )" '    # CRLF would otherwise carry a carriage return into every value' \
  expect caught 'reddened a healthy CRLF run'

defect 'lenient' 't.sh' \
  "$(
    cat <<'EOF'
      *) die "config: $conf:$n — unknown key '$key' (markers, pattern, allow, logdir, tests)" ;;
EOF
  )" \
  '      *) : ;;' \
  'a typo in tests/t.conf silently switches off the policy it names, and every run afterwards believes in markers that were never loaded' \
  expect caught 'unknown key'

defect 'subshell' 't.sh' \
  '  load_markers' \
  '  MARKER_PATTERNS=()' \
  'every run passes because nothing is being looked for, and a suite that collected no tests reads exactly like a healthy one' \
  expect caught 'accepted an empty marker set'

defect 'blind' 't.sh' \
  'set -uo pipefail' \
  'set -u' \
  'a suite that exited 7 is reported as a pass, because the status acted on belongs to the pipe and not to the command' \
  --and 't.sh' "$(
    cat <<'EOF'
  # line would already read empty.
  local -a ps=("${PIPESTATUS[@]}")
EOF
  )" "$(
    cat <<'EOF'
  # line would already read empty.
  local -a ps=($?)
EOF
  )" \
  --and 't.sh' "$(
    cat <<'EOF'
  T_LOGDIR="$logdir" git bisect run "$SELF" bisect-probe "${pass[@]+"${pass[@]}"}" "$@" 2>&1 | tee "$out"
  local -a ps=("${PIPESTATUS[@]}")
EOF
  )" "$(
    cat <<'EOF'
  T_LOGDIR="$logdir" git bisect run "$SELF" bisect-probe "${pass[@]+"${pass[@]}"}" "$@" 2>&1 | tee "$out"
  local -a ps=($?)
EOF
  )" \
  expect caught 'for a command that exited 7'

defect 'undocumented' 't.sh' \
  '  run) cmd_run "$@" ;;' \
  "$(
    cat <<'EOF'
  run) cmd_run "$@" ;;
  wat) cmd_run "$@" ;;
EOF
  )" \
  'a subcommand nobody can find: the help is the only reference anyone reads, and what it leaves out does not exist for whoever runs the tool' \
  expect caught "its help never mentions 't.sh wat'"

defect 'undocumented-flag' 't.sh' \
  'cmd_focused() { # focused [--any-file] [PATH...]' \
  'cmd_focused() { # focused [--anyfile] [PATH...]' \
  'a flag the parser accepts and the help never names, so the only way to learn it is reading the source' \
  --and 't.sh' '# --any-file is for a list that knows better.' '# --anyfile is for a list that knows better.' \
  --and 't.sh' "$(
    cat <<'EOF'
        die "falsify: ${DEF_NAME[$i]} edits $candidate, which looks like a test, vendored or generated file, or one the policy's tests names — a defect there proves nothing about the suite (--any-file if the list knows better)"
EOF
  )" "$(
    cat <<'EOF'
        die "falsify: ${DEF_NAME[$i]} edits $candidate, which looks like a test, vendored or generated file, or one the policy's tests names — a defect there proves nothing about the suite (--anyfile if the list knows better)"
EOF
  )" \
  --and 't.sh' '    die "prove: $ref changes no source file, only ${#tests[@]} test file(s) — there is no fix to take away (--any-file counts every file)"' '    die "prove: $ref changes no source file, only ${#tests[@]} test file(s) — there is no fix to take away (--anyfile counts every file)"' \
  --and 't.sh' '  t.sh focused [--any-file] [PATH...]  is a `.only` left in the source, so most of the suite is skipped' '  t.sh focused [--anyfile] [PATH...]  is a `.only` left in the source, so most of the suite is skipped' \
  --and 't.sh' 't.sh focused [--any-file] [PATH...]' 't.sh focused [--anyfile] [PATH...]' \
  --and 't.sh' '  --any-file          look inside node_modules, vendor, third_party, dist, build and' '  --anyfile          look inside node_modules, vendor, third_party, dist, build and' \
  --and 't.sh' 't.sh falsify [-d FILE] [-b BUILD] [--timeout SECONDS] [--out DIR] [--since REF] [--shard I/N] [--worktree] [--any-file] [-l DIR] [-m SET] [-p PATTERN] [-t N] [FILTER] -- CMD...' 't.sh falsify [-d FILE] [-b BUILD] [--timeout SECONDS] [--out DIR] [--since REF] [--shard I/N] [--worktree] [--anyfile] [-l DIR] [-m SET] [-p PATTERN] [-t N] [FILTER] -- CMD...' \
  --and 't.sh' '  --any-file          allow a defect in a test, vendored or generated file, which is' '  --anyfile          allow a defect in a test, vendored or generated file, which is' \
  --and 't.sh' 't.sh prove [-b BUILD] [--timeout SECONDS] [--worktree] [--any-file] [-l DIR] [-m SET] [-p PATTERN] [-t N] [REF] -- CMD...' 't.sh prove [-b BUILD] [--timeout SECONDS] [--worktree] [--anyfile] [-l DIR] [-m SET] [-p PATTERN] [-t N] [REF] -- CMD...' \
  --and 't.sh' '`tests` among them, stay and the rest is the fix; --any-file counts everything as the fix.' '`tests` among them, stay and the rest is the fix; --anyfile counts everything as the fix.' \
  expect caught 'never mentions it'

defect 'undocumented-variable' 't.sh' \
  '  T_LOGFILE    one log file for one run, instead of a name chosen under the log directory' \
  '  T_LOGFLIE    one log file for one run, instead of a name chosen under the log directory' \
  'a variable that changes what a run does and appears in no help, so runs differ for reasons nobody can look up' \
  expect caught 'never mentions it'

defect 'undocumented-code' 't.sh' \
  '  86  the runs disagreed with each other (flaky)' \
  '  68  the runs disagreed with each other (flaky)' \
  'an exit code CI branches on that the help never lists, so a pipeline meets it as an unknown failure and stops for the wrong reason' \
  expect caught 'never lists it'

defect 'raw' 't.sh' \
  '        *) return 1 ;;' \
  '        *) return "$status" ;; # planted' \
  'git bisect is handed a status it reads as "cannot test", so a history with an interrupted probe in it bisects to the wrong commit' \
  expect caught 'should be 1 to git bisect'

defect 'trailing' 't.sh' \
  '  __content=$(cat "$2" && printf x) || return 1' \
  '  __content=$(cat "$2") || return 1' \
  'every falsification leaves the working tree dirty by one byte, and the next run refuses to start over changes nobody made' \
  expect caught 'byte for byte'

defect 'badallow' 't.sh' \
  "$(
    cat <<'EOF'
    [[ -z "$complaint" ]] || die "allow: '$allow' is not a regex grep -E accepts — $complaint"
EOF
  )" \
  '    : "$complaint" # planted' \
  'an allow pattern grep cannot compile excuses nothing at all, and the lines it was written for redden every run afterwards' \
  expect caught 'grep cannot compile'

defect 'carryon' 't.sh' \
  "$(
    cat <<'EOF'
  # terminal does not reach, so the group is ended first
  trap 'restore_all; cleanup_worktree' EXIT
  trap 'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$' INT
EOF
  )" \
  "$(
    cat <<'EOF'
  # terminal does not reach, so the group is ended first
  trap 'restore_all; cleanup_worktree' EXIT
  trap 'end_mutant; restore_all' INT
EOF
  )" \
  'Ctrl-C leaves the run going: the interrupted defect drops out of the report while still counted in the summary, which then claims more than was measured' \
  --and 't.sh' "$(
    cat <<'EOF'
  }
  trap 'restore_all; cleanup_worktree' EXIT
  trap 'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$' INT
EOF
  )" "$(
    cat <<'EOF'
  }
  trap 'restore_all; cleanup_worktree' EXIT
  trap 'end_mutant; restore_all' INT
EOF
  )" \
  expect caught 'carried on after an interrupt'

defect 'unrestored' 't.sh' \
  "$(
    cat <<'EOF'
  # terminal does not reach, so the group is ended first
  trap 'restore_all; cleanup_worktree' EXIT
  trap 'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$' INT
  trap 'end_mutant; restore_all; cleanup_worktree; trap - TERM; kill -TERM $$' TERM
EOF
  )" \
  "$(
    cat <<'EOF'
  # terminal does not reach, so the group is ended first
  trap 'cleanup_worktree' EXIT
  trap 'end_mutant; cleanup_worktree; trap - INT; kill -INT $$' INT
  trap 'end_mutant; cleanup_worktree; trap - TERM; kill -TERM $$' TERM
EOF
  )" \
  'an interrupted run leaves a mutant on disk, and every suite after it measures code nobody wrote' \
  --and 't.sh' "$(
    cat <<'EOF'
  }
  trap 'restore_all; cleanup_worktree' EXIT
  trap 'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$' INT
  trap 'end_mutant; restore_all; cleanup_worktree; trap - TERM; kill -TERM $$' TERM
EOF
  )" "$(
    cat <<'EOF'
  }
  trap 'cleanup_worktree' EXIT
  trap 'end_mutant; cleanup_worktree; trap - INT; kill -INT $$' INT
  trap 'end_mutant; cleanup_worktree; trap - TERM; kill -TERM $$' TERM
EOF
  )" \
  expect caught 'did not put impl.sh back'

defect 'unbisected' 't.sh' \
  '  ((head_verdict != 0)) || {' \
  '  ((head_verdict != 999)) || {' \
  'bisect names the first commit it happens to try as the culprit, over a history where nothing is broken at all' \
  expect caught 'over a history where every commit passes'

defect 'unpremised' 't.sh' \
  '  ((st == 0)) || {' \
  '  true || {' \
  'a test that fails on its own is reported as poisoned by another one, and the hunt goes to a file that was never involved' \
  expect caught 'on a victim that fails by itself'

defect 'halfblind' 't.sh' \
  '    elif fails_after "${right[@]}"; then' \
  '    elif true; then' \
  'a pollution that needs two tests together is reported as one, so removing the named test changes nothing and the report is trusted anyway' \
  expect caught 'exited 0 where two tests'

defect 'unexpired' 't.sh' \
  '      if (cell[ecol] < today) {' \
  '      if (0) {' \
  'a test taken out of the gate stays out forever, because the date somebody promised to come back by is never looked at' \
  expect caught 'did not name the row past its expiry'

defect 'undated-ok' 't.sh' \
  '      if (cell[ecol] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {' \
  '      if (0) { # planted' \
  'a quarantine entry whose expiry is not a date can never come up for review, and the debt stops being visible to anyone' \
  expect caught 'can never come up for review'

defect 'blindscan' 't.sh' \
  "$(
    cat <<'EOF'
  cat <<'FOCUS'
EOF
  )" \
  "$(
    cat <<'EOF'
  : <<'FOCUS'
EOF
  )" \
  'focused reports a clean tree because it searched for nothing, and a file running one of its tests passes as a full suite' \
  expect caught 'exited 70 on a tree'

defect 'unfocused' 't.sh' \
  '  return 80' \
  '  return 0' \
  'a focused modifier left in the source is found and the run still exits 0, so CI merges a suite that ran a single test' \
  expect caught 'exited 0 on a tree'

defect 'miscredited' 't.sh' \
  '      grep -qF -- "$expect" "$out/logs/$(log_name "$name").log" || VERDICT=misattributed' \
  '      : # planted' \
  'one flaky test failing through a whole run credits every defect to a suite that noticed none of them' \
  expect caught 'was still called caught'

defect 'unrecorded' 't.sh' \
  "$(
    cat <<'EOF'
    printf '%s\n' "$2" >>"$out/$list.txt"
EOF
  )" \
  '    : "$out/$list.txt" # planted' \
  'CI has nothing to diff or grep, so a survivor that appeared between two runs goes unnoticed' \
  expect caught '.txt does not name'

defect 'vacuous' 't.sh' \
  "$(
    cat <<'EOF'
      printf '%s' "${befores[$i]}" >"${src[$i]}" || fatal "prove: cannot write ${src[$i]} — nothing was measured"
EOF
  )" \
  '      : # planted' \
  'a commit whose tests pin nothing is reported proven, and the one discipline this command exists for stops meaning anything' \
  expect caught 'want proven'

defect 'leftover' 't.sh' \
  '  git -C "$WORKTREE_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || :' \
  '  : # planted' \
  'every run leaves a checkout behind, and the disk fills with trees nobody can trace back to what made them' \
  expect caught 'left a worktree behind'

defect 'unsince' 't.sh' \
  "$(
    cat <<'EOF'
    printf 'nothing to falsify: no defect names a file changed since %s — this is a filter, not a proof; run the full list on the default branch\n' "$since"
EOF
  )" \
  '    : # planted' \
  'a pull request reports a green falsification that ran no defect at all' \
  expect caught 'ran nothing and did not say so'

defect 'shard-overlap' 't.sh' \
  '    for ((s = shard_i - 1; s < ${#whole[@]}; s += shard_n)); do' \
  '    for ((s = shard_i - 1; s < ${#whole[@]}; s += 1)); do' \
  'the matrix runs the same defects in every shard and reports the whole list covered while part of it was never reached' \
  expect caught 'in more than one of them'

defect 'shard-gap' 't.sh' \
  '    for ((s = shard_i - 1; s < ${#whole[@]}; s += shard_n)); do' \
  '    for ((s = shard_i; s < ${#whole[@]}; s += shard_n)); do' \
  'a defect falls out of every shard, so the list is reported covered while that entry was never run once' \
  expect caught 'not the whole list'

defect 'unannotated' 't.sh' \
  '        annotate error "$file" "$line" "SURVIVED $name: $why"' \
  '        : # planted' \
  'a survivor sits in a log nobody opens instead of on the line somebody is about to merge' \
  expect caught 'did not annotate the survivor'

defect 'unexpected' 't.sh' \
  '    if [[ "$expect_kind" == survived ]]; then' \
  '    if false; then # planted' \
  'an exception that has outlived its truth is reported as a finding, and a report with false findings in it trains everyone to skim' \
  expect caught 'was reported as a survivor'

defect 'nowhere' 't.sh' \
  "$(
    cat <<'EOF'
            printf '          %s:%s  - %s\n' "$file" "$line" "${find%%$'\n'*}"
EOF
  )" \
  '' \
  'a finding names the file but not the place, so closing it begins with a search through the file' \
  --and 't.sh' "$(
    cat <<'EOF'
      printf '  - %s\n' "${src[$i]}"
EOF
  )" '' \
  expect caught 'where the edit is'

defect 'anyfile' 't.sh' \
  '        looks_like_test_file "$candidate" || continue' \
  '        continue # planted' \
  'a defect aimed at a test file is caught by whatever it breaks and reads as coverage the suite does not have' \
  expect caught 'aimed at a test file'

defect 'nodeadline' 't.sh' \
  '    if [[ -n "$deadline" ]] && ((waited >= deadline * 10)); then' \
  '    if false; then # planted' \
  'a mutant that loops forever hangs the run until a CI timeout kills it with no name attached to the failure' \
  expect caught 'nothing timed it out'

defect 'surrender' 't.sh' \
  '    return 89' \
  '    return 0 # planted' \
  'a history where nothing could answer is reported as a culprit found, and the commit it names is innocent' \
  expect caught 'want 89'

defect 'muted' 't.sh' \
  '      >/dev/null 2>"$stamp/run-$i.err" || status=$?' \
  '      >/dev/null 2>/dev/null || status=$?' \
  'a run that refused to start is counted as a stable pass, so the command reports agreement it never measured' \
  expect caught "hid run's refusal"

defect 'anytail' 't.sh' \
  '        (($# >= 2)) || die "run: -t needs a number"' \
  '' \
  'a typo in -t makes the harness read a number it never got, and the tail of the log comes out silently empty' \
  --and 't.sh' "$(
    cat <<'EOF'
        [[ "$tail_n" =~ ^[0-9]+$ ]] || die "run: -t needs a number of lines, got '$tail_n'"
EOF
  )" '' \
  expect caught 'accepted -t abc'

defect 'twice' 't.sh' \
  "$(
    cat <<'EOF'
        resolve_markers "$value"
        add_marker_file "$RESOLVED"
EOF
  )" \
  "$(
    cat <<'EOF'
        resolve_markers "$value"
        MARKER_FILES+=("$RESOLVED")
EOF
  )" \
  'a marker set named twice matches twice, and one lying line in a log is reported as two separate ones' \
  --and 't.sh' "$(
    cat <<'EOF'
        resolve_markers "$2"
        add_marker_file "$RESOLVED"
EOF
  )" "$(
    cat <<'EOF'
        resolve_markers "$2"
        MARKER_FILES+=("$RESOLVED")
EOF
  )" \
  expect caught 'named twice printed'

defect 'leaky' 't.sh' \
  '    unset T_LOGFILE' \
  '    : # planted' \
  "the suite writes into the harness's own log and cuts it short, so the verdict is read from a file that stops mid-run" \
  expect caught "saw the harness's own T_LOGFILE"

defect 'unignored' 't.sh' \
  "$(
    cat <<'EOF'
  mkdir -p "$1" && printf '*\n' >"$1/.gitignore"
EOF
  )" \
  '  mkdir -p "$1" # planted' \
  "git add -A picks the logs up, and they land in somebody's commit" \
  expect caught 'shows up in git status'

defect 'overreach' 't.sh' \
  '  [[ -d "$1" ]] && return 0' \
  '  : # planted' \
  "the harness writes a .gitignore into a directory it did not create, changing a repository's own rules behind its back" \
  expect caught 'a directory it did not create'

defect 'policy-tests' 't.sh' \
  '    [[ "$1" == $glob ]] && return 0' \
  '    : # planted' \
  "a repository's own gate is treated as code, so prove takes the commit's new checks away together with the fix it was proving and reports VACUOUS" \
  expect caught 'the policy names a test'

defect 'falsify-policy' 't.sh' \
  '    load_config' \
  '    : # planted' \
  "a defect aimed at a repository's own gate is accepted, and the run measures the gate breaking itself rather than the suite noticing anything" \
  expect caught 'the policy names a test'

defect 'prove-policy' 't.sh' \
  "$(
    cat <<'EOF'
  POLICY_TESTS=()
  load_config
EOF
  )" \
  "$(
    cat <<'EOF'
  POLICY_TESTS=()
  : # planted
EOF
  )" \
  'prove splits a commit before it knows which files the policy calls tests, so a real fix is reported VACUOUS while its tests were removed along with it' \
  expect caught "on a fix the policy's tests pin"

defect 'unresolved' 't.sh' \
  'while [[ -L "$self" ]]; do' \
  'while false; do' \
  'a harness reached through a symlink looks for its markers beside the link, finds none, and refuses every run' \
  expect caught 'through the symlink'

defect 'nosidecar' 't.sh' \
  "$(
    cat <<'EOF'
  printf '%s\n' "$RUN_VERDICT" >"$log.verdict"
EOF
  )" \
  "$(
    cat <<'EOF'
  printf '%s\n' "$RUN_VERDICT" >/dev/null
EOF
  )" \
  'the kind of verdict is lost, so a refusal and a genuine failure are the same number to whoever reads the result' \
  expect caught 'did not record'

defect 'nolog' 't.sh' \
  '  : >"$log" || fatal "run: cannot write $log"' \
  '' \
  'a run whose log cannot be written carries on and reports a pass that nobody is able to check' \
  expect caught 'nowhere to put its log'

defect 'unwritten' 't.sh' \
  "$(
    cat <<'EOF'
      printf '%s' "$mutated" >"$file" || fatal "falsify: cannot write $file — the tree is untouched, and nothing was measured"
EOF
  )" \
  "$(
    cat <<'EOF'
      printf '%s' "$mutated" >"$file" # planted
EOF
  )" \
  'a read-only file leaves the pristine code in place, the suite passes against it, and a guard the suite does cover is reported as one nobody checks' \
  expect caught 'could not write'
