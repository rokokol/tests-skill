#!/usr/bin/env bash
# t.sh — the local test harness: one subcommand per question a test run raises.
#
#   t.sh run [-l DIR] [-m SET] [-p PATTERN] [-t N] -- CMD...
#                             run CMD once. The status reported is CMD's own, the whole
#                             output is kept in a log file, and the log is read even when
#                             CMD exited 0 — because that is not always a success.
#                             -m adds a marker set from markers/ (a name) or a file path;
#                             markers/default.txt always applies. The kind of verdict —
#                             pass, fail or lied — is written beside the log as LOG.verdict
#   t.sh flaky N [-l DIR] [-m SET] [-p PATTERN] [-t N] -- CMD...
#                             run CMD N times and report how many runs disagreed with the
#                             first. Evidence that a test is unstable, never a way to
#                             tolerate one
#   t.sh bisect GOOD [-b BUILD] [-m SET] [-p PATTERN] [-t N] [--first-parent] [--no-checkout] -- CMD...
#                             git bisect run between GOOD and HEAD, judging each commit
#                             with run. A commit that cannot be built is skipped rather
#                             than blamed; when only such commits are left the answer is
#                             INCONCLUSIVE, exit 89, and git's session log is kept
#   t.sh bisect-probe [-b BUILD] [-l DIR] [-m SET] [-p PATTERN] [-t N] -- CMD...
#                             internal: the single-commit verdict `git bisect run` calls
#   t.sh falsify [-d FILE] [-b BUILD] [--timeout SECONDS] [--out DIR] [--any-file] [-l DIR] [-m SET] [-p PATTERN] [-t N] [FILTER] -- CMD...
#                             break one guard at a time, as written by hand in FILE
#                             (default tests/defects.sh), and require the suite to notice.
#                             A defect the suite survives names something nobody checks.
#                             Each run is held to a deadline, five times the unbroken
#                             suite's own time or twenty seconds, or --timeout. What was
#                             found goes under DIR (default falsify.out): one file of
#                             names per verdict, a log per defect, and results.json. A
#                             defect in a test, vendored or generated file is refused,
#                             because it proves nothing, unless --any-file says otherwise
#
# The command is always explicit, after `--`. Nothing here guesses what your suite is:
# a harness that guesses runs the wrong thing on the day it matters.
#
# A repository may keep its POLICY — marker sets, excused lines, log directory — in
# ./tests/t.conf, which is read from the current directory only. It never carries the
# command. See the config section below, or `allow`/`markers`/`pattern`/`logdir`.
#
# Exit status: CMD's own, passed through unchanged, except a band no test runner uses.
# 2, 3 and 4 were tried first and collide: GNU make exits 2 on any error, pytest uses
# 2–5, cargo-nextest exits 4 for "no tests ran", which is the very thing run detects.
#   64  a usage error — a flag, the config, a missing --, an allow regex grep rejects
#   70  the harness itself failed — a log it cannot write, a file it cannot put back
#   79  CMD exited 0 but its log says it did not do what a pass claims (run)
#   83  at least one defect SURVIVED: the suite did not notice it (falsify)
#   84  a defect never let the suite finish within the deadline (falsify)
#   85  the suite was red, or never really ran, before any edit was made (falsify)
#   86  the runs disagreed with each other (flaky)
#   87  the defect list has drifted: a find text no longer matches exactly once (falsify)
#   88  a defect only stopped the build, so the tests were never asked (falsify)
#   89  only commits that could not answer are left between good and bad (bisect)
set -uo pipefail

# The header above, up to the first line that is not a comment, is the help text
usage() { awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; }

# 64 is EX_USAGE and 70 is EX_SOFTWARE in sysexits(3): the caller asked wrongly, or the
# harness broke. Neither is CMD's status, and a probe that skips on 64 must not skip on 70.
die() {
  printf 't.sh: %s\n' "$1" >&2
  exit 64
}

fatal() {
  printf 't.sh: %s\n' "$1" >&2
  exit 70
}

# Resolved through symlinks: `ln -s .../t.sh ~/.local/bin/t.sh` is how this gets onto a
# PATH, and dirname of the link would look for markers/ beside the link and refuse every
# run. A loop over readlink rather than `readlink -f`, which macOS only gained in 12.3.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
  target=$(readlink "$self")
  case "$target" in
    /*) self="$target" ;;
    *) self="$(dirname -- "$self")/$target" ;;
  esac
done
HERE=$(cd -- "$(dirname -- "$self")" && pwd)
SELF="$HERE/$(basename -- "$self")"
unset self target
MARKER_DIR="$HERE/markers"
MARKER_FILES=()

# The markers live in markers/*.txt as data, not in this file as code, so the list can grow
# without touching the harness and so check.sh can read exactly what `run` reads. A NAME
# with no slash resolves to a set shipped beside this script; anything else is a path.
#
# It assigns to RESOLVED instead of printing, and everything below refuses instead of
# returning, for one reason: `die` inside a `$(...)` exits the SUBSHELL. The caller carries
# on with an empty string, so a refusal written that way does not refuse — and here it
# would leave the marker list empty, which is the one state that makes every run pass while
# the check still looks like it is working.
RESOLVED=""
resolve_markers() {
  local name="$1"
  if [[ "$name" != */* && -r "$MARKER_DIR/$name.txt" ]]; then
    RESOLVED="$MARKER_DIR/$name.txt"
    return
  fi
  [[ -r "$name" ]] ||
    die "no marker set called '$name' — expected $MARKER_DIR/$name.txt or a readable file"
  RESOLVED="$name"
}

# The same set named twice — twice on the line, or once in the config and once on the
# line — would print every finding twice, and a doubled finding reads as two problems
add_marker_file() {
  local f
  for f in ${MARKER_FILES[@]+"${MARKER_FILES[@]}"}; do
    [[ "$f" != "$1" ]] || return 0
  done
  MARKER_FILES+=("$1")
}

# Blank lines and # comments out; everything else verbatim, spaces included.
#
# The trailing CR is stripped first, and that is not cosmetic: a file checked out with
# CRLF turns every blank line into a marker of a single carriage return, which `grep -F`
# then finds on every line of a CRLF log — so a healthy run is reported as a lie, with a
# random build line offered as the evidence. Found on a Windows runner, where git's
# autocrlf does the conversion on checkout.
read_markers() {
  local file="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "$line"
  done <"$file"
}

# A repository's own policy: which marker sets apply, which lines are excused, where logs
# go. Read from ./tests/t.conf and nowhere else — no search up the tree, because a config
# found three directories away is a config nobody knew was in effect. T_CONFIG points
# somewhere else; T_CONFIG= (empty) turns it off.
#
# It carries policy and never the command. The command stays after `--`, in the line you
# typed, so what runs is always visible where it runs.
EXTRA_PATTERNS=()
POLICY_LOGDIR=""
POLICY_ALLOW=""
load_config() {
  local conf="${T_CONFIG-tests/t.conf}"
  [[ -n "$conf" ]] || return 0
  if [[ ! -e "$conf" ]]; then
    # A repository with no config is the normal case; only a config that exists and cannot
    # be used is an error
    # `-z "${T_CONFIG-}"` rather than `-v T_CONFIG`: the second is bash 4.2+, and macOS
    # ships 3.2. It is also the same test — an unset T_CONFIG expands to the empty string
    # here, and an empty one returned above.
    [[ -z "${T_CONFIG-}" ]] || die "config: $conf does not exist"
    return 0
  fi
  [[ -r "$conf" ]] || die "config: $conf exists but cannot be read"

  local line key value n=0 sets=0 pats=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    # Same CRLF stripping as read_markers, for the same reason: a config checked out with
    # CRLF would otherwise carry a carriage return into every value
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
    key=${line%%[[:space:]]*}
    value=${line#"$key"}
    value=${value#"${value%%[![:space:]]*}"}
    [[ -n "$value" ]] || die "config: $conf:$n — '$key' has no value"
    case "$key" in
      markers)
        resolve_markers "$value"
        add_marker_file "$RESOLVED"
        sets=$((sets + 1))
        ;;
      pattern)
        EXTRA_PATTERNS+=("$value")
        pats=$((pats + 1))
        ;;
      allow)
        [[ -z "$POLICY_ALLOW" ]] || die "config: $conf:$n — 'allow' is given more than once"
        POLICY_ALLOW="$value"
        ;;
      logdir) POLICY_LOGDIR="$value" ;;
      # An unknown key is a typo, and a typo that is ignored is a policy silently not in
      # effect — the failure this whole file exists to avoid
      *) die "config: $conf:$n — unknown key '$key' (markers, pattern, allow, logdir)" ;;
    esac
  done <"$conf"

  printf 't.sh: policy from %s (%d marker set(s), %d pattern(s)%s)\n' \
    "$conf" "$sets" "$pats" "$([[ -n "$POLICY_ALLOW" ]] && printf ', 1 allow')" >&2
}

# What the last cmd_run in this shell concluded: pass, fail or lied. Empty until it ran.
RUN_VERDICT=""

# Fills MARKER_PATTERNS from MARKER_FILES. Called from the shell that can actually exit.
MARKER_PATTERNS=()
load_markers() {
  MARKER_PATTERNS=()
  local file line before
  for file in "${MARKER_FILES[@]}"; do
    before=${#MARKER_PATTERNS[@]}
    while IFS= read -r line; do MARKER_PATTERNS+=("$line"); done < <(read_markers "$file")
    ((${#MARKER_PATTERNS[@]} > before)) ||
      die "$file holds no markers — an empty set reads as a working check while checking nothing"
  done
  ((${#MARKER_PATTERNS[@]} > 0)) || die "no marker files were loaded"
}

# Prints "pattern<TAB>line" for every marker found; returns 0 when anything was found.
# T_ALLOW is an extended regex whose matching lines are dropped before the scan.
scan_log() {
  local log="$1"
  shift
  # Already loaded and validated by the caller, which is the shell that can still exit
  local -a pats=("${MARKER_PATTERNS[@]}")
  (($#)) && pats+=("$@")

  # T_ALLOW is the ad-hoc override and wins over the repository's own `allow` line
  local allow="${T_ALLOW:-$POLICY_ALLOW}"
  local source="$log" rc=0
  if [[ -n "$allow" ]]; then
    source="$log.scanned"
    grep -Ev -- "$allow" "$log" >"$source" || rc=$?
    # 1 means every line was excused, which is odd but legitimate. Anything above it
    # means the filter did not run, and a log it did not run on must not read as clean.
    # cmd_run refuses such a regex before CMD starts; this is the guard behind that one,
    # for the day it is bypassed — a `die` here would only exit the $(...) around us.
    if ((rc > 1)); then
      printf 'allow\tthe allow regex could not be applied (grep exited %d), so the log was not scanned\n' "$rc"
      rm -f "$source"
      return 0
    fi
  fi

  local pat line found=1
  for pat in "${pats[@]}"; do
    while IFS= read -r line; do
      printf '%s\t%s\n' "$pat" "$line"
      found=0
    done < <(grep -i -F -m 3 -- "$pat" "$source" || :)
  done

  [[ -n "$allow" ]] && rm -f "$source"
  return "$found"
}

cmd_run() {
  local tail_n=40 saw_ddash="" logdir=""
  MARKER_FILES=("$MARKER_DIR/default.txt")
  EXTRA_PATTERNS=()
  POLICY_LOGDIR=""
  POLICY_ALLOW=""

  # Policy first, then the flags on top: what you type adds to the repository's own
  # settings rather than silently replacing them
  load_config
  logdir="${T_LOGDIR:-${POLICY_LOGDIR:-.test-logs}}"

  local -a extra=(${EXTRA_PATTERNS[@]+"${EXTRA_PATTERNS[@]}"})
  while (($#)); do
    case "$1" in
      -l)
        logdir="${2:?-l needs a directory}"
        shift 2
        ;;
      -m)
        # Additive: the default set always applies, and a repository opts into more
        resolve_markers "${2:?-m needs a marker set or file}"
        add_marker_file "$RESOLVED"
        shift 2
        ;;
      -p)
        extra+=("${2:?-p needs a pattern}")
        shift 2
        ;;
      -t)
        tail_n="${2:?-t needs a number}"
        # (( )) reads a word as the variable of that name, which is zero, so `-t abc`
        # would silently mean "no tail" rather than refuse
        [[ "$tail_n" =~ ^[0-9]+$ ]] || die "run: -t needs a number of lines, got '$tail_n'"
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

  # Before the command runs, and from this shell rather than a subshell, so a broken
  # marker set stops the run instead of quietly making every run a pass
  load_markers

  # The same for the allow regex. It used to be applied only inside scan_log, where grep
  # rejecting it left the filtered log empty, and an empty log has no markers — so a typo
  # in `allow` turned every run into a pass, silently. Judged by what grep says rather
  # than by its status, and against a line of input rather than /dev/null: GNU and BSD grep
  # exit 2 on a regex they cannot compile, busybox's does not compile it at all until there
  # is a line to match, and every one of them complains on stderr once it does.
  local allow="${T_ALLOW:-$POLICY_ALLOW}" complaint=""
  if [[ -n "$allow" ]]; then
    complaint=$(printf 'x\n' | grep -E -- "$allow" 2>&1 >/dev/null || :)
    [[ -z "$complaint" ]] || die "allow: '$allow' is not a regex grep -E accepts — $complaint"
  fi

  mkdir -p "$logdir" || fatal "run: cannot create $logdir"
  local log="${T_LOGFILE:-}"
  [[ -n "$log" ]] || log="$logdir/run-$(date +%Y%m%d-%H%M%S)-$$.log"
  # Refuse before running rather than discover it afterwards: a run whose log could not be
  # written cannot be read, and reading the log is half of what this harness is for
  : >"$log" || fatal "run: cannot write $log"

  # CMD's own status, never the pipeline's. `cmd | tee` reports tee and `cmd | tail`
  # reports tail — both are 0 for a suite that just failed, which is how a red run
  # gets committed as a green one.
  "$@" 2>&1 | tee "$log"
  # Copied whole, in the one command that still can: bash resets PIPESTATUS after every
  # simple command, and an assignment or a `local` is one. A second reference on the next
  # line would already read empty.
  local -a ps=("${PIPESTATUS[@]}")
  local status=${ps[0]}

  local hits
  hits=$(scan_log "$log" ${extra[@]+"${extra[@]}"}) || :

  local verdict=$status
  if ((status == 0)) && [[ -n "$hits" ]]; then
    verdict=79
  fi

  # The KIND of verdict, out of band. A number cannot carry it: CMD's own 79 or 64 would
  # read as the harness's, and make's 2 once read as "the harness could not run it". So
  # the kind is set here for a caller in this shell, and written beside the log for a
  # caller that had to run this in a subshell — flaky, bisect-probe and falsify all do.
  RUN_VERDICT=fail
  ((verdict != 0)) || RUN_VERDICT=pass
  ((verdict != 79)) || RUN_VERDICT=lied
  printf '%s\n' "$RUN_VERDICT" >"$log.verdict"

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
    79) printf 't.sh: LIED — exit 0, but the log above says otherwise (%s)\n' "$log" >&2 ;;
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

  # The same policy `run` obeys: a repository that named its log directory once should not
  # find flaky writing somewhere else
  POLICY_LOGDIR=""
  load_config
  local logdir="${T_LOGDIR:-${POLICY_LOGDIR:-.test-logs}}"
  local -a pass=()
  while (($#)); do
    case "$1" in
      -l)
        logdir="${2:?-l needs a directory}"
        shift 2
        ;;
      -m)
        # Resolved here as well as in run, so a set that does not exist is refused
        # before the first of twenty runs rather than inside it
        resolve_markers "${2:?-m needs a marker set or file}"
        pass+=("$1" "$2")
        shift 2
        ;;
      -p | -t)
        # Forwarded to run, which validates them. Named here rather than swept up by a
        # catch-all, so the gate can read from this parser which flags flaky accepts.
        pass+=("$1" "${2:?$1 needs a value}")
        shift 2
        ;;
      --) break ;;
      *) die "flaky: unexpected argument '$1' — the command goes after --" ;;
    esac
  done
  [[ "${1:-}" == "--" ]] || die "flaky: the command must follow -- (t.sh flaky 20 -- pytest -q)"

  local stamp
  stamp="$logdir/flaky-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$stamp" || fatal "flaky: cannot create $stamp"

  local i status baseline="" differed=0 agreed=0 first_divergence=""
  for ((i = 1; i <= n; i++)); do
    status=0
    # In a subshell, so a `die` inside run ends that run and not this loop; and with its
    # stderr kept, because a refusal that went to /dev/null with the command's output
    # once left flaky exiting without a word
    (T_LOGFILE="$stamp/run-$i.log" cmd_run -t 0 -l "$stamp" "${pass[@]+"${pass[@]}"}" "$@") \
      >/dev/null 2>"$stamp/run-$i.err" || status=$?
    # No sidecar means run never reached a verdict — it refused, or it died. Neither is
    # a result to compare the other runs against.
    if [[ ! -e "$stamp/run-$i.log.verdict" ]]; then
      head -3 "$stamp/run-$i.err" >&2
      fatal "flaky: run $i produced no verdict (exit $status) — the harness could not run the command"
    fi
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
  return 86
}

# The verdict on ONE commit, in the vocabulary `git bisect run` speaks (git-bisect(1)):
#
#   0          good
#   1–124      bad
#   125        skip — this commit cannot answer the question
#   126, 127   bad as well: "command not found" is an ordinary error to git
#   128+       git ABORTS the whole session
#
# The kind of verdict comes from run's sidecar, never from the number: the command's own
# 2 is make failing, and once read here as "the harness could not run it", which skipped
# every commit where `make test` failed and named nobody. What the number still decides:
#   - 126 and 127 are a runner that is not there at this commit, which is no evidence
#     against it, so they are skipped rather than blamed;
#   - a run stopped by a person — HUP, INT, QUIT, TERM, that is 129/130/131/143 — is not
#     evidence either, and it is passed through so git aborts, which is what Ctrl-C means;
#   - any other signal (SEGV, ABRT, BUS, an OOM kill) is the code at this commit crashing,
#     and a crash is bad — clamped to 1 so git records it instead of aborting.
cmd_bisect_probe() {
  local build=""
  local -a pass=()
  while (($#)); do
    case "$1" in
      -b)
        build="${2:?-b needs a command}"
        shift 2
        ;;
      -l | -m | -p | -t)
        pass+=("$1" "${2:?$1 needs a value}")
        shift 2
        ;;
      --) break ;;
      *) die "bisect-probe: unexpected argument '$1' — the command goes after --" ;;
    esac
  done
  [[ "${1:-}" == "--" ]] || die "bisect-probe: the command must follow --"

  if [[ -n "$build" ]]; then
    if ! sh -c "$build" >&2; then
      echo "t.sh: this commit does not build — skipping it rather than blaming it" >&2
      return 125
    fi
  fi

  # The log path is chosen here so the sidecar can be found afterwards; bisect sets
  # T_LOGDIR to a directory outside the working tree it is checking commits out into
  local log="${T_LOGFILE:-}"
  if [[ -z "$log" ]]; then
    local dir="${T_LOGDIR:-.test-logs}"
    mkdir -p "$dir" || fatal "bisect-probe: cannot create $dir"
    log="$dir/probe-$(date +%Y%m%d-%H%M%S)-$$.log"
  fi

  # A short tail by default: a bisect prints one verdict per commit, and forty lines each
  # buries the answer. A -t the caller passed comes later in the list and wins. In a
  # subshell, so a refusal inside run reaches the case below as "no verdict" instead of
  # ending the probe with a status git would take for an answer.
  local status=0 kind=""
  (T_LOGFILE="$log" cmd_run -t 5 "${pass[@]+"${pass[@]}"}" "$@") || status=$?
  [[ ! -r "$log.verdict" ]] || kind=$(cat "$log.verdict")

  case "$kind" in
    pass) return 0 ;;
    lied)
      echo "t.sh: this commit's run exited 0 but its log says nothing ran — skipping it" >&2
      return 125
      ;;
    fail)
      case "$status" in
        126 | 127)
          echo "t.sh: the test runner is not there at this commit (exit $status) — skipping it" >&2
          return 125
          ;;
        129 | 130 | 131 | 143) return "$status" ;;
        *) return 1 ;;
      esac
      ;;
    *)
      echo "t.sh: no verdict from this commit (exit $status) — the harness could not run it, skipping" >&2
      return 125
      ;;
  esac
}

cmd_bisect() {
  local good="${1:-}"
  [[ -n "$good" ]] || die "bisect: needs a known-good ref (t.sh bisect v1.2.0 -- pytest -q)"
  shift
  local -a pass=() start_opts=()
  while (($#)); do
    case "$1" in
      -b | -m | -p | -t)
        # -b for the probe, the rest for run. No -l: the logs of a bisect go outside the
        # working tree on purpose, because bisect checks other commits out over it.
        pass+=("$1" "${2:?$1 needs a value}")
        shift 2
        ;;
      --first-parent | --no-checkout)
        # git's own. --first-parent follows only the first parent of a merge, which is
        # the bisect to run when a merged branch held commits that never built on their
        # own; --no-checkout only moves BISECT_HEAD, for a probe that reads history
        # rather than a tree.
        start_opts+=("$1")
        shift
        ;;
      --) break ;;
      *) die "bisect: unexpected argument '$1' — the command goes after --" ;;
    esac
  done
  [[ "${1:-}" == "--" ]] || die "bisect: the command must follow -- (t.sh bisect HEAD~20 -- pytest -q)"

  git rev-parse --git-dir >/dev/null 2>&1 || die "bisect: not inside a git repository"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "bisect: the working tree has uncommitted changes — commit or stash them first, because bisect checks other commits out over them"
  fi
  git rev-parse --verify --quiet "$good^{commit}" >/dev/null ||
    die "bisect: '$good' is not a commit in this repository"
  # `git bisect start` over a bisect already in progress resets it without a word, and
  # whoever was in the middle of that one loses their place
  if git bisect log >/dev/null 2>&1; then
    die "bisect: a bisect is already in progress here — finish it, or run 'git bisect reset' first"
  fi

  # Logs go outside the working tree: bisect checks other commits out over it, and a
  # directory of logs sitting in the middle of that is noise at best. A global, because
  # the EXIT trap below runs after this function's locals are gone.
  BISECT_LOGDIR=$(mktemp -d "${TMPDIR:-/tmp}/t.sh.XXXXXX") || fatal "bisect: cannot create a log directory"
  local logdir="$BISECT_LOGDIR"
  echo "t.sh: logs for this bisect are in $logdir"

  # Leaving a repository in a detached bisect state is a nasty thing to do to whoever runs
  # this, including on an interrupt. git's own session log is saved first: it is the one
  # artifact from which a wrong answer can be corrected — edit it, `git bisect replay`.
  trap 'git bisect log >"$BISECT_LOGDIR/bisect.log" 2>/dev/null; git bisect reset >/dev/null 2>&1 || :' EXIT

  git bisect start "${start_opts[@]+"${start_opts[@]}"}" >/dev/null || fatal "bisect: could not start"
  git bisect bad HEAD >/dev/null || fatal "bisect: could not mark HEAD bad"
  git bisect good "$good" >/dev/null || fatal "bisect: could not mark $good good"

  # git's own exit status cannot carry the answer: it is 0 on a culprit found, nonzero
  # both when only skipped commits are left and when the probe made it abort, and those
  # two mean different things to whoever asked. So what git said is read instead.
  local out="$logdir/bisect.out"
  T_LOGDIR="$logdir" git bisect run "$SELF" bisect-probe "${pass[@]+"${pass[@]}"}" "$@" 2>&1 | tee "$out"
  local -a ps=("${PIPESTATUS[@]}")
  local status=${ps[0]} culprit code
  git bisect log >"$logdir/bisect.log" 2>/dev/null || :

  # "bisect found first bad commit" in one git, "first 'bad' commit" in another, and the
  # term is whatever `git bisect terms` says: the quotes and the word are both optional
  if grep -qE "^bisect found first '?[a-z]*'? commit" "$out"; then
    culprit=$(sed -n "s/^\([0-9a-f]\{7,40\}\) is the first '\{0,1\}[a-z]*'\{0,1\} commit$/\1/p" "$out" | head -1)
    printf 't.sh: first bad commit is %s — the session is in %s/bisect.log, replayable with git bisect replay\n' \
      "$culprit" "$logdir"
    return 0
  fi
  if grep -q 'cannot continue any more' "$out"; then
    printf 't.sh: INCONCLUSIVE — only commits that could not answer are left between good and bad (%s/bisect.log)\n' \
      "$logdir" >&2
    return 89
  fi
  code=$(sed -n 's/^error: bisect run failed: exit code \([0-9]*\) from .*/\1/p' "$out" | head -1)
  if [[ -n "$code" ]] && ((code >= 128)); then
    # The probe passed a signal through so git would abort; end with the same one
    return "$code"
  fi
  fatal "bisect: git bisect run ended with exit $status and no verdict (see $out)"
}

# A passing suite says the code works. It does not say the suite would notice if the code
# stopped working, and that is the question worth asking of a green run. This answers it by
# applying, one at a time, edits a human wrote down — never edits it invented. Nothing here
# generates mutants: a tool that rewrites code on its own mostly produces code that will
# not compile, and a compiler error is not a test noticing anything.
DEF_NAME=()
DEF_FILE=()
DEF_FIND=()
DEF_REPLACE=()
DEF_WHY=()

# The one call a defects file makes. Sourced, so the file is plain bash and needs no parser.
defect() {
  (($# == 5)) ||
    die "defects: defect takes 5 arguments (name file find replace consequence), got $#"
  DEF_NAME+=("$1")
  DEF_FILE+=("$2")
  DEF_FIND+=("$3")
  DEF_REPLACE+=("$4")
  DEF_WHY+=("$5")
}

# Reads a file into the variable NAMED by $1, so putting it back is byte-for-byte rather
# than close enough. It assigns rather than prints for a reason: command substitution
# strips trailing newlines, so `var=$(slurp f)` would throw away the very thing the
# `printf x` dance exists to preserve — and a restore that drops a trailing newline leaves
# the working tree dirty in a way only a byte-wise diff notices.
slurp() { # slurp VARNAME FILE
  local __content
  __content=$(cat "$2" && printf x) || return 1
  printf -v "$1" '%s' "${__content%x}"
}

count_occurrences() {
  local haystack="$1" needle="$2" n=0
  while [[ "$haystack" == *"$needle"* ]]; do
    haystack="${haystack#*"$needle"}"
    n=$((n + 1))
  done
  printf '%d' "$n"
}

# A defect aimed at a test file proves nothing: the test file is executed, so the edit is
# "caught" by whatever it breaks, and the report reads as coverage the suite does not
# have. Vendored and generated code is nobody's guard either. The shapes are the usual
# ones; --any-file is for a list that knows better.
looks_like_test_file() {
  case "$1" in
    tests/* | test/* | spec/* | __tests__/* | */tests/* | */test/* | */spec/* | */__tests__/*) return 0 ;;
    *_test.* | *.test.* | *.spec.* | test_*.py | */test_*.py | *_spec.rb) return 0 ;;
    vendor/* | node_modules/* | third_party/* | */vendor/* | */node_modules/* | */third_party/*) return 0 ;;
    *_pb2.py | *.pb.go | *.generated.* | *.g.dart) return 0 ;;
  esac
  return 1
}

# A JSON string literal, for results.json: a consequence sentence may carry quotes
json_str() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

cmd_falsify() {
  local defects="tests/defects.sh" build="" filter="" logdir="" deadline="" out="falsify.out" any_file=""
  local -a pass=()
  while (($#)); do
    case "$1" in
      -d)
        defects="${2:?-d needs a file}"
        shift 2
        ;;
      --any-file)
        any_file=1
        shift
        ;;
      --out)
        out="${2:?--out needs a directory}"
        shift 2
        ;;
      --timeout)
        deadline="${2:?--timeout needs a number of seconds}"
        [[ "$deadline" =~ ^[0-9]+$ ]] || die "falsify: --timeout needs a number of seconds, got '$deadline'"
        shift 2
        ;;
      -b)
        build="${2:?-b needs a command}"
        shift 2
        ;;
      -l)
        # Kept here as well as forwarded: the suite runs go through run, but the log
        # each run's verdict is read from has to be a path this function chose
        logdir="${2:?-l needs a directory}"
        pass+=("$1" "$2")
        shift 2
        ;;
      -m | -p | -t)
        pass+=("$1" "${2:?$1 needs a value}")
        shift 2
        ;;
      --) break ;;
      *)
        [[ -z "$filter" ]] || die "falsify: only one filter may be given"
        filter="$1"
        shift
        ;;
    esac
  done
  [[ "${1:-}" == "--" ]] || die "falsify: the suite command must follow -- (t.sh falsify -- pytest -q)"
  [[ -r "$defects" ]] || die "falsify: cannot read $defects — write the defect list first (see templates/defects.sh)"
  # Everything a run found goes under one directory, in the shape cargo-mutants made
  # familiar: one file of names per verdict, which is what a diff or a grep wants; one
  # log per defect; and results.json for whatever reads machines. Written as the run
  # goes, so an interrupted run still leaves what it had found. Only the files this
  # writes are cleared first — the directory may be somebody's.
  rm -f "$out"/caught.txt "$out"/survived.txt "$out"/stale.txt "$out"/unusable.txt "$out"/timeout.txt "$out"/results.json
  rm -rf "$out/logs"
  mkdir -p "$out/logs" || fatal "falsify: cannot create $out"
  local -a RES_NAME=() RES_FILE=() RES_VERDICT=() RES_WHY=()
  write_results() {
    local i first=1
    {
      printf '{\n  "deadline": %s,\n  "defects": [' "${deadline:-null}"
      for i in "${!RES_NAME[@]}"; do
        if ((first)); then first=0; else printf ','; fi
        printf '\n    {"name": %s, "file": %s, "verdict": %s, "consequence": %s}' \
          "$(json_str "${RES_NAME[$i]}")" "$(json_str "${RES_FILE[$i]}")" \
          "$(json_str "${RES_VERDICT[$i]}")" "$(json_str "${RES_WHY[$i]}")"
      done
      printf '\n  ]\n}\n'
    } >"$out/results.json.new" && mv "$out/results.json.new" "$out/results.json"
  }
  record() { # record VERDICT NAME FILE CONSEQUENCE
    local list="$1"
    [[ "$list" != timedout ]] || list=timeout
    printf '%s\n' "$2" >>"$out/$list.txt"
    RES_NAME+=("$2")
    RES_FILE+=("$3")
    RES_VERDICT+=("$1")
    RES_WHY+=("$4")
    write_results
  }
  log_name() { # log_name DEFECT-NAME -> a file name: the slashes in a name become dashes
    local n="$1"
    printf '%s' "${n//\//-}"
  }

  # A dirty tree makes an interrupted restore indistinguishable from your own edits, and
  # this is a command that edits your source on purpose
  git rev-parse --git-dir >/dev/null 2>&1 || die "falsify: not inside a git repository"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "falsify: the working tree has uncommitted changes — commit or stash them first, so an interrupted run cannot be mistaken for your own edits"
  fi

  # shellcheck source=/dev/null
  source "$defects"
  ((${#DEF_NAME[@]} > 0)) || die "falsify: $defects declared no defects — an empty list proves nothing"

  local -a files=()
  local f i
  if [[ -z "$any_file" ]]; then
    for i in "${!DEF_NAME[@]}"; do
      looks_like_test_file "${DEF_FILE[$i]}" || continue
      die "falsify: ${DEF_NAME[$i]} edits ${DEF_FILE[$i]}, which looks like a test, vendored or generated file — a defect there proves nothing about the suite (--any-file if the list knows better)"
    done
  fi
  for f in "${DEF_FILE[@]}"; do
    [[ " ${files[*]-} " == *" $f "* ]] || files+=("$f")
  done
  # Two parallel arrays rather than one associative array: `declare -A` is bash 4.0+, and
  # macOS ships 3.2. `files` holds at most a handful of paths, so a linear lookup costs
  # nothing and the harness stays runnable wherever bash is.
  local -a originals=()
  local __slurped=""
  for f in "${files[@]}"; do
    [[ -r "$f" ]] || die "falsify: $defects names $f, which cannot be read"
    slurp __slurped "$f" || fatal "falsify: cannot read $f"
    originals+=("$__slurped")
  done

  # Assigns to the variable NAMED by $1, for the same reason slurp does: a value fetched
  # through $(...) loses its trailing newlines, and a `die` inside one would exit only the
  # subshell — here that would mean silently restoring a file to nothing.
  original_of() { # original_of VARNAME FILE
    local wanted="$2" i
    for i in "${!files[@]}"; do
      [[ "${files[$i]}" == "$wanted" ]] || continue
      printf -v "$1" '%s' "${originals[$i]}"
      return 0
    done
    fatal "falsify: $wanted has no recorded original — the defect list and the file list disagree"
  }

  # Restoration happens here and not only at the end of the loop, so an interrupt, a
  # failure or a kill cannot leave the source edited. The contents come from memory rather
  # than from git, so this needs neither a clean checkout nor git to be working.
  # shellcheck disable=SC2317  # reached through the trap, which shellcheck does not follow
  restore_all() {
    local i
    for i in "${!files[@]}"; do
      printf '%s' "${originals[$i]}" >"${files[$i]}" 2>/dev/null || :
    done
  }
  # EXIT covers a die or a fatal. INT and TERM restore and then die of the same signal,
  # because a handler that merely returns lets the script carry on: written that way,
  # Ctrl-C restored the file and the loop ran the next defect, with the interrupted one
  # gone from the report and still counted in the summary. `exit 130` would be wrong
  # too — the caller would see an exit rather than a signal, and a loop around this
  # would keep going.
  # The suite runs in its own process group (see suite_verdict), which Ctrl-C at the
  # terminal does not reach, so the group is ended here first
  MUTANT_PGID=""
  # shellcheck disable=SC2317  # reached through the traps
  end_mutant() {
    [[ -z "$MUTANT_PGID" ]] || kill -TERM -- -"$MUTANT_PGID" 2>/dev/null || :
  }
  trap 'restore_all' EXIT
  trap 'end_mutant; restore_all; trap - INT; kill -INT $$' INT
  trap 'end_mutant; restore_all; trap - TERM; kill -TERM $$' TERM

  # Assigns VERDICT — caught, survived, unusable, timedout, or none — rather than printing
  # it: a $(...) would swallow a die inside run, and the kind of verdict comes from run's
  # sidecar, never from the number, because the suite's own exit 79 is not the harness's.
  # run goes in a subshell so its own refusal ends that run and reaches here as "none".
  #
  # The run is watched against a deadline. A neutered guard is often a loop that no
  # longer ends — the increment removed from a counter is the canonical one — and without
  # a deadline that mutant would hang the whole falsification. The suite is started in
  # its own process group, under job control, so the deadline can end the runner and
  # everything it spawned, not just the shell around them; without GNU timeout(1), which
  # macOS does not have, that is what a watchdog is.
  VERDICT=""
  suite_verdict() { # suite_verdict LOG CMD...
    local log="$1" kind="" pid waited=0 grace=0
    shift
    VERDICT=none
    if [[ -n "$build" ]]; then
      if ! sh -c "$build" >"$log" 2>&1; then
        VERDICT=unusable
        return
      fi
    fi
    set -m
    (T_LOGFILE="$log" cmd_run -t 0 "${pass[@]+"${pass[@]}"}" "$@") >/dev/null 2>&1 &
    pid=$!
    set +m
    MUTANT_PGID="$pid"
    # Tenths of a second, so a fast suite is not held for a whole second per defect
    while kill -0 "$pid" 2>/dev/null; do
      if [[ -n "$deadline" ]] && ((waited >= deadline * 10)); then
        kill -TERM -- -"$pid" 2>/dev/null || :
        while kill -0 "$pid" 2>/dev/null && ((grace < 50)); do
          sleep 0.1
          grace=$((grace + 1))
        done
        kill -KILL -- -"$pid" 2>/dev/null || :
        wait "$pid" 2>/dev/null || :
        MUTANT_PGID=""
        VERDICT=timedout
        return
      fi
      sleep 0.1
      waited=$((waited + 1))
    done
    wait "$pid" 2>/dev/null || :
    MUTANT_PGID=""
    [[ ! -r "$log.verdict" ]] || kind=$(cat "$log.verdict")
    case "$kind" in
      pass) VERDICT=survived ;;
      lied) VERDICT=unusable ;;
      fail) VERDICT=caught ;;
    esac
  }

  echo "== the suite is green before anything is broken"
  # Falsification measures the distance between green and red. Starting red there is no
  # distance, and every "caught" below would be meaningless. The baseline is timed, and
  # the deadline for every mutant is five times that or twenty seconds, whichever is more
  # — five times leaves room for a slower path, twenty seconds for a fast suite whose
  # five times would be a fraction of a second. --timeout sets it outright.
  local started=$SECONDS
  suite_verdict "$out/logs/baseline.log" "$@"
  if [[ -z "$deadline" ]]; then
    deadline=$(((SECONDS - started) * 5))
    ((deadline >= 20)) || deadline=20
  fi
  case "$VERDICT" in
    survived) ;;
    caught)
      echo "t.sh: falsify: the suite is already failing — fix that first, or nothing measured here means anything" >&2
      return 85
      ;;
    unusable)
      echo "t.sh: falsify: the suite did not really run before any edit — check the build command and the log" >&2
      return 85
      ;;
    timedout)
      echo "t.sh: falsify: the suite did not finish within the --timeout before any edit was made" >&2
      return 85
      ;;
    *) fatal "falsify: the baseline run ended without a verdict — the harness could not run the suite (see $logdir)" ;;
  esac

  local i name file find replace why content mutated occurrences pristine
  local -a caught=() survived=() stale=() unusable=() timedout=() ran=()
  for i in "${!DEF_NAME[@]}"; do
    name="${DEF_NAME[$i]}"
    [[ -z "$filter" || "$name" == *"$filter"* ]] || continue
    file="${DEF_FILE[$i]}"
    find="${DEF_FIND[$i]}"
    replace="${DEF_REPLACE[$i]}"
    why="${DEF_WHY[$i]}"
    ran+=("$name")

    original_of content "$file"
    occurrences=$(count_occurrences "$content" "$find")
    if ((occurrences != 1)); then
      # Not guessed at: a list that no longer describes the code has to say so, or it
      # quietly stops testing the thing it was written for
      printf 'stale     %s: its find text matches %s times in %s, not once\n' "$name" "$occurrences" "$file"
      stale+=("$name")
      record stale "$name" "$file" "$why"
      continue
    fi

    # Cut around the one occurrence rather than ${content//"$find"/"$replace"}: bash 3.2
    # keeps the quotes around the replacement as literal text, so every mutant on macOS
    # was `"if false"` and unusable, and unquoted, a `&` in the replacement is the match
    # itself from bash 5.2 on. Prefix and suffix have neither problem.
    mutated="${content%%"$find"*}$replace${content#*"$find"}"
    # Checked, because a write that fails leaves the pristine code in place, the suite
    # then passes against it, and that would be reported as a survivor: a read-only file
    # once made a guard the suite does cover read as one nobody checks
    printf '%s' "$mutated" >"$file" || fatal "falsify: cannot write $file — the tree is untouched, and nothing was measured"
    suite_verdict "$out/logs/$(log_name "$name").log" "$@"
    printf '%s' "$content" >"$file"

    case "$VERDICT" in
      caught)
        printf 'caught    %s\n' "$name"
        caught+=("$name")
        ;;
      survived)
        printf 'SURVIVED  %s: %s\n' "$name" "$why"
        survived+=("$name")
        ;;
      unusable)
        # The compiler noticed the syntax; the tests said nothing. Calling this "caught"
        # is how a suite gets credit for coverage it does not have — and calling it
        # SURVIVED, as this once did, blamed the suite for an edit that never reached it.
        printf 'unusable  %s: the edit stopped it building, so the tests were never asked\n' "$name"
        unusable+=("$name")
        ;;
      timedout)
        # Neither caught — that would credit the suite for a hang — nor SURVIVED, which
        # would blame it for an edit that never let it answer. Like stale, a fault of the
        # entry: the edit most likely made a loop that does not end.
        printf 'TIMEDOUT  %s: the suite did not finish within %ss, so it never gave a verdict\n' "$name" "$deadline"
        timedout+=("$name")
        ;;
      # No verdict is a suite run that ended without one — killed, most likely. Silently
      # matching nothing here is how a defect once vanished from the report.
      *) fatal "falsify: no verdict for $name — the suite run ended without one" ;;
    esac
    record "$VERDICT" "$name" "$file" "$why"
  done

  restore_all
  trap - EXIT INT TERM
  for f in "${files[@]}"; do
    slurp __slurped "$f" || fatal "falsify: cannot re-read $f to confirm it was restored"
    original_of pristine "$f"
    [[ "$__slurped" == "$pristine" ]] ||
      fatal "falsify: $f was not restored to what it was — restore it from git before doing anything else"
  done

  ((${#ran[@]} > 0)) || die "falsify: no defect matched the filter '$filter'"

  # Three kinds of not-caught, three different problems, three exit codes. A survivor is
  # the suite's problem. A stale or unusable entry is the list's: it no longer describes
  # the code, or it breaks the build rather than the behaviour, and a report that folded
  # those into the survivors blamed the tests for a list nobody had maintained.
  echo
  printf '%d caught, %d SURVIVED, %d stale, %d unusable, %d timed out, of %d defect(s) — %s/\n' \
    "${#caught[@]}" "${#survived[@]}" "${#stale[@]}" "${#unusable[@]}" "${#timedout[@]}" "${#ran[@]}" "$out"
  if ((${#survived[@]} > 0)); then
    printf 'the suite did not notice %d of them — read the SURVIVED lines: each names what nobody checks\n' "${#survived[@]}" >&2
    return 83
  fi
  if ((${#timedout[@]} > 0)); then
    printf '%d edit(s) never let the suite finish — an infinite loop, most likely; neuter the guard another way\n' "${#timedout[@]}" >&2
    return 84
  fi
  if ((${#stale[@]} > 0)); then
    printf 'the defect list has drifted from the code: %d find text(s) no longer match once\n' "${#stale[@]}" >&2
    return 87
  fi
  if ((${#unusable[@]} > 0)); then
    printf '%d edit(s) only stopped the build — neuter the guard instead, so the tests are asked\n' "${#unusable[@]}" >&2
    return 88
  fi
  printf 'all %d defect(s) were caught by the suite.\n' "${#ran[@]}"
}

cmd="${1:-}"
(($# == 0)) || shift
case "$cmd" in
  run) cmd_run "$@" ;;
  flaky) cmd_flaky "$@" ;;
  bisect) cmd_bisect "$@" ;;
  bisect-probe) cmd_bisect_probe "$@" ;;
  falsify) cmd_falsify "$@" ;;
  -h | --help | help) usage ;;
  '')
    usage >&2
    exit 64
    ;;
  *)
    printf 't.sh: no such subcommand: %s\n\n' "$cmd" >&2
    usage >&2
    exit 64
    ;;
esac
