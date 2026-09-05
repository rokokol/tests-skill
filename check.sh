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
scripts=(t.sh check.sh)

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

# The steps below prove the checks above can fail, by breaking one thing at a time in a
# throwaway copy. T_CHECK_NESTED stops the copy from recursing into this same section.
if [[ -z "${T_CHECK_NESTED:-}" ]]; then
  copy() {
    local dest="$1"
    mkdir -p "$dest/tests/fixtures"
    cp t.sh check.sh "$dest/"
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
