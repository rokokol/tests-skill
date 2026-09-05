#!/usr/bin/env bash
# t.sh — the local test harness: one subcommand per question a test run raises.
#
#   t.sh run [-l DIR] [-p PATTERN] [-t N] -- CMD...
#                             run CMD once. The status reported is CMD's own, the whole
#                             output is kept in a log file, and the log is read even when
#                             CMD exited 0 — because that is not always a success
#   t.sh flaky N [-l DIR] [-p PATTERN] -- CMD...
#                             run CMD N times and report how many runs disagreed with the
#                             first. Evidence that a test is unstable, never a way to
#                             tolerate one
#
# The command is always explicit, after `--`. Nothing here guesses what your suite is:
# a harness that guesses runs the wrong thing on the day it matters.
#
# Exit status: CMD's own, passed through unchanged, except
#   4  the runs disagreed with each other (flaky)
#   3  CMD exited 0 but its log says it did not do what a pass claims
#   2  a usage or harness error, before CMD ever ran
set -uo pipefail

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

die() {
  printf 't.sh: %s\n' "$1" >&2
  exit 2
}

# >>> LIE MARKERS: a run that printed one of these did not do what its exit status claims.
# Matched case-insensitively as fixed strings against the whole log. check.sh reads this
# block out of this file and requires every entry to match its own fixture, so the list is
# never spelled a second time — a second copy drifts, and a drifted list lies, and a dead
# entry that matches nothing looks exactly like a guard while guarding nothing.
#
# Two kinds live here, and both are failures rather than warnings: markers that mean the
# suite never ran, and markers that mean something broke in a way an exit status can miss.
#
# What is deliberately NOT here: markers that are normal noise in some ecosystem. Go
# prints `[no test files]` for every package without tests and Rust prints `running 0
# tests` for every target without them, so in a workspace both fire on a perfectly good
# run. A marker that cries on healthy runs gets the whole check switched off within a day,
# which protects nothing. Those live in references/ecosystems/ instead, to be added per
# repository with -p — see also T_ALLOW, which excuses a marker your repo expects.
LIE_MARKERS=(
  'no tests ran'
  'collected 0 items'
  'no tests were found'
  'no tests found'
  '1..0'
  'traceback (most recent call last)'
  'panic:'
  'addresssanitizer'
  'leaksanitizer'
  'command not found'
  'segmentation fault'
)
# <<< LIE MARKERS

# Prints "pattern<TAB>line" for every marker found; returns 0 when anything was found.
# T_ALLOW is an extended regex whose matching lines are dropped before the scan.
scan_log() {
  local log="$1"
  shift
  local -a pats=("${LIE_MARKERS[@]}")
  (($#)) && pats+=("$@")

  local source="$log"
  if [[ -n "${T_ALLOW:-}" ]]; then
    source="$log.scanned"
    grep -Ev -- "$T_ALLOW" "$log" >"$source" || :
  fi

  local pat line found=1
  for pat in "${pats[@]}"; do
    while IFS= read -r line; do
      printf '%s\t%s\n' "$pat" "$line"
      found=0
    done < <(grep -i -F -m 3 -- "$pat" "$source" || :)
  done

  [[ -n "${T_ALLOW:-}" ]] && rm -f "$source"
  return "$found"
}

cmd_run() {
  local logdir="${T_LOGDIR:-.test-logs}" tail_n=40 saw_ddash=""
  local -a extra=()
  while (($#)); do
    case "$1" in
      -l)
        logdir="${2:?-l needs a directory}"
        shift 2
        ;;
      -p)
        extra+=("${2:?-p needs a pattern}")
        shift 2
        ;;
      -t)
        tail_n="${2:?-t needs a number}"
        shift 2
        ;;
      --)
        saw_ddash=1
        shift
        break
        ;;
      *) die "run: unexpected argument '$1' — the command goes after --" ;;
    esac
  done
  [[ -n "$saw_ddash" ]] || die "run: the command must follow -- (t.sh run -- pytest -q)"
  (($#)) || die "run: no command after --"

  mkdir -p "$logdir" || die "run: cannot create $logdir"
  local log="${T_LOGFILE:-}"
  [[ -n "$log" ]] || log="$logdir/run-$(date +%Y%m%d-%H%M%S)-$$.log"
  # Refuse before running rather than discover it afterwards: a run whose log could not be
  # written cannot be read, and reading the log is half of what this harness is for
  : >"$log" || die "run: cannot write $log"

  # CMD's own status, never the pipeline's. `cmd | tee` reports tee and `cmd | tail`
  # reports tail — both are 0 for a suite that just failed, which is how a red run
  # gets committed as a green one.
  "$@" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}

  local hits
  hits=$(scan_log "$log" ${extra[@]+"${extra[@]}"}) || :

  local verdict=$status
  if ((status == 0)) && [[ -n "$hits" ]]; then
    verdict=3
  fi

  # The verdict is decided above, before a single line of the log is shown. Whatever is
  # printed from here on is for a reader, and can no longer become the answer.
  echo
  if [[ -n "$hits" ]]; then
    printf 't.sh: the log carries markers of a run that did not do its job:\n' >&2
    printf '%s\n' "$hits" | while IFS=$'\t' read -r pat line; do
      printf '  [%s] %s\n' "$pat" "$line" >&2
    done
  fi

  case "$verdict" in
    0) printf 't.sh: pass — exit 0, log clean (%s)\n' "$log" ;;
    3) printf 't.sh: LIED — exit 0, but the log above says otherwise (%s)\n' "$log" >&2 ;;
    *) printf 't.sh: fail — exit %d (%s)\n' "$status" "$log" >&2 ;;
  esac

  if ((verdict != 0)) && ((tail_n > 0)); then
    printf '\n--- last %d lines ---\n' "$tail_n" >&2
    tail -n "$tail_n" "$log" >&2
  fi

  return "$verdict"
}

# Runs the same command N times and reports how many runs disagreed with the first.
# That is the whole mechanism: no history, no statistics, no quarantine list. It exists to
# turn "it failed once, probably nothing" into evidence, so the underlying race can be
# fixed — never to make an unstable test tolerable by rerunning it until it agrees.
cmd_flaky() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "flaky: first argument must be a run count (t.sh flaky 20 -- ...)"
  ((n >= 2)) || die "flaky: $n runs cannot show disagreement; use 2 or more"
  shift

  local logdir="${T_LOGDIR:-.test-logs}"
  local -a pass=()
  while (($#)); do
    case "$1" in
      -l)
        logdir="${2:?-l needs a directory}"
        shift 2
        ;;
      --) break ;;
      *)
        pass+=("$1")
        shift
        ;;
    esac
  done
  [[ "${1:-}" == "--" ]] || die "flaky: the command must follow -- (t.sh flaky 20 -- pytest -q)"

  local stamp
  stamp="$logdir/flaky-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$stamp" || die "flaky: cannot create $stamp"

  local i status baseline="" differed=0 agreed=0 first_divergence=""
  for ((i = 1; i <= n; i++)); do
    status=0
    T_LOGFILE="$stamp/run-$i.log" cmd_run -t 0 -l "$stamp" "${pass[@]+"${pass[@]}"}" "$@" \
      >/dev/null 2>&1 || status=$?
    if [[ -z "$baseline" ]]; then
      baseline="$status"
      agreed=1
      printf 'run %d/%d  baseline: exit %d\n' "$i" "$n" "$status"
      continue
    fi
    if ((status == baseline)); then
      agreed=$((agreed + 1))
      printf 'run %d/%d  same (exit %d)\n' "$i" "$n" "$status"
    else
      differed=$((differed + 1))
      [[ -n "$first_divergence" ]] || first_divergence="$stamp/run-$i.log"
      printf 'run %d/%d  DIFFERED: exit %d, not %d  -> %s\n' "$i" "$n" "$status" "$baseline" "$stamp/run-$i.log"
    fi
  done

  echo
  if ((differed == 0)); then
    printf 't.sh: stable across %d runs — every run exited %d (%s)\n' "$n" "$baseline" "$stamp"
    return "$baseline"
  fi
  printf 't.sh: UNSTABLE — %d of %d runs disagreed with the first (%s)\n' "$differed" "$n" "$stamp" >&2
  printf 'first divergence: %s\n' "$first_divergence" >&2
  printf '%d agreed, %d differed. Fix the race or quarantine the test; do not retry it.\n' \
    "$agreed" "$differed" >&2
  return 4
}

cmd="${1:-}"
(($# == 0)) || shift
case "$cmd" in
  run) cmd_run "$@" ;;
  flaky) cmd_flaky "$@" ;;
  -h | --help | help) usage ;;
  '')
    usage >&2
    exit 2
    ;;
  *)
    printf 't.sh: no such subcommand: %s\n\n' "$cmd" >&2
    usage >&2
    exit 2
    ;;
esac
