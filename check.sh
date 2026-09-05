#!/usr/bin/env bash
# The gate for this repository. It lints what the skill ships and then proves that each
# of its checks can actually go red — a check that has never failed is a decoration, and
# that is the one claim this skill is not allowed to make about itself.
#
# Nothing here touches the network, so it is safe on pull requests.
# Needs: shellcheck, shfmt — from the flake's dev shell, never from whatever the runner has.
#
#   nix develop -c ./check.sh
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# One source of truth for what gets linted. A second copy of this list drifts, and a
# drifted list lies about what was checked.
scripts=(t.sh check.sh templates/defects.sh)

fail() {
  echo "check: $1" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "== the scripts parse and lint"
for s in "${scripts[@]}"; do bash -n "$s"; done
shellcheck "${scripts[@]}"
shfmt -d -i 2 -ci "${scripts[@]}"

echo "== every lie marker catches its fixture, and none of them cries on a healthy run"
# The markers are read OUT of t.sh rather than spelled a second time here: two copies of
# a list disagree within a month, and then the gate is testing the copy.
markers=()
while IFS= read -r m; do markers+=("$m"); done < <(
  sed -n '/^# >>> LIE MARKERS/,/^# <<< LIE MARKERS/p' t.sh |
    sed -n "s/^  '\(.*\)'\$/\1/p"
)
# An extractor that finds nothing must say so rather than read as "all clear"
((${#markers[@]} > 0)) || fail "no markers could be read out of t.sh — the extractor is broken"
for m in "${markers[@]}"; do
  grep -qiF -- "$m" tests/fixtures/lying.log ||
    fail "the marker '$m' matches nothing in tests/fixtures/lying.log — a dead entry guards nothing"
  ! grep -qiF -- "$m" tests/fixtures/clean.log ||
    fail "the marker '$m' fires on tests/fixtures/clean.log — it would redden healthy runs"
done

echo "== run reports the command's own status, where a pipe would report zero"
# The whole reason this harness exists: `cmd | tail` exits 0 for a suite that just failed
status=0
./t.sh run -t 0 -l "$work/logs" -- sh -c 'echo working; exit 7' >/dev/null 2>&1 || status=$?
((status == 7)) || fail "run reported $status for a command that exited 7"
# And the premise still holds: in a shell without pipefail — the default everywhere, and
# what a Makefile recipe or a CI `run:` step gets — that same pipe reports success.
premise=0
(
  set +o pipefail
  sh -c 'echo working; exit 7' | tail -n 1 >/dev/null 2>&1
) || premise=$?
((premise == 0)) || fail "the premise changed: a tail pipe no longer hides a failure (got $premise)"

echo "== a run that exits 0 while its log says otherwise is not a pass"
status=0
./t.sh run -t 0 -l "$work/logs" -- sh -c 'echo "collected 0 items"; exit 0' >/dev/null 2>&1 || status=$?
((status == 3)) || fail "run reported $status for a green run whose log said no tests were collected"

echo "== an honest green run is still a pass"
status=0
./t.sh run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed in 1.83s"; exit 0' >/dev/null 2>&1 || status=$?
((status == 0)) || fail "run reported $status for a healthy run — it would cry wolf"

echo "== T_ALLOW excuses a marker the repository expects, and nothing else"
status=0
T_ALLOW='expected: no tests ran' ./t.sh run -t 0 -l "$work/logs" \
  -- sh -c 'echo "expected: no tests ran"; exit 0' >/dev/null 2>&1 || status=$?
((status == 0)) || fail "T_ALLOW did not excuse the line it names (got $status)"
status=0
T_ALLOW='something else entirely' ./t.sh run -t 0 -l "$work/logs" \
  -- sh -c 'echo "expected: no tests ran"; exit 0' >/dev/null 2>&1 || status=$?
((status == 3)) || fail "T_ALLOW excused a line it does not name (got $status) — it excuses everything"

echo "== run refuses to start when its log cannot be written"
# A lost log silently cancels half of what this harness is for, so it is a refusal up
# front rather than a discovery afterwards. Root can write anywhere, so it cannot be asked.
if [[ $EUID -eq 0 ]]; then
  echo "   skipped: running as root, which can write into a read-only directory"
else
  readonly_dir="$work/readonly"
  mkdir -p "$readonly_dir"
  chmod a-w "$readonly_dir"
  status=0
  ./t.sh run -t 0 -l "$readonly_dir" -- sh -c 'exit 0' >/dev/null 2>&1 || status=$?
  ((status == 2)) || fail "run started with nowhere to put its log (got $status)"
fi

echo "== run refuses a command that was not put after --"
status=0
./t.sh run sh -c 'exit 0' >/dev/null 2>&1 || status=$?
((status == 2)) || fail "run accepted a command without -- (got $status); guessing is how the wrong thing gets run"

echo "== flaky calls a command that always agrees with itself stable"
status=0
./t.sh flaky 3 -l "$work/logs" -- sh -c 'echo "3 passed"; exit 0' >/dev/null 2>&1 || status=$?
((status == 0)) || fail "flaky called a deterministic green command unstable (got $status)"
status=0
./t.sh flaky 3 -l "$work/logs" -- sh -c 'echo "1 failed"; exit 1' >/dev/null 2>&1 || status=$?
((status == 1)) || fail "flaky did not pass through the status of a command that always fails (got $status)"

echo "== flaky notices a command that disagrees with itself"
# Deterministic divergence: the first run passes, every run after it fails
counter="$work/flaky-counter"
rm -f "$counter"
status=0
# shellcheck disable=SC2016  # $0 and $n belong to the inner sh, not to this script
./t.sh flaky 3 -l "$work/logs" -- \
  sh -c 'n=$(cat "$0" 2>/dev/null || echo 0); echo $((n + 1)) >"$0"; test "$n" -eq 0' "$counter" \
  >/dev/null 2>&1 || status=$?
((status == 4)) || fail "flaky missed a command whose runs disagreed (got $status)"

echo "== flaky refuses the arguments that would make it meaningless"
status=0
./t.sh flaky 1 -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>&1 || status=$?
((status == 2)) || fail "flaky accepted a single run, which cannot show disagreement (got $status)"
status=0
./t.sh flaky 3 -l "$work/logs" sh -c 'exit 0' >/dev/null 2>&1 || status=$?
((status == 2)) || fail "flaky accepted a command that was not put after -- (got $status)"

echo "== bisect names the commit that broke it, across a history holding an unbuildable one"
# A throwaway history where the answer is known in advance. The commit in the middle that
# does not build is the whole point: git bisect run treats a raw nonzero as "bad", so a
# harness that does not turn "cannot build" into a skip confidently blames the wrong commit.
repo="$work/bisect-repo"
mkdir -p "$repo"
git -C "$repo" init -q -b master
git -C "$repo" config user.name check
git -C "$repo" config user.email check@example.invalid
commit() { # commit MESSAGE
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$1"
  git -C "$repo" rev-parse HEAD
}
: >"$repo/builds"
: >"$repo/passes"
first_good=$(commit "good: it builds and the test passes")
rm "$repo/builds"
commit "untestable: this commit does not build" >/dev/null
# A testable good commit has to sit between the unbuildable one and the breakage, or the
# answer is genuinely ambiguous: with the middle commit skipped, "first bad" could be
# either it or the one after, and git would be right to say so.
: >"$repo/builds"
commit "good again, and testable" >/dev/null
rm "$repo/passes"
first_bad=$(commit "bad: it builds, and the test fails")
echo change >"$repo/note"
commit "bad too, further along" >/dev/null

status=0
bisect_out=$(cd "$repo" && "$HERE/t.sh" bisect "$first_good" -b 'test -f builds' -- test -f passes 2>&1) ||
  status=$?
((status == 0)) || fail "bisect exited $status on a history it should have resolved:"$'\n'"$bisect_out"
grep -qF "$first_bad" <<<"$bisect_out" ||
  fail "bisect did not name $first_bad as the first bad commit:"$'\n'"$bisect_out"
# And it must leave the repository where it found it, not detached mid-bisect
[[ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" == master ]] ||
  fail "bisect left the repository detached instead of resetting it"

echo "== every status a commit can produce maps to the right bisect verdict"
# Asserted on the probe directly rather than through a bisect: which commits git chooses
# to visit is its own business, so a skip may simply never happen in a given history. A
# check that only sometimes exercises the branch it guards is not a check.
probe() { # probe EXPECTED DESCRIPTION -- CMD...
  local expected="$1" what="$2"
  shift 2
  local got=0
  (cd "$repo" && "$HERE/t.sh" bisect-probe -l "$work/logs" "$@") >/dev/null 2>&1 || got=$?
  ((got == expected)) || fail "a commit that $what should be $expected to git bisect, but the probe said $got"
}
probe 0 "builds and passes" -b true -- true
probe 1 "builds and fails" -b true -- false
probe 125 "does not build" -b false -- true
probe 125 "has no test runner (exit 127)" -- sh -c 'exit 127'
probe 125 "runs nothing while exiting 0" -- sh -c 'echo "collected 0 items"; exit 0'
# 128+n means killed by a signal, and git bisect ABORTS on anything above 127 rather than
# treating it as a verdict. Clamping it to "bad" is what keeps a crashing commit from
# ending the session.
probe 1 "is killed by a signal" -- sh -c 'kill -SEGV $$'

echo "== bisect refuses to start on a working tree it would trample"
echo dirty >"$repo/passes"
status=0
(cd "$repo" && "$HERE/t.sh" bisect "$first_good" -- true) >/dev/null 2>&1 || status=$?
((status == 2)) || fail "bisect started with uncommitted changes in the tree (got $status)"
git -C "$repo" checkout -q -- . 2>/dev/null || :

echo "== falsify separates what the suite caught from what it never saw"
# A throwaway repository whose suite deliberately covers one guard and not the other, so
# every verdict falsify can reach is exercised on a known answer.
fal="$work/falsify-repo"
mkdir -p "$fal/tests"
cat >"$fal/impl.sh" <<'IMPL'
#!/bin/sh
clamp() { if [ "$1" -lt 0 ]; then echo 0; else echo "$1"; fi; }
strip() { echo "$1" | tr -d ' '; }
IMPL
cat >"$fal/suite.sh" <<'SUITE'
#!/bin/sh
. ./impl.sh
[ "$(clamp -5)" = "0" ] || { echo "clamp let a negative through"; exit 1; }
echo "1 passed"
SUITE
cat >"$fal/tests/defects.sh" <<'DEFECTS'
defect 'clamp/negative' 'impl.sh' \
  'if [ "$1" -lt 0 ]' 'if false' \
  'a negative reading is reported as-is instead of being clamped to zero'
defect 'strip/spaces' 'impl.sh' \
  "tr -d ' '" 'cat' \
  'a name keeps the spaces that were supposed to be removed'
defect 'gone/drifted' 'impl.sh' \
  'a line that is not in the file' 'anything' \
  'nothing: this entry exists to prove a drifted list says so'
defect 'syntax/broken' 'impl.sh' \
  'clamp() {' 'clamp() {{{' \
  'nothing: this edit only breaks the syntax, which a parser notices and a test does not'
DEFECTS
chmod +x "$fal/impl.sh" "$fal/suite.sh"
git -C "$fal" init -q -b master
git -C "$fal" config user.name check
git -C "$fal" config user.email check@example.invalid
git -C "$fal" add -A
git -C "$fal" commit -q -m "the fixture"
# A pristine copy to diff against byte for byte. Comparing `$(cat file)` with `$(cat file)`
# would pass a restore that dropped the trailing newline, because command substitution
# strips it from both sides — a check sharing the blind spot of the code it checks.
cp "$fal/impl.sh" "$work/impl.sh.pristine"

status=0
fal_out=$(cd "$fal" && "$HERE/t.sh" falsify -b 'sh -n impl.sh' -l "$work/logs" -- sh suite.sh 2>&1) || status=$?
((status == 1)) || fail "falsify exited $status where defects went unnoticed:"$'\n'"$fal_out"
grep -q '^caught    clamp/negative' <<<"$fal_out" ||
  fail "falsify did not credit the suite for the guard it does cover:"$'\n'"$fal_out"
grep -q '^SURVIVED  strip/spaces' <<<"$fal_out" ||
  fail "falsify did not report the guard nothing checks:"$'\n'"$fal_out"
grep -q '^stale     gone/drifted' <<<"$fal_out" ||
  fail "falsify guessed at a find text that no longer matches instead of reporting it stale:"$'\n'"$fal_out"
# The one the user has to be able to trust: an edit that only breaks the build is not
# evidence that any test noticed anything
grep -q '^unusable  syntax/broken' <<<"$fal_out" ||
  fail "falsify credited the suite for an edit that merely stopped the code building:"$'\n'"$fal_out"

echo "== falsify puts the source back byte for byte"
cmp -s "$fal/impl.sh" "$work/impl.sh.pristine" ||
  fail "falsify did not restore impl.sh byte for byte"
git -C "$fal" diff --quiet || fail "falsify left the working tree dirty"

echo "== falsify refuses the situations where its answer would be meaningless"
status=0
(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh -c 'exit 1') >/dev/null 2>&1 || status=$?
((status == 2)) || fail "falsify measured against an already-failing suite (got $status)"
status=0
(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh -c 'echo "collected 0 items"; exit 0') \
  >/dev/null 2>&1 || status=$?
((status == 2)) || fail "falsify measured against a suite that never really ran (got $status)"
echo dirt >"$fal/impl.sh.tmp" && mv "$fal/impl.sh.tmp" "$fal/impl.sh"
status=0
(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
((status == 2)) || fail "falsify started on a dirty tree, where an interrupted restore looks like your own edits (got $status)"
git -C "$fal" checkout -q -- .
status=0
: >"$fal/tests/empty.sh"
(cd "$fal" && "$HERE/t.sh" falsify -d tests/empty.sh -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
((status == 2)) || fail "falsify accepted an empty defect list, which proves nothing (got $status)"

echo "== the help text lists every subcommand the dispatcher accepts"
# The usage text is read out of this file's own header by line range, so it drifts the
# moment a subcommand is added without moving the range. This is that drift check.
help=$(./t.sh --help)
subs=()
while IFS= read -r sub; do subs+=("$sub"); done < <(sed -n 's/^  \([a-z-]*\)) cmd_[a-z_]*.*/\1/p' t.sh)
# An extractor that matches nothing would leave the loop below empty and read as "no
# drift" — the exact way a broken check goes on looking like a working one
((${#subs[@]} >= 2)) || fail "only ${#subs[@]} subcommand(s) could be read out of t.sh — the extractor is broken"
for sub in "${subs[@]}"; do
  grep -qF "t.sh $sub" <<<"$help" ||
    fail "t.sh dispatches '$sub' but its help never mentions it — the usage line range has drifted"
done

# The steps below prove the checks above can fail, by breaking one thing at a time in a
# throwaway copy. T_CHECK_NESTED stops the copy from recursing into this same section.
if [[ -z "${T_CHECK_NESTED:-}" ]]; then
  copy() {
    local dest="$1"
    mkdir -p "$dest/tests/fixtures" "$dest/templates"
    cp t.sh check.sh "$dest/"
    cp templates/defects.sh "$dest/templates/"
    cp tests/fixtures/*.log "$dest/tests/fixtures/"
  }
  nested() { (cd "$1" && T_CHECK_NESTED=1 ./check.sh >/dev/null 2>&1); }

  echo "== the marker check is able to fail: a dead entry"
  copy "$work/dead"
  awk '/^# <<< LIE MARKERS/ && !done { print "  '\''a marker matching nothing'\''"; done=1 } { print }' \
    t.sh >"$work/dead/t.sh.new" && mv "$work/dead/t.sh.new" "$work/dead/t.sh"
  chmod +x "$work/dead/t.sh"
  grep -qF 'a marker matching nothing' "$work/dead/t.sh" || fail "the dead-entry fixture was not planted"
  ! nested "$work/dead" || fail "a marker matching nothing passed the gate — the marker check catches nothing"

  echo "== the marker check is able to fail: an entry that fires on a healthy run"
  copy "$work/noisy"
  awk '/^# <<< LIE MARKERS/ && !done { print "  '\''test session starts'\''"; done=1 } { print }' \
    t.sh >"$work/noisy/t.sh.new" && mv "$work/noisy/t.sh.new" "$work/noisy/t.sh"
  chmod +x "$work/noisy/t.sh"
  ! nested "$work/noisy" || fail "a marker that fires on the clean fixture passed the gate"

  echo "== the status check is able to fail: run reading the pipeline instead of the command"
  # The regression as it actually occurs: a harness with no pipefail that reads $? after
  # the pipe. Both halves are one defect — under pipefail alone, $? still happens to be
  # right whenever the *first* command is the one that failed, so planting only the $?
  # would prove nothing.
  copy "$work/blind"
  # shellcheck disable=SC2016  # the $? is the defect being planted, not an expansion
  sed -e 's/^set -uo pipefail$/set -u/' -e 's/local status=${PIPESTATUS\[0\]}/local status=$?/' \
    t.sh >"$work/blind/t.sh.new" && mv "$work/blind/t.sh.new" "$work/blind/t.sh"
  chmod +x "$work/blind/t.sh"
  grep -qF 'local status=$?' "$work/blind/t.sh" || fail "the blind-status fixture was not planted"
  ! nested "$work/blind" || fail "a run reading tee's status passed the gate — the whole premise is unguarded"

  echo "== the help-drift check is able to fail: a subcommand the help never mentions"
  copy "$work/undocumented"
  awk '/^  flaky\) cmd_flaky/ && !done { print "  wat) cmd_run \"$@\" ;;"; done=1 } { print }' \
    t.sh >"$work/undocumented/t.sh.new" && mv "$work/undocumented/t.sh.new" "$work/undocumented/t.sh"
  chmod +x "$work/undocumented/t.sh"
  grep -qF 'wat) cmd_run' "$work/undocumented/t.sh" || fail "the undocumented-subcommand fixture was not planted"
  ! nested "$work/undocumented" || fail "a subcommand missing from the help passed the gate"

  echo "== the bisect status mapping is able to fail: statuses passed through raw"
  copy "$work/raw"
  # shellcheck disable=SC2016  # the $status is the defect being planted, not an expansion
  sed 's/^    \*) return 1 ;;$/    *) return "$status" ;;/' t.sh >"$work/raw/t.sh.new" &&
    mv "$work/raw/t.sh.new" "$work/raw/t.sh"
  chmod +x "$work/raw/t.sh"
  # shellcheck disable=SC2016  # $status is t.sh's own source text, not an expansion here
  grep -qF 'return "$status" ;;' "$work/raw/t.sh" || fail "the raw-status fixture was not planted"
  ! nested "$work/raw" || fail "a probe returning 139 to git bisect passed the gate — a crash would abort the session"

  echo "== the restore check is able to fail: a slurp that loses the trailing newline"
  # The regression this exact guard was written for. Dropping the `printf x` lets command
  # substitution eat the file's last newline, so every restore leaves the tree dirty by one
  # byte — invisible to a string comparison, obvious to git.
  copy "$work/trailing"
  # shellcheck disable=SC2016  # both sides are t.sh's own source text, not expansions
  sed 's/__content=\$(cat "\$2" \&\& printf x)/__content=$(cat "$2")/' t.sh >"$work/trailing/t.sh.new" &&
    mv "$work/trailing/t.sh.new" "$work/trailing/t.sh"
  chmod +x "$work/trailing/t.sh"
  # shellcheck disable=SC2016  # t.sh's own source text, not an expansion
  grep -qF '__content=$(cat "$2")' "$work/trailing/t.sh" || fail "the trailing-newline fixture was not planted"
  ! nested "$work/trailing" || fail "a falsify that leaves the source one byte different passed the gate"

  echo "== the log-is-writable guard is able to fail"
  copy "$work/nolog"
  # shellcheck disable=SC2016  # $log is t.sh's own source text being matched, not an expansion
  guard=': >"$log" || die'
  grep -vF "$guard" t.sh >"$work/nolog/t.sh.new" && mv "$work/nolog/t.sh.new" "$work/nolog/t.sh"
  chmod +x "$work/nolog/t.sh"
  ! grep -qF "$guard" "$work/nolog/t.sh" || fail "the missing-guard fixture was not planted"
  ! nested "$work/nolog" || fail "a run that cannot write its log passed the gate"
fi

echo
echo "check: everything holds"
