#!/usr/bin/env bash
# t.sh — the local test harness: one subcommand per question a test run raises.
#
#   t.sh run [-l DIR] [-p PATTERN] [-t N] -- CMD...
#                             run CMD once. The status reported is CMD's own, the whole
#                             output is kept in a log file, and the log is read even when
#                             CMD exited 0 — because that is not always a success
#
# The command is always explicit, after `--`. Nothing here guesses what your suite is:
# a harness that guesses runs the wrong thing on the day it matters.
#
# Exit status: CMD's own, passed through unchanged, except
#   3  CMD exited 0 but its log says it did not do what a pass claims
#   2  a usage or harness error, before CMD ever ran
set -uo pipefail

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
  local log
  log="$logdir/run-$(date +%Y%m%d-%H%M%S)-$$.log"
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

cmd="${1:-}"
(($# == 0)) || shift
case "$cmd" in
  run) cmd_run "$@" ;;
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
