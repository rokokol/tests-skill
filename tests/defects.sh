#!/usr/bin/env bash
# The defect list for this repository, read by `t.sh falsify`. Every entry breaks one guard
# on purpose and requires this repository's own gate to notice it.
#
# The names are grouped by the half of the gate that has to do the catching, because one
# run of falsify knows one suite command and the two halves need different ones:
#
#   ./t.sh falsify --worktree behaviour/ -- env T_CHECK_NESTED=1 ./check.sh behaviour
#   nix develop -c ./t.sh falsify --worktree lint/ -- env T_CHECK_NESTED=1 ./check.sh lint
#
# --worktree is not optional for the behaviour half. The file being edited is the harness
# running the edit: bash reads a script as it executes it, so a mutant written into the
# t.sh in front of you can be read by the very run applying it. A worktree gives the mutant
# a file of its own.
#
# T_CHECK_NESTED=1 leaves out the gate's own planted-defect pass, which would otherwise run
# inside every mutant, proving a t.sh this list has already broken.
#
# Each entry names what should do the catching with `expect caught`, so a red run is only
# credited to the guard whose failure message is actually in it.
#
# Six plants stay in check.sh rather than moving here. noisy-awk edits check.sh, which is
# the suite: a defect in the suite is "caught" by the suite falling over, which proves
# nothing. no-healthy-run, dupe and noisy-elsewhere edit fixtures under tests/, which
# falsify refuses — and --any-file is a flag for the whole run, so allowing them would drop
# that refusal for every other entry. bash4-declare and bash4-mapfile are planted only
# where CHECK_BASH32 says the interpreter is the 3.2 macOS ships, and a list has no way to
# say "only where the bash is old".

defect 'behaviour/crlf' 't.sh' \
  '  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'"'"'\r'"'"'}"' \
  '  while IFS= read -r line || [[ -n "$line" ]]; do' \
  'a repository whose marker files carry Windows line endings has every healthy run reported as a failure, and the team learns to disbelieve the verdict' \
  --and 't.sh' '    # CRLF would otherwise carry a carriage return into every value
    line="${line%$'"'"'\r'"'"'}"' '    # CRLF would otherwise carry a carriage return into every value' \
  expect caught 'reddened a healthy CRLF run'

defect 'behaviour/lenient' 't.sh' \
  '      *) die "config: $conf:$n — unknown key '"'"'$key'"'"' (markers, pattern, allow, logdir, tests)" ;;' \
  '      *) : ;;' \
  'a typo in tests/t.conf silently switches off the policy it names, and every run afterwards believes in markers that were never loaded' \
  expect caught 'unknown key'

defect 'behaviour/subshell' 't.sh' \
  '  load_markers' \
  '  MARKER_PATTERNS=()' \
  'every run passes because nothing is being looked for, and a suite that collected no tests reads exactly like a healthy one' \
  expect caught 'accepted an empty marker set'

defect 'behaviour/blind' 't.sh' \
  'set -uo pipefail' \
  'set -u' \
  'a suite that exited 7 is reported as a pass, because the status acted on belongs to the pipe and not to the command' \
  --and 't.sh' '  # line would already read empty.
  local -a ps=("${PIPESTATUS[@]}")' '  # line would already read empty.
  local -a ps=($?)' \
  --and 't.sh' '  T_LOGDIR="$logdir" git bisect run "$SELF" bisect-probe "${pass[@]+"${pass[@]}"}" "$@" 2>&1 | tee "$out"
  local -a ps=("${PIPESTATUS[@]}")' '  T_LOGDIR="$logdir" git bisect run "$SELF" bisect-probe "${pass[@]+"${pass[@]}"}" "$@" 2>&1 | tee "$out"
  local -a ps=($?)' \
  expect caught 'for a command that exited 7'

defect 'behaviour/undocumented' 't.sh' \
  '  run) cmd_run "$@" ;;' \
  '  run) cmd_run "$@" ;;
  wat) cmd_run "$@" ;;' \
  'a subcommand nobody can find: the help is the only reference anyone reads, and what it leaves out does not exist for whoever runs the tool' \
  expect caught "its help never mentions 't.sh wat'"

defect 'behaviour/undocumented-flag' 't.sh' \
  'cmd_focused() { # focused [--any-file] [PATH...]' \
  'cmd_focused() { # focused [--anyfile] [PATH...]' \
  'a flag the parser accepts and the help never names, so the only way to learn it is reading the source' \
  --and 't.sh' '# --any-file is for a list that knows better.' '# --anyfile is for a list that knows better.' \
  --and 't.sh' '        die "falsify: ${DEF_NAME[$i]} edits $candidate, which looks like a test, vendored or generated file, or one the policy'"'"'s tests names — a defect there proves nothing about the suite (--any-file if the list knows better)"' '        die "falsify: ${DEF_NAME[$i]} edits $candidate, which looks like a test, vendored or generated file, or one the policy'"'"'s tests names — a defect there proves nothing about the suite (--anyfile if the list knows better)"' \
  --and 't.sh' '    die "prove: $ref changes no source file, only ${#tests[@]} test file(s) — there is no fix to take away (--any-file counts every file)"' '    die "prove: $ref changes no source file, only ${#tests[@]} test file(s) — there is no fix to take away (--anyfile counts every file)"' \
  --and 't.sh' '  t.sh focused [--any-file] [PATH...]  is a `.only` left in the source, so most of the suite is skipped' '  t.sh focused [--anyfile] [PATH...]  is a `.only` left in the source, so most of the suite is skipped' \
  --and 't.sh' 't.sh focused [--any-file] [PATH...]' 't.sh focused [--anyfile] [PATH...]' \
  --and 't.sh' '  --any-file          look inside node_modules, vendor, third_party, dist, build and' '  --anyfile          look inside node_modules, vendor, third_party, dist, build and' \
  --and 't.sh' 't.sh falsify [-d FILE] [-b BUILD] [--timeout SECONDS] [--out DIR] [--since REF] [--shard I/N] [--worktree] [--any-file] [-l DIR] [-m SET] [-p PATTERN] [-t N] [FILTER] -- CMD...' 't.sh falsify [-d FILE] [-b BUILD] [--timeout SECONDS] [--out DIR] [--since REF] [--shard I/N] [--worktree] [--anyfile] [-l DIR] [-m SET] [-p PATTERN] [-t N] [FILTER] -- CMD...' \
  --and 't.sh' '  --any-file          allow a defect in a test, vendored or generated file, which is' '  --anyfile          allow a defect in a test, vendored or generated file, which is' \
  --and 't.sh' 't.sh prove [-b BUILD] [--timeout SECONDS] [--worktree] [--any-file] [-l DIR] [-m SET] [-p PATTERN] [-t N] [REF] -- CMD...' 't.sh prove [-b BUILD] [--timeout SECONDS] [--worktree] [--anyfile] [-l DIR] [-m SET] [-p PATTERN] [-t N] [REF] -- CMD...' \
  --and 't.sh' '`tests` among them, stay and the rest is the fix; --any-file counts everything as the fix.' '`tests` among them, stay and the rest is the fix; --anyfile counts everything as the fix.' \
  expect caught 'never mentions it'

defect 'behaviour/undocumented-variable' 't.sh' \
  '  T_LOGFILE    one log file for one run, instead of a name chosen under the log directory' \
  '  T_LOGFLIE    one log file for one run, instead of a name chosen under the log directory' \
  'a variable that changes what a run does and appears in no help, so runs differ for reasons nobody can look up' \
  expect caught 'never mentions it'

defect 'behaviour/undocumented-code' 't.sh' \
  '  86  the runs disagreed with each other (flaky)' \
  '  68  the runs disagreed with each other (flaky)' \
  'an exit code CI branches on that the help never lists, so a pipeline meets it as an unknown failure and stops for the wrong reason' \
  expect caught 'never lists it'

defect 'behaviour/raw' 't.sh' \
  '        *) return 1 ;;' \
  '        *) return "$status" ;; # planted' \
  'git bisect is handed a status it reads as "cannot test", so a history with an interrupted probe in it bisects to the wrong commit' \
  expect caught 'should be 1 to git bisect'

defect 'behaviour/trailing' 't.sh' \
  '  __content=$(cat "$2" && printf x) || return 1' \
  '  __content=$(cat "$2") || return 1' \
  'every falsification leaves the working tree dirty by one byte, and the next run refuses to start over changes nobody made' \
  expect caught 'byte for byte'

defect 'behaviour/badallow' 't.sh' \
  '    [[ -z "$complaint" ]] || die "allow: '"'"'$allow'"'"' is not a regex grep -E accepts — $complaint"' \
  '    : "$complaint" # planted' \
  'an allow pattern grep cannot compile excuses nothing at all, and the lines it was written for redden every run afterwards' \
  expect caught 'grep cannot compile'

defect 'behaviour/carryon' 't.sh' \
  '  # terminal does not reach, so the group is ended first
  trap '"'"'restore_all; cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$'"'"' INT' \
  '  # terminal does not reach, so the group is ended first
  trap '"'"'restore_all; cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; restore_all'"'"' INT' \
  'Ctrl-C leaves the run going: the interrupted defect drops out of the report while still counted in the summary, which then claims more than was measured' \
  --and 't.sh' '  }
  trap '"'"'restore_all; cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$'"'"' INT' '  }
  trap '"'"'restore_all; cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; restore_all'"'"' INT' \
  expect caught 'carried on after an interrupt'

defect 'behaviour/unrestored' 't.sh' \
  '  # terminal does not reach, so the group is ended first
  trap '"'"'restore_all; cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$'"'"' INT
  trap '"'"'end_mutant; restore_all; cleanup_worktree; trap - TERM; kill -TERM $$'"'"' TERM' \
  '  # terminal does not reach, so the group is ended first
  trap '"'"'cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; cleanup_worktree; trap - INT; kill -INT $$'"'"' INT
  trap '"'"'end_mutant; cleanup_worktree; trap - TERM; kill -TERM $$'"'"' TERM' \
  'an interrupted run leaves a mutant on disk, and every suite after it measures code nobody wrote' \
  --and 't.sh' '  }
  trap '"'"'restore_all; cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT $$'"'"' INT
  trap '"'"'end_mutant; restore_all; cleanup_worktree; trap - TERM; kill -TERM $$'"'"' TERM' '  }
  trap '"'"'cleanup_worktree'"'"' EXIT
  trap '"'"'end_mutant; cleanup_worktree; trap - INT; kill -INT $$'"'"' INT
  trap '"'"'end_mutant; cleanup_worktree; trap - TERM; kill -TERM $$'"'"' TERM' \
  expect caught 'did not put impl.sh back'

defect 'behaviour/unbisected' 't.sh' \
  '  ((head_verdict != 0)) || {' \
  '  ((head_verdict != 999)) || {' \
  'bisect names the first commit it happens to try as the culprit, over a history where nothing is broken at all' \
  expect caught 'over a history where every commit passes'

defect 'behaviour/unpremised' 't.sh' \
  '  ((st == 0)) || {' \
  '  true || {' \
  'a test that fails on its own is reported as poisoned by another one, and the hunt goes to a file that was never involved' \
  expect caught 'on a victim that fails by itself'

defect 'behaviour/halfblind' 't.sh' \
  '    elif fails_after "${right[@]}"; then' \
  '    elif true; then' \
  'a pollution that needs two tests together is reported as one, so removing the named test changes nothing and the report is trusted anyway' \
  expect caught 'exited 0 where two tests'

defect 'behaviour/unexpired' 't.sh' \
  '      if (cell[ecol] < today) {' \
  '      if (0) {' \
  'a test taken out of the gate stays out forever, because the date somebody promised to come back by is never looked at' \
  expect caught 'did not name the row past its expiry'

defect 'behaviour/undated-ok' 't.sh' \
  '      if (cell[ecol] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {' \
  '      if (0) { # planted' \
  'a quarantine entry whose expiry is not a date can never come up for review, and the debt stops being visible to anyone' \
  expect caught 'can never come up for review'

defect 'behaviour/blindscan' 't.sh' \
  '  cat <<'"'"'FOCUS'"'"'' \
  '  : <<'"'"'FOCUS'"'"'' \
  'focused reports a clean tree because it searched for nothing, and a file running one of its tests passes as a full suite' \
  expect caught 'exited 70 on a tree'

defect 'behaviour/unfocused' 't.sh' \
  '  return 80' \
  '  return 0' \
  'a focused modifier left in the source is found and the run still exits 0, so CI merges a suite that ran a single test' \
  expect caught 'exited 0 on a tree'

defect 'behaviour/miscredited' 't.sh' \
  '      grep -qF -- "$expect" "$out/logs/$(log_name "$name").log" || VERDICT=misattributed' \
  '      : # planted' \
  'one flaky test failing through a whole run credits every defect to a suite that noticed none of them' \
  expect caught 'was still called caught'

defect 'behaviour/unrecorded' 't.sh' \
  '    printf '"'"'%s\n'"'"' "$2" >>"$out/$list.txt"' \
  '    : "$out/$list.txt" # planted' \
  'CI has nothing to diff or grep, so a survivor that appeared between two runs goes unnoticed' \
  expect caught '.txt does not name'

defect 'behaviour/vacuous' 't.sh' \
  '      printf '"'"'%s'"'"' "${befores[$i]}" >"${src[$i]}" || fatal "prove: cannot write ${src[$i]} — nothing was measured"' \
  '      : # planted' \
  'a commit whose tests pin nothing is reported proven, and the one discipline this command exists for stops meaning anything' \
  expect caught 'want proven'

defect 'behaviour/leftover' 't.sh' \
  '  git -C "$WORKTREE_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || :' \
  '  : # planted' \
  'every run leaves a checkout behind, and the disk fills with trees nobody can trace back to what made them' \
  expect caught 'left a worktree behind'

defect 'behaviour/unsince' 't.sh' \
  '    printf '"'"'nothing to falsify: no defect names a file changed since %s — this is a filter, not a proof; run the full list on the default branch\n'"'"' "$since"' \
  '    : # planted' \
  'a pull request reports a green falsification that ran no defect at all' \
  expect caught 'ran nothing and did not say so'

defect 'behaviour/shard-overlap' 't.sh' \
  '    for ((s = shard_i - 1; s < ${#whole[@]}; s += shard_n)); do' \
  '    for ((s = shard_i - 1; s < ${#whole[@]}; s += 1)); do' \
  'the matrix runs the same defects in every shard and reports the whole list covered while part of it was never reached' \
  expect caught 'in more than one of them'

defect 'behaviour/shard-gap' 't.sh' \
  '    for ((s = shard_i - 1; s < ${#whole[@]}; s += shard_n)); do' \
  '    for ((s = shard_i; s < ${#whole[@]}; s += shard_n)); do' \
  'a defect falls out of every shard, so the list is reported covered while that entry was never run once' \
  expect caught 'not the whole list'

defect 'behaviour/unannotated' 't.sh' \
  '        annotate error "$file" "$line" "SURVIVED $name: $why"' \
  '        : # planted' \
  'a survivor sits in a log nobody opens instead of on the line somebody is about to merge' \
  expect caught 'did not annotate the survivor'

defect 'behaviour/unexpected' 't.sh' \
  '    if [[ "$expect_kind" == survived ]]; then' \
  '    if false; then # planted' \
  'an exception that has outlived its truth is reported as a finding, and a report with false findings in it trains everyone to skim' \
  expect caught 'was reported as a survivor'

defect 'behaviour/nowhere' 't.sh' \
  '            printf '"'"'          %s:%s  - %s\n'"'"' "$file" "$line" "${find%%$'"'"'\n'"'"'*}"' \
  '' \
  'a finding names the file but not the place, so closing it begins with a search through the file' \
  --and 't.sh' '      printf '"'"'  - %s\n'"'"' "${src[$i]}"' '' \
  expect caught 'where the edit is'

defect 'behaviour/anyfile' 't.sh' \
  '        looks_like_test_file "$candidate" || continue' \
  '        continue # planted' \
  'a defect aimed at a test file is caught by whatever it breaks and reads as coverage the suite does not have' \
  expect caught 'aimed at a test file'

defect 'behaviour/nodeadline' 't.sh' \
  '  if [[ -n "$deadline" ]]; then' \
  '  if false; then # planted' \
  'a mutant that loops forever hangs the run until a CI timeout kills it with no name attached to the failure' \
  expect caught 'nothing timed it out'

defect 'behaviour/watchdogheld' 't.sh' \
  '    [[ -e "$log.timedout" ]] || kill -KILL -- -"$WATCHDOG_PGID" 2>/dev/null || :' \
  '    : # planted' \
  'the run waits on a watchdog nobody ended, which wakes at the deadline and reports every defect timed out, the caught ones included' \
  expect caught 'exited 84 where a defect went unnoticed'

defect 'behaviour/watchdogorphan' 't.sh' \
  '  [[ -z "$WATCHDOG_PGID" ]] || kill -KILL -- -"$WATCHDOG_PGID" 2>/dev/null || :' \
  '  : # planted' \
  'an interrupted run leaves its watchdog asleep, to wake at the deadline and signal whatever process group has that id by then' \
  expect caught 'left its watchdog asleep'

defect 'behaviour/surrender' 't.sh' \
  '    return 89' \
  '    return 0 # planted' \
  'a history where nothing could answer is reported as a culprit found, and the commit it names is innocent' \
  expect caught 'want 89'

defect 'behaviour/muted' 't.sh' \
  '      >/dev/null 2>"$stamp/run-$i.err" || status=$?' \
  '      >/dev/null 2>/dev/null || status=$?' \
  'a run that refused to start is counted as a stable pass, so the command reports agreement it never measured' \
  expect caught "hid run's refusal"

defect 'behaviour/anytail' 't.sh' \
  '        (($# >= 2)) || die "run: -t needs a number"' \
  '' \
  'a typo in -t makes the harness read a number it never got, and the tail of the log comes out silently empty' \
  --and 't.sh' '        [[ "$tail_n" =~ ^[0-9]+$ ]] || die "run: -t needs a number of lines, got '"'"'$tail_n'"'"'"' '' \
  expect caught 'accepted -t abc'

defect 'behaviour/twice' 't.sh' \
  '        resolve_markers "$value"
        add_marker_file "$RESOLVED"' \
  '        resolve_markers "$value"
        MARKER_FILES+=("$RESOLVED")' \
  'a marker set named twice matches twice, and one lying line in a log is reported as two separate ones' \
  --and 't.sh' '        resolve_markers "$2"
        add_marker_file "$RESOLVED"' '        resolve_markers "$2"
        MARKER_FILES+=("$RESOLVED")' \
  expect caught 'named twice printed'

defect 'behaviour/leaky' 't.sh' \
  '    unset T_LOGFILE' \
  '    : # planted' \
  "the suite writes into the harness's own log and cuts it short, so the verdict is read from a file that stops mid-run" \
  expect caught "saw the harness's own T_LOGFILE"

defect 'behaviour/unignored' 't.sh' \
  '  mkdir -p "$1" && printf '"'"'*\n'"'"' >"$1/.gitignore"' \
  '  mkdir -p "$1" # planted' \
  "git add -A picks the logs up, and they land in somebody's commit" \
  expect caught 'shows up in git status'

defect 'behaviour/overreach' 't.sh' \
  '  [[ -d "$1" ]] && return 0' \
  '  : # planted' \
  "the harness writes a .gitignore into a directory it did not create, changing a repository's own rules behind its back" \
  expect caught 'a directory it did not create'

defect 'behaviour/policy-tests' 't.sh' \
  '    [[ "$1" == $glob ]] && return 0' \
  '    : # planted' \
  "a repository's own gate is treated as code, so prove takes the commit's new checks away together with the fix it was proving and reports VACUOUS" \
  expect caught 'the policy names a test'

defect 'behaviour/falsify-policy' 't.sh' \
  '    load_config' \
  '    : # planted' \
  "a defect aimed at a repository's own gate is accepted, and the run measures the gate breaking itself rather than the suite noticing anything" \
  expect caught 'the policy names a test'

defect 'behaviour/prove-policy' 't.sh' \
  '  POLICY_TESTS=()
  load_config' \
  '  POLICY_TESTS=()
  : # planted' \
  'prove splits a commit before it knows which files the policy calls tests, so a real fix is reported VACUOUS while its tests were removed along with it' \
  expect caught "on a fix the policy's tests pin"

defect 'behaviour/unresolved' 't.sh' \
  'while [[ -L "$self" ]]; do' \
  'while false; do' \
  'a harness reached through a symlink looks for its markers beside the link, finds none, and refuses every run' \
  expect caught 'through the symlink'

defect 'behaviour/nosidecar' 't.sh' \
  '  printf '"'"'%s\n'"'"' "$RUN_VERDICT" >"$log.verdict"' \
  '  printf '"'"'%s\n'"'"' "$RUN_VERDICT" >/dev/null' \
  'the kind of verdict is lost, so a refusal and a genuine failure are the same number to whoever reads the result' \
  expect caught 'did not record'

defect 'behaviour/nolog' 't.sh' \
  '  : >"$log" || fatal "run: cannot write $log"' \
  '' \
  'a run whose log cannot be written carries on and reports a pass that nobody is able to check' \
  expect caught 'nowhere to put its log'

defect 'behaviour/unwritten' 't.sh' \
  '        fatal "falsify: cannot write ${edit_files[$k]} — the tree holds half of a defect, so restore it from git before doing anything else"' \
  '        : "planted"' \
  'a read-only file leaves the pristine code in place, the suite passes against it, and a guard the suite does cover is reported as one nobody checks' \
  expect caught 'could not write'

defect 'behaviour/quadratic-find' 't.sh' \
  '  __at=$((__hi - ${#__needle}))' \
  '  __at=$((${#__haystack} - ${#__needle} - $(__tail="${__haystack#*"$__needle"}"; printf '"'"'%d'"'"' "${#__tail}")))' \
  'every entry spends seconds finding its own text in a large file before the suite is asked anything, and over a whole list that is most of the time a run takes' \
  expect caught 'costs the square of the file'

plant 'lint/nofront' 'SKILL.md' write $'no frontmatter here\n' \
  'a skill whose frontmatter is gone installs and never loads, and nothing in the repository says a word about it' \
  expect caught 'does not open with a frontmatter block'

plant 'lint/wrapped' 'README.md' append $'\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n' \
  'a hard-wrapped paragraph reflows on GitHub into lines nobody wrote, and the next one-word edit rewrites every line after it' \
  expect caught 'hard-wraps a paragraph'

plant 'lint/wrapped-reference' 'references/verdict.md' append $'\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n' \
  'a reference page drifts to hard wrapping, so every later edit to it produces a diff nobody can read' \
  expect caught 'hard-wraps a paragraph'

plant 'lint/wrapped-unlisted' 'PITFALLS.md' append $'\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n' \
  'a document that no list in the gate names drifts to hard wrapping, because the rule only ever looked at the files somebody remembered to enumerate' \
  expect caught 'hard-wraps a paragraph'

plant 'lint/fullstop' 'references/verdict.md' append $'\n- a list item that ends with a full stop.\n' \
  'the house style goes one line at a time, and the documents stop looking like one voice' \
  expect caught 'ends a line with a full stop'

plant 'lint/fullstop-bold' 'references/verdict.md' append $'\n**A bold rule that ends with a full stop.**\n' \
  'a full stop hides behind closing markup, where a rule that reads the last character of a line never sees it' \
  expect caught 'ends a line with a full stop'

plant 'lint/fullstop-paren' 'references/verdict.md' append $'\nA remark. (A parenthesis that ends with a full stop.)\n' \
  'a full stop sits inside a closing parenthesis and passes the same rule for the same reason' \
  expect caught 'ends a line with a full stop'

plant 'lint/bloated' 'SKILL.md' append $'\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another\n\n- one more rule, and another' \
  'SKILL.md grows into a reference, and an agent that needed the rules reads a page of prose instead' \
  expect caught 'has grown to'

plant 'lint/orphan' 'references/nothing-points-here.md' create '' \
  'a reference nothing links to is never opened and never updated, and it rots where nobody looks' \
  expect caught 'reaches it'

plant 'lint/deadlink' 'SKILL.md' append $'\nSee [the missing one](references/not-a-file.md).\n' \
  'the skill ships a link to a file that does not exist, and whoever follows it gets nothing where a rule should be' \
  expect caught 'which does not exist'

plant 'lint/deadanchor' 'SKILL.md' append $'\nSee [nowhere](references/verdict.md#no-such-heading).\n' \
  'a link points at a heading nobody has, and drops the reader at the top of a page to search by hand' \
  expect caught 'where no heading has that anchor'

plant 'lint/badflag' 'references/verdict.md' append $'\n```sh\nt.sh run -b \'cargo build\' -- cargo test\n```\n' \
  'the documentation shows a flag the parser does not accept, so a command copied out of it exits 64 for the reader' \
  expect caught 'which that subcommand does not accept'

defect 'lint/dead-system' 'flake.nix' \
  '        "aarch64-darwin"' \
  '        "x86_64-darwin"' \
  'the flake claims a system nixpkgs has dropped, and every evaluation for it fails where nobody is watching' \
  expect caught 'cannot be evaluated for'

plant 'lint/dead' 'markers/default.txt' append $'a marker matching nothing\n' \
  'a marker that matches nothing sits in the list looking like a guard, and the lying log it was written for goes straight through' \
  expect caught 'a dead entry guards nothing'

plant 'lint/noisy' 'markers/default.txt' append $'test session starts\n' \
  'a marker fires on a healthy run, every green run is reported red, and the markers stop being believed at all' \
  expect caught 'it would redden healthy runs'

plant 'lint/noisy-ecosystem' 'markers/rust.txt' append $'test result: ok.\n' \
  "an ecosystem's own healthy run is reddened by its own marker set, so that toolchain's runs are all suspect" \
  expect caught 'its own healthy run'

plant 'lint/unproven' 'markers/invented.txt' create $'no tests ran\n' \
  'a marker set nobody has a fixture for ships untested, and whether it matches anything at all is unknown' \
  expect caught 'has no fixture at'

plant 'lint/unwatched' '.github/dependabot.yml' rm \
  'the action pins nobody watches go stale, and workflows keep running a version with a known problem in it' \
  expect caught 'watched by nobody'

plant 'lint/unwatched-actions' '.github/dependabot.yml' write $'version: 2\nupdates:\n  - package-ecosystem: npm\n    directory: /\n    schedule:\n      interval: weekly\n' \
  'dependabot watches something else, so the pins it was added for are never offered an update' \
  expect caught 'does not watch the github-actions'
