#!/usr/bin/env bash
# The gate for this repository. It lints what the skill ships and then proves that each
# of its checks can actually go red — a check that has never failed is a decoration, and
# that is the one claim this skill is not allowed to make about itself.
#
# Nothing here touches the network, so it is safe on pull requests.
#
#   check.sh [lint|behaviour|all]
#
# Two halves, because they need different things. `lint` reads what the skill ships —
# scripts, workflows, docs, markers — and needs actionlint, shellcheck and shfmt from the
# flake's dev shell, never from whatever the runner has. `behaviour` runs t.sh against
# throwaway repositories and needs only bash and git, so it can be run under the bash 3.2
# that macOS ships, which is the one place the harness has broken before. `all` is both.
#
#   nix develop -c ./check.sh
#   /bin/bash ./check.sh behaviour        # on a macOS runner
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# One source of truth for what gets linted. A second copy of this list drifts, and a
# drifted list lies about what was checked.
scripts=(t.sh check.sh check-skill.sh check-pins.sh templates/defects.sh)

# The skill's own name, as the frontmatter, the readme and the symlink all spell it
skill_name=tests

fail() {
  echo "check: $1" >&2
  exit 1
}

# The throwaway repositories below must not inherit whatever git config this machine has:
# a global commit.gpgsign would try to sign their commits, a core.hooksPath would run
# somebody's hooks in them, and the gate would go red for a reason outside the repository
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
[[ -z "$(git config --global --list 2>/dev/null)" ]] ||
  fail "the gate can see a global git config — its fixture repositories would inherit it"

# Every t.sh below runs under the bash running this gate, not under whatever bash the
# shebang finds: on a macOS runner the gate is started as `/bin/bash ./check.sh` to prove
# the harness on the 3.2 that macOS ships, while `env bash` would find Homebrew's 5.
tsh() { "$BASH" "$HERE/t.sh" "$@"; }

# With a template, because the BSD mktemp on macOS wants one
work=$(mktemp -d "${TMPDIR:-/tmp}/check.XXXXXX")
trap 'rm -rf "$work"' EXIT

mode="${1:-all}"
case "$mode" in
  lint | behaviour | all) ;;
  *) fail "no such mode: '$mode' — lint, behaviour or all" ;;
esac

# Say which tool is missing, rather than dying halfway through with a bare "command not
# found" that the reader then has to trace back to a step
tools=(git)
[[ "$mode" == behaviour ]] || tools+=(actionlint shellcheck shfmt)
missing=()
for tool in "${tools[@]}"; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
((${#missing[@]} == 0)) ||
  fail "missing: ${missing[*]} — they are pinned in the flake, so run this as: nix develop -c ./check.sh"

check_lint() {
  echo "== the scripts parse and lint"
  for s in "${scripts[@]}"; do bash -n "$s"; done
  shellcheck "${scripts[@]}"
  shfmt -d -i 2 -ci "${scripts[@]}"

  echo "== the workflows are valid, and their tools come from the lock rather than a registry"
  # actionlint needs a git project to find workflows in, which the throwaway copies below are
  # not. Skipping it there is what lets a planted defect be the reason a copy fails; without
  # this the copies would all die here, and every "able to fail" proof would be vacuous while
  # the gate stayed green. Outside a nested run the workflows must exist.
  if [[ -n "${T_CHECK_NESTED:-}" ]]; then
    echo "   actionlint skipped in the nested copy, which is not a git project"
  else
    [[ -d .github/workflows ]] || fail ".github/workflows is missing — nothing gates this repository"
    actionlint
  fi
  # This repo follows its own advice about pinning: a job that resolves a tool at run time
  # changes behaviour with zero change in the repository. The guard is the ci skill's
  # check-pins.sh, copied verbatim, which proves on every run that it catches each shape
  # it claims to and stays quiet on the pinned spellings.
  ./check-pins.sh
  # And the pins have to be watched: a major tag moves within its major on its own, but
  # nothing says when GitHub retires the runtime an old major runs on, except a red run
  # with no change in the repository. dependabot's pull request arrives first.
  [[ -f .github/dependabot.yml ]] ||
    fail ".github/dependabot.yml is missing — the action pins in the workflows are watched by nobody"
  grep -q 'package-ecosystem: github-actions' .github/dependabot.yml ||
    fail ".github/dependabot.yml does not watch the github-actions ecosystem"

  echo "== SKILL.md loads, every reference is reachable, every link and anchor resolves"
  # The ci skill's gate for a skill repository, copied verbatim: the frontmatter an agent
  # loads the skill by, reachability as a real walk over links from SKILL.md, and every
  # relative link and heading anchor. It falsifies itself on copies of the repository.
  ./check-skill.sh -n "$skill_name" .

  echo "== no paragraph in any document is hard-wrapped"
  # GitHub soft-wraps, so a manual break inside a paragraph only means a one-word edit
  # reflows every line after it. The create-readme skill's rule for the readme, applied to
  # every document here: a reference is read by an agent and by a person on GitHub alike,
  # and the diff of a one-word edit should be one line in either.
  hard_wrapped() { # hard_wrapped FILE -> prints the offending line numbers
    awk '
    # the frontmatter is one key per line by definition, not prose
    NR == 1 && /^---$/ { front = 1; next }
    front { if (/^---$/) front = 0; next }
    /^```/ { fence = !fence; prev = 0; next }
    fence { next }
    # blank, heading, table, list, quote, html, badge, link or indented line: not prose
    /^[[:space:]]*$/ || /^[#|>< ]/ || /^[-*+]/ || /^[0-9]+\. / || /^!\[/ || /^\[/ { prev = 0; next }
    { if (prev) print NR; prev = 1 }
  ' "$1"
  }
  docs=(README.md SKILL.md CHANGELOG.md)
  while IFS= read -r f; do docs+=("$f"); done < <(find references -type f -name '*.md' | sort)
  ((${#docs[@]} > 3)) || fail "no references were found — the extractor is broken"
  for doc in "${docs[@]}"; do
    wrapped=$(hard_wrapped "$doc")
    [[ -z "$wrapped" ]] ||
      fail "$doc hard-wraps a paragraph at line(s): $(tr '\n' ' ' <<<"$wrapped")— one paragraph is one line"
  done

  echo "== every t.sh example in the docs uses flags that subcommand actually accepts"
  # A documented command is a hand-written mirror of the parser, and mirrors drift. This one
  # drifted the day it was written: two ecosystem references showed `t.sh run -b '...'`, and
  # `run` has no -b — the build phase belongs to falsify and bisect. Found by somebody trying
  # to follow the documentation, which is the expensive way to find it.
  flags_of() { # flags_of SUBCOMMAND [FILE] -> the flags its parser accepts, one per line
    # The function is found by prefix, not by regex. As a regex, "cmd_bisect()" holds an
    # empty group and matches cmd_bisect_probe too, which for a while hid that bisect's own
    # parser declared no flags at all: the probe's -b was being read as bisect's.
    awk -v want="cmd_${1//-/_}() {" '
    substr($0, 1, length(want)) == want { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside && match($0, /^ *(--?[a-zA-Z][a-zA-Z-]*)(\ *\|\ *--?[a-zA-Z][a-zA-Z-]*)*\)/) {
      line = substr($0, RSTART, RLENGTH)
      gsub(/[)| ]/, "\n", line)
      print line
    }
  ' "${2:-t.sh}" | grep -oE '^--?[a-zA-Z][a-zA-Z-]*$' | sort -u
  }
  # Proven on a synthetic file rather than on t.sh, where the two functions happen to agree
  # shellcheck disable=SC2016  # the $1 belongs to the synthetic parser being written out
  printf 'cmd_a() {\n  case "$1" in\n    -x) ;;\n  esac\n}\ncmd_a_b() {\n  case "$1" in\n    -y) ;;\n  esac\n}\n' >"$work/anchor.sh"
  [[ "$(flags_of a "$work/anchor.sh")" == "-x" ]] ||
    fail "flags_of reads past the function it was asked about: cmd_a_b's flags leaked into cmd_a's"
  examples=0
  while IFS= read -r example; do
    sub=$(awk '{print $2}' <<<"$example")
    [[ -n "$sub" && "$sub" != -* ]] || continue
    allowed=$(flags_of "$sub")
    [[ -n "$allowed" ]] || fail "the docs show 't.sh $sub' but no cmd_$sub parses anything — the extractor or the example is wrong"
    examples=$((examples + 1))
    # only the part before --, which is where flags live, and with quoted arguments
    # removed: the --workspace inside -b 'cargo build --workspace' is the build's flag
    before_ddash="${example%% -- *}"
    # shellcheck disable=SC2001  # ${var//'*'/} would be greedy across two quoted arguments
    before_ddash=$(sed "s/'[^']*'//g" <<<"$before_ddash")
    # `\b` would be shorter, and is GNU-only
    for flag in $(grep -oE ' --?[a-zA-Z][a-zA-Z-]*( |$)' <<<"$before_ddash" || :); do
      grep -qx -- "${flag# }" <<<"$allowed" ||
        fail "the docs show 't.sh $sub ${flag# }', which that subcommand does not accept: $example"
    done
  done < <(grep -rhoE '(^|\$ )t\.sh [a-z-]+[^|`]*' README.md SKILL.md references/ | sed 's/^\$ //')
  ((examples > 0)) || fail "no t.sh examples were found in the docs — the extractor is broken"

  echo "== every marker catches its own fixture, and no default one cries on a healthy run"
  # Read from the same files `t.sh run` reads, never from a second copy of the list: two
  # copies disagree within a month, and then the gate is testing the copy.
  #
  # Both halves of the rule apply to markers/default.txt. Only the first applies to the
  # per-ecosystem sets: they exist precisely because some of their lines DO appear in healthy
  # runs (`[no test files]` in a Go workspace), which is why they are opted into rather than
  # on by default.
  set_count=0
  for set_file in markers/*.txt; do
    name=$(basename "$set_file" .txt)
    fixture="tests/fixtures/lying/$name.log"
    [[ -r "$fixture" ]] || fail "$set_file has no fixture at $fixture — its entries are unproven"
    markers=()
    while IFS= read -r m; do
      [[ -z "$m" || "$m" == \#* ]] && continue
      markers+=("$m")
    done <"$set_file"
    # An extractor that finds nothing must say so rather than read as "all clear"
    ((${#markers[@]} > 0)) || fail "$set_file holds no markers — an empty set checks nothing"
    for m in "${markers[@]}"; do
      grep -qiF -- "$m" "$fixture" ||
        fail "the marker '$m' matches nothing in $fixture — a dead entry guards nothing"
      if [[ "$name" == default ]]; then
        ! grep -qiF -- "$m" tests/fixtures/clean.log ||
          fail "the default marker '$m' fires on tests/fixtures/clean.log — it would redden healthy runs"
      fi
    done
    set_count=$((set_count + 1))
  done
  ((set_count > 0)) || fail "no marker sets were found in markers/ — the glob is broken"

  # An ecosystem set repeating a default entry adds nothing: the default already applies to
  # every run, so the copy is dead weight that reads as extra coverage. Matched the way the
  # scan matches, case-insensitively and by containment: `No Tests Ran in 0.01s` repeats
  # `no tests ran` as surely as the same letters would, and an exact comparison missed both.
  defaults=()
  while IFS= read -r m; do
    [[ -z "$m" || "$m" == \#* ]] && continue
    defaults+=("$(tr '[:upper:]' '[:lower:]' <<<"$m")")
  done <markers/default.txt
  ((${#defaults[@]} > 0)) || fail "markers/default.txt holds no markers — the extractor is broken"
  for set_file in markers/*.txt; do
    [[ "$set_file" == markers/default.txt ]] && continue
    while IFS= read -r m; do
      [[ -z "$m" || "$m" == \#* ]] && continue
      lower=$(tr '[:upper:]' '[:lower:]' <<<"$m")
      for d in "${defaults[@]}"; do
        [[ "$lower" != *"$d"* ]] ||
          fail "$set_file repeats a marker that markers/default.txt already applies to every run: '$m' contains '$d'"
      done
    done <"$set_file"
  done
}

check_behaviour() {
  echo "== run refuses a marker set that would leave it checking nothing"
  status=0
  tsh run -t 0 -l "$work/logs" -m no-such-set -- true >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "run accepted a marker set that does not exist (got $status)"
  : >"$work/empty-markers.txt"
  status=0
  tsh run -t 0 -l "$work/logs" -m "$work/empty-markers.txt" -- true >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "run accepted an empty marker set, which reads as a working check (got $status)"

  echo "== a repository's own policy applies, and a broken one stops the run"
  # The config carries policy and never the command, so what runs stays visible in the line
  # you typed. Its failure mode to avoid is silence: a typo'd key that reads as "no policy"
  # leaves a repository believing in markers that were never loaded.
  conf="$work/conf"
  mkdir -p "$conf/tests"
  policy() { printf '%s\n' "$@" >"$conf/tests/t.conf"; }
  in_conf() { # in_conf EXPECTED DESCRIPTION -- CMD...
    local expected="$1" what="$2"
    shift 2
    local got=0
    (cd "$conf" && tsh run -t 0 -l "$work/logs" "$@") >/dev/null 2>&1 || got=$?
    ((got == expected)) || fail "$what: expected $expected, got $got"
  }
  policy 'markers rust'
  in_conf 79 "a marker set named in the config applies" -- sh -c 'echo "running 0 tests"; exit 0'
  policy 'pattern thread panicked in setup'
  in_conf 79 "a pattern named in the config applies" -- sh -c 'echo "thread panicked in setup"; exit 0'
  policy 'allow expected: no tests ran'
  in_conf 0 "a line the config excuses is excused" -- sh -c 'echo "expected: no tests ran"; exit 0'
  policy 'allow expected('
  in_conf 64 "an allow regex the config names but grep cannot compile refuses" -- sh -c 'echo "collected 0 items"; exit 0'
  # flaky obeys the same policy: a repository that named its log directory once should not
  # find one subcommand writing somewhere else
  policy 'logdir .from-config'
  rm -rf "$conf/.from-config"
  (cd "$conf" && tsh flaky 2 -- sh -c 'echo "1 passed"; exit 0') >/dev/null 2>&1 || :
  [[ -d "$conf/.from-config" ]] || fail "flaky ignored the log directory the config names"
  rm -rf "$conf/.from-config"
  policy 'command cargo test'
  in_conf 64 "an unknown key refuses rather than reading as no policy" -- true
  policy 'markers'
  in_conf 64 "a key with no value refuses" -- true
  policy 'markers nosuchset'
  in_conf 64 "a marker set the config names but does not exist refuses" -- true
  rm -f "$conf/tests/t.conf"
  in_conf 0 "a repository with no config is the normal case" -- sh -c 'echo "47 passed"; exit 0'
  # The template is the thing people copy, so it has to parse — an example config that the
  # harness refuses would teach the format wrong on the first try
  status=0
  T_CONFIG=templates/t.conf tsh run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed"; exit 0' \
    >/dev/null 2>&1 || status=$?
  ((status == 0)) || fail "templates/t.conf is not a config t.sh accepts (got $status)"

  echo "== a marker file checked out with CRLF does not turn every line into a finding"
  # Reported from a Windows runner, where git's autocrlf converts on checkout: a blank line
  # becomes a marker of one carriage return, `grep -F` finds that on every line of a CRLF
  # log, and a healthy `cargo test` is reported as a lie with a build line as the evidence.
  # The worst shape a marker bug can take — it reddens good runs, so it gets switched off.
  crlf_markers="$work/crlf-markers.txt"
  printf '# a comment\r\n\r\nno tests ran\r\ncollected 0 items\r\n' >"$crlf_markers"
  status=0
  tsh run -t 0 -l "$work/logs" -m "$crlf_markers" \
    -- sh -c 'printf "Compiling windows-link v0.2.1\r\ntest result: ok. 12 passed\r\n"; exit 0' \
    >/dev/null 2>&1 || status=$?
  ((status == 0)) || fail "a CRLF marker file reddened a healthy CRLF run (got $status)"
  status=0
  tsh run -t 0 -l "$work/logs" -m "$crlf_markers" \
    -- sh -c 'printf "collected 0 items\r\n"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 79)) || fail "a CRLF marker file stopped catching what it names (got $status)"

  echo "== run reports the command's own status, where a pipe would report zero"
  # The whole reason this harness exists: `cmd | tail` exits 0 for a suite that just failed
  status=0
  tsh run -t 0 -l "$work/logs" -- sh -c 'echo working; exit 7' >/dev/null 2>&1 || status=$?
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
  tsh run -t 0 -l "$work/logs" -- sh -c 'echo "collected 0 items"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 79)) || fail "run reported $status for a green run whose log said no tests were collected"

  echo "== an honest green run is still a pass"
  status=0
  tsh run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed in 1.83s"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 0)) || fail "run reported $status for a healthy run — it would cry wolf"

  echo "== run writes the kind of verdict it reached beside the log"
  # A number cannot say whether 79 was the harness's verdict or the command's own status,
  # so the kind goes in a sidecar, and the subcommands that run cmd_run in a subshell
  # read that instead of guessing from the number
  for pair in 'fail:exit 7' 'lied:echo "collected 0 items"; exit 0' 'pass:echo "47 passed"; exit 0'; do
    want=${pair%%:*}
    cmd=${pair#*:}
    rm -f "$work/verdict.log" "$work/verdict.log.verdict"
    T_LOGFILE="$work/verdict.log" tsh run -t 0 -l "$work/logs" -- sh -c "$cmd" >/dev/null 2>&1 || :
    grep -qx "$want" "$work/verdict.log.verdict" 2>/dev/null ||
      fail "run did not record '$want' beside its log for: $cmd"
  done

  echo "== T_ALLOW excuses a marker the repository expects, and nothing else"
  status=0
  T_ALLOW='expected: no tests ran' tsh run -t 0 -l "$work/logs" \
    -- sh -c 'echo "expected: no tests ran"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 0)) || fail "T_ALLOW did not excuse the line it names (got $status)"
  status=0
  T_ALLOW='something else entirely' tsh run -t 0 -l "$work/logs" \
    -- sh -c 'echo "expected: no tests ran"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 79)) || fail "T_ALLOW excused a line it does not name (got $status) — it excuses everything"
  # A regex grep cannot compile used to leave the filtered log empty, and an empty log has
  # no markers: the worst shape, because a typo in the excuse list made every run a pass
  status=0
  T_ALLOW='expected(' tsh run -t 0 -l "$work/logs" \
    -- sh -c 'echo "collected 0 items"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "a regex grep cannot compile was accepted as an allow list (got $status) — an empty filtered log reads as clean"

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
    tsh run -t 0 -l "$readonly_dir" -- sh -c 'exit 0' >/dev/null 2>&1 || status=$?
    ((status == 70)) || fail "run started with nowhere to put its log (got $status)"
  fi

  echo "== run refuses a command that was not put after --"
  status=0
  tsh run sh -c 'exit 0' >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "run accepted a command without -- (got $status); guessing is how the wrong thing gets run"

  echo "== run refuses a tail length that is not a number, and counts a marker set once"
  status=0
  tsh run -t abc -l "$work/logs" -- sh -c 'exit 1' >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "run accepted -t abc (got $status); (( )) reads a word as zero, so the tail silently vanished"
  findings=$(tsh run -t 0 -m rust -m rust -l "$work/logs" -- sh -c 'echo "running 0 tests"; exit 0' 2>&1 |
    grep -c '^  \[running 0 tests\]' || :)
  ((findings == 1)) || fail "a marker set named twice printed its finding $findings times, not once"

  echo "== run finds its markers through a symlink, absolute and relative"
  # `ln -s .../t.sh ~/.local/bin/t.sh` is how the harness gets onto a PATH. dirname of the
  # link once looked for markers/ beside the link, so every run through it refused.
  mkdir -p "$work/bin" "$work/rel/bin"
  ln -s "$HERE/t.sh" "$work/bin/t.sh"
  ln -s ../../bin/t.sh "$work/rel/bin/t.sh"
  for link in "$work/bin/t.sh" "$work/rel/bin/t.sh"; do
    status=0
    "$link" run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed"; exit 0' >/dev/null 2>&1 || status=$?
    ((status == 0)) || fail "run through the symlink $link could not find its markers (got $status)"
  done

  echo "== flaky calls a command that always agrees with itself stable"
  status=0
  tsh flaky 3 -l "$work/logs" -- sh -c 'echo "3 passed"; exit 0' >/dev/null 2>&1 || status=$?
  ((status == 0)) || fail "flaky called a deterministic green command unstable (got $status)"
  status=0
  tsh flaky 3 -l "$work/logs" -- sh -c 'echo "1 failed"; exit 1' >/dev/null 2>&1 || status=$?
  ((status == 1)) || fail "flaky did not pass through the status of a command that always fails (got $status)"

  echo "== flaky notices a command that disagrees with itself"
  # Deterministic divergence: the first run passes, every run after it fails
  counter="$work/flaky-counter"
  rm -f "$counter"
  status=0
  # shellcheck disable=SC2016  # $0 and $n belong to the inner sh, not to this script
  tsh flaky 3 -l "$work/logs" -- \
    sh -c 'n=$(cat "$0" 2>/dev/null || echo 0); echo $((n + 1)) >"$0"; test "$n" -eq 0' "$counter" \
    >/dev/null 2>&1 || status=$?
  ((status == 86)) || fail "flaky missed a command whose runs disagreed (got $status)"

  echo "== flaky refuses the arguments that would make it meaningless"
  status=0
  tsh flaky 1 -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "flaky accepted a single run, which cannot show disagreement (got $status)"
  status=0
  tsh flaky 3 -l "$work/logs" sh -c 'exit 0' >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "flaky accepted a command that was not put after -- (got $status)"
  # A refusal has to be heard. flaky mutes the command's output for each run, and for a
  # while muted run's own refusals with it: `flaky 3 -x` exited 2 without a word.
  status=0
  tsh flaky 3 -x -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>"$work/flaky.err" || status=$?
  ((status == 64)) || fail "flaky accepted an unknown flag (got $status)"
  grep -q 'flaky:' "$work/flaky.err" || fail "flaky refused an unknown flag without saying so"
  status=0
  tsh flaky 3 -m no-such-set -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>"$work/flaky.err" || status=$?
  ((status == 64)) || fail "flaky accepted a marker set that does not exist (got $status)"
  [[ -s "$work/flaky.err" ]] || fail "flaky refused a marker set silently"
  # And a refusal only run can make, once the loop has started, is shown too
  status=0
  T_ALLOW='expected(' tsh flaky 3 -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>"$work/flaky.err" || status=$?
  ((status == 70)) || fail "flaky carried on after run refused its allow regex (got $status)"
  grep -q 'allow' "$work/flaky.err" || fail "flaky hid run's refusal of the allow regex"

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
  bisect_out=$(cd "$repo" && tsh bisect "$first_good" -b 'test -f builds' -- test -f passes 2>&1) ||
    status=$?
  ((status == 0)) || fail "bisect exited $status on a history it should have resolved:"$'\n'"$bisect_out"
  grep -qF "$first_bad" <<<"$bisect_out" ||
    fail "bisect did not name $first_bad as the first bad commit:"$'\n'"$bisect_out"
  # And it must leave the repository where it found it, not detached mid-bisect
  [[ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" == master ]] ||
    fail "bisect left the repository detached instead of resetting it"
  # git's session log is the one artifact a wrong answer can be corrected from
  bisect_logdir=$(sed -n 's/^t.sh: logs for this bisect are in //p' <<<"$bisect_out")
  [[ -f "$bisect_logdir/bisect.log" ]] || fail "bisect did not keep git's session log for a replay"
  # git's own options pass through to git bisect start
  status=0
  bisect_out=$(cd "$repo" && tsh bisect "$first_good" --first-parent -b 'test -f builds' -- test -f passes 2>&1) ||
    status=$?
  ((status == 0)) || fail "bisect exited $status with --first-parent on a linear history:"$'\n'"$bisect_out"
  grep -qF "$first_bad" <<<"$bisect_out" || fail "bisect with --first-parent did not name $first_bad"

  echo "== bisect says so when every commit between good and bad was skipped"
  # git prints "cannot continue any more" and exits nonzero; passed through raw, that once
  # read as a usage error, and the harness said nothing of its own about the answer
  stuck="$work/bisect-stuck"
  mkdir -p "$stuck"
  git -C "$stuck" init -q -b master
  git -C "$stuck" config user.name check
  git -C "$stuck" config user.email check@example.invalid
  : >"$stuck/builds"
  git -C "$stuck" add -A && git -C "$stuck" commit -q -m "good: it builds"
  stuck_good=$(git -C "$stuck" rev-parse HEAD)
  rm "$stuck/builds"
  git -C "$stuck" add -A && git -C "$stuck" commit -q -m "does not build"
  echo x >"$stuck/note" && git -C "$stuck" add -A && git -C "$stuck" commit -q -m "still does not build"
  status=0
  stuck_out=$(cd "$stuck" && tsh bisect "$stuck_good" -b 'test -f builds' -- false 2>&1) || status=$?
  ((status == 89)) || fail "bisect exited $status where nothing between good and bad could answer (want 89):"$'\n'"$stuck_out"
  grep -q 'INCONCLUSIVE' <<<"$stuck_out" || fail "bisect did not say its answer was inconclusive"
  [[ "$(git -C "$stuck" rev-parse --abbrev-ref HEAD)" == master ]] ||
    fail "an inconclusive bisect left the repository detached"

  echo "== bisect refuses to start over a bisect already in progress"
  # git bisect start resets an in-progress bisect without a word
  git -C "$repo" bisect start >/dev/null
  status=0
  (cd "$repo" && tsh bisect "$first_good" -- true) >/dev/null 2>&1 || status=$?
  git -C "$repo" bisect reset >/dev/null 2>&1
  ((status == 64)) || fail "bisect started over a bisect already in progress (got $status)"

  echo "== every status a commit can produce maps to the right bisect verdict"
  # Asserted on the probe directly rather than through a bisect: which commits git chooses
  # to visit is its own business, so a skip may simply never happen in a given history. A
  # check that only sometimes exercises the branch it guards is not a check.
  probe() { # probe EXPECTED DESCRIPTION -- CMD...
    local expected="$1" what="$2"
    shift 2
    local got=0
    (cd "$repo" && tsh bisect-probe -l "$work/logs" "$@") >/dev/null 2>&1 || got=$?
    ((got == expected)) || fail "a commit that $what should be $expected to git bisect, but the probe said $got"
  }
  probe 0 "builds and passes" -b true -- true
  probe 1 "builds and fails" -b true -- false
  probe 125 "does not build" -b false -- true
  probe 125 "has no test runner (exit 127)" -- sh -c 'exit 127'
  probe 125 "runs nothing while exiting 0" -- sh -c 'echo "collected 0 items"; exit 0'
  # The command's own low numbers are its own: make exits 2 on any failure, and for a while
  # the probe took 2 for "the harness could not run it" and skipped every failing commit
  probe 1 "fails the way make does, with exit 2" -- sh -c 'exit 2'
  probe 1 "fails with exit 3" -- sh -c 'exit 3'
  probe 125 "has a runner that is not executable (exit 126)" -- sh -c 'exit 126'
  probe 125 "cannot be run by the harness at all" -m no-such-set -- true
  # 128+n means killed by a signal, and git bisect ABORTS on anything above 127 rather than
  # treating it as a verdict. A crash is the code at this commit misbehaving, so it is
  # clamped to "bad" and the session goes on; a person stopping the run is not evidence
  # about the commit, so it is passed through and the session ends, which is what Ctrl-C
  # is for.
  probe 1 "is killed by a signal" -- sh -c 'kill -SEGV $$'
  probe 130 "is interrupted by the user" -- sh -c 'kill -INT $$'
  probe 143 "is terminated from outside" -- sh -c 'kill -TERM $$'

  echo "== bisect refuses to start on a working tree it would trample"
  # A TRACKED file has to change: `passes` is deleted at HEAD, so writing it would only add
  # an untracked file, which `git diff --quiet` does not see. Written that way, this check
  # held for a year on git's own refusal to check out over the untracked file, and t.sh's
  # dirty-tree refusal was never exercised at all.
  echo dirty >>"$repo/note"
  status=0
  (cd "$repo" && tsh bisect "$first_good" -- true) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "bisect started with uncommitted changes in the tree (got $status)"
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
  fal_out=$(cd "$fal" && tsh falsify -b 'sh -n impl.sh' -l "$work/logs" --out "$work/falsify.out" -- sh suite.sh 2>&1) || status=$?
  ((status == 83)) || fail "falsify exited $status where a defect went unnoticed (want 83):"$'\n'"$fal_out"
  grep -q '^caught    clamp/negative' <<<"$fal_out" ||
    fail "falsify did not credit the suite for the guard it does cover:"$'\n'"$fal_out"
  grep -q '^SURVIVED  strip/spaces' <<<"$fal_out" ||
    fail "falsify did not report the guard nothing checks:"$'\n'"$fal_out"
  # A survivor is only actionable next to the code it names
  if ! grep -qF "impl.sh:3  - tr -d ' '" <<<"$fal_out" || ! grep -qF "impl.sh:3  + cat" <<<"$fal_out"; then
    fail "falsify reported the survivor without saying where the edit is and what it was:"$'\n'"$fal_out"
  fi
  grep -q '^stale     gone/drifted' <<<"$fal_out" ||
    fail "falsify guessed at a find text that no longer matches instead of reporting it stale:"$'\n'"$fal_out"
  # The one the user has to be able to trust: an edit that only breaks the build is not
  # evidence that any test noticed anything
  grep -q '^unusable  syntax/broken' <<<"$fal_out" ||
    fail "falsify credited the suite for an edit that merely stopped the code building:"$'\n'"$fal_out"
  echo "== falsify leaves what it found where a diff and a grep can read it"
  # One file of names per verdict, a log per defect, results.json for machines
  fo="$work/falsify.out"
  grep -qx 'clamp/negative' "$fo/caught.txt" || fail "falsify.out/caught.txt does not name the caught defect"
  grep -qx 'strip/spaces' "$fo/survived.txt" || fail "falsify.out/survived.txt does not name the survivor"
  grep -qx 'gone/drifted' "$fo/stale.txt" || fail "falsify.out/stale.txt does not name the stale entry"
  grep -qx 'syntax/broken' "$fo/unusable.txt" || fail "falsify.out/unusable.txt does not name the unusable entry"
  [[ -s "$fo/logs/clamp-negative.log" ]] || fail "falsify.out/logs has no log for clamp/negative"
  [[ -s "$fo/logs/baseline.log" ]] || fail "falsify.out/logs has no log for the baseline run"
  [[ "$(grep -c '"verdict": "survived"' "$fo/results.json")" == 1 ]] ||
    fail "results.json does not carry exactly one survivor"
  grep -q '"consequence": "a name keeps the spaces' "$fo/results.json" ||
    fail "results.json does not carry the consequence sentence"
  grep -q '"file": "impl.sh", "line": 3, "verdict": "survived"' "$fo/results.json" ||
    fail "results.json does not carry the survivor's file and line"

  echo "== falsify puts the source back byte for byte"
  cmp -s "$fal/impl.sh" "$work/impl.sh.pristine" ||
    fail "falsify did not restore impl.sh byte for byte"
  git -C "$fal" diff --quiet || fail "falsify left the working tree dirty"

  echo "== the exit code says which kind of not-caught ended the run"
  # A weak suite (83), a list that drifted (87), an edit that only broke the build (88).
  # Folded into one status, CI could not tell the tests being weak from the list having
  # rotted. After the byte-for-byte check above, because these refuse on a dirty tree.
  status=0
  (cd "$fal" && tsh falsify -l "$work/logs" gone -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 87)) || fail "falsify exited $status on a list whose only defect is stale (want 87)"
  status=0
  (cd "$fal" && tsh falsify -b 'sh -n impl.sh' -l "$work/logs" syntax -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 88)) || fail "falsify exited $status on a list whose only defect breaks the build (want 88)"
  status=0
  (cd "$fal" && tsh falsify -l "$work/logs" clamp -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 0)) || fail "falsify exited $status on a list whose only defect is caught (want 0)"

  echo "== --since narrows the list to the files a change touched, and says so when that is nothing"
  # In a clone, so the fixture's history stays what the checks above and below expect
  since_repo="$work/since-repo"
  git clone -q "$fal" "$since_repo"
  git -C "$since_repo" config user.name check
  git -C "$since_repo" config user.email check@example.invalid
  echo note >"$since_repo/note.txt"
  git -C "$since_repo" add note.txt && git -C "$since_repo" commit -q -m "a note, no code"
  status=0
  since_out=$(cd "$since_repo" && tsh falsify --since HEAD~1 -l "$work/logs" --out "$work/fo-since" -- sh suite.sh 2>&1) || status=$?
  ((status == 0)) || fail "falsify --since exited $status where no defect names a changed file (want 0):"$'\n'"$since_out"
  grep -q '^nothing to falsify' <<<"$since_out" || fail "falsify --since ran nothing and did not say so:"$'\n'"$since_out"
  printf '# touched\n' >>"$since_repo/impl.sh"
  git -C "$since_repo" add impl.sh && git -C "$since_repo" commit -q -m "impl.sh changed"
  status=0
  since_out=$(cd "$since_repo" && tsh falsify --since HEAD~1 -l "$work/logs" --out "$work/fo-since" -- sh suite.sh 2>&1) || status=$?
  ((status == 83)) || fail "falsify --since exited $status where impl.sh changed and its survivor should run (want 83):"$'\n'"$since_out"
  grep -q '^SURVIVED  strip/spaces' <<<"$since_out" || fail "falsify --since skipped a defect in the changed file:"$'\n'"$since_out"
  status=0
  (cd "$since_repo" && tsh falsify --since no-such-ref -l "$work/logs" --out "$work/fo-since" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "falsify accepted --since with a ref that does not exist (got $status)"

  echo "== --worktree falsifies a checkout of HEAD and leaves the tree in front of you alone"
  # The suite prints where it runs, so the log can show it was not the fixture's tree
  status=0
  wt_out=$(cd "$fal" && tsh falsify --worktree -l "$work/logs" --out "$work/fo-wt" -- sh -c 'pwd; sh suite.sh' 2>&1) || status=$?
  ((status == 83)) || fail "falsify --worktree exited $status (want 83, the survivor is still there):"$'\n'"$wt_out"
  grep -q '^SURVIVED  strip/spaces' <<<"$wt_out" || fail "falsify --worktree lost the survivor:"$'\n'"$wt_out"
  suite_ran_in=$(head -1 "$work/fo-wt/logs/strip-spaces.log")
  [[ -n "$suite_ran_in" && "$suite_ran_in" != "$fal" ]] ||
    fail "falsify --worktree ran the suite in the fixture's own tree ($suite_ran_in), not in a worktree"
  [[ "$(git -C "$fal" worktree list | wc -l)" -eq 1 ]] || fail "falsify --worktree left a worktree behind"
  git -C "$fal" diff --quiet || fail "falsify --worktree touched the tree in front of you"
  [[ ! -e "$fal/FALSIFY-IN-PROGRESS" ]] || fail "falsify --worktree put its in-flight marker in the tree in front of you"
  [[ ! -e "$work/fo-wt/in-flight" ]] || fail "falsify left its in-flight marker after finishing"

  echo "== on a GitHub runner a finding is also an annotation on the file and line"
  # A finding next to the code is read by whoever is about to merge it; in a log, by
  # whoever opens the log. The variable is cleared for the negative, because the gate
  # itself runs on such a runner.
  status=0
  gh_out=$(cd "$fal" && GITHUB_ACTIONS=true tsh falsify -b 'sh -n impl.sh' -l "$work/logs" --out "$work/fo-gh" -- sh suite.sh 2>&1) || status=$?
  grep -qF '::error file=impl.sh,line=3,title=falsify::SURVIVED strip/spaces: a name keeps the spaces' <<<"$gh_out" ||
    fail "falsify on a GitHub runner did not annotate the survivor:"$'\n'"$gh_out"
  grep -qF '::warning file=impl.sh,title=falsify::stale gone/drifted' <<<"$gh_out" ||
    fail "falsify on a GitHub runner did not annotate the stale entry:"$'\n'"$gh_out"
  grep -qF '::warning file=impl.sh,line=2,title=falsify::unusable syntax/broken' <<<"$gh_out" ||
    fail "falsify on a GitHub runner did not annotate the unusable entry:"$'\n'"$gh_out"
  status=0
  plain_out=$(cd "$fal" && GITHUB_ACTIONS='' tsh falsify -b 'sh -n impl.sh' -l "$work/logs" --out "$work/fo-gh" -- sh suite.sh 2>&1) || status=$?
  ! grep -q '^::' <<<"$plain_out" || fail "falsify printed GitHub annotations off a GitHub runner"

  echo "== a defect that never lets the suite finish is timed out, not caught"
  # A neutered guard is often a loop that no longer ends. Without a deadline it hung the
  # whole falsification; credited as caught it would reward the suite for a hang.
  printf "defect 'clamp/hang' 'impl.sh' 'echo 0; else' 'while :; do sleep 1; done; else' 'a hang'\n" >"$fal/tests/hang.sh"
  # Under a watchdog of its own, because the thing being checked is that falsify does not
  # hang, and a check that hangs when it fails is not a check. Job control, so the group
  # can be ended if it comes to that.
  set -m
  (cd "$fal" && exec "$BASH" "$HERE/t.sh" falsify -d tests/hang.sh --timeout 1 -l "$work/logs" -- sh suite.sh) \
    >"$work/hang.out" 2>&1 &
  hang_pid=$!
  set +m
  hang_waited=0
  while kill -0 "$hang_pid" 2>/dev/null && ((hang_waited < 200)); do
    sleep 0.1
    hang_waited=$((hang_waited + 1))
  done
  if kill -0 "$hang_pid" 2>/dev/null; then
    kill -TERM -- -"$hang_pid" 2>/dev/null || :
    sleep 1
    kill -KILL -- -"$hang_pid" 2>/dev/null || :
    wait "$hang_pid" 2>/dev/null || :
    git -C "$fal" checkout -q -- . 2>/dev/null || :
    fail "a defect that hangs the suite hangs falsify with it, twenty seconds and counting — nothing timed it out"
  fi
  status=0
  wait "$hang_pid" || status=$?
  fal_out=$(cat "$work/hang.out")
  ((status == 84)) || fail "falsify exited $status on a defect that hangs the suite (want 84):"$'\n'"$fal_out"
  grep -q '^TIMEDOUT  clamp/hang' <<<"$fal_out" || fail "falsify did not report the hanging defect as timed out:"$'\n'"$fal_out"
  cmp -s "$fal/impl.sh" "$work/impl.sh.pristine" || fail "falsify did not put impl.sh back after a timeout"
  status=0
  (cd "$fal" && tsh falsify --timeout abc -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "falsify accepted --timeout abc (got $status)"

  echo "== an interrupted falsify dies interrupted, with the source put back"
  # A trap that only restored and returned let the loop carry on: Ctrl-C stopped nothing,
  # the interrupted defect vanished from the report, and the summary still counted it
  printf '#!/bin/sh\nsleep 1\nsh suite.sh\n' >"$fal/slow.sh"
  git -C "$fal" add slow.sh && git -C "$fal" commit -q -m "a slow suite"
  # exec, so the PID below is t.sh's own and the signal reaches the trap being tested; and
  # under job control, because without it a script's background jobs IGNORE SIGINT, an
  # ignored signal cannot be trapped, and this check would find nothing to interrupt
  set -m
  (cd "$fal" && exec "$BASH" "$HERE/t.sh" falsify -l "$work/logs" -- sh slow.sh) >"$work/interrupted.out" 2>&1 &
  falsify_pid=$!
  set +m
  sleep 0.5
  kill -INT "$falsify_pid"
  status=0
  wait "$falsify_pid" || status=$?
  ((status >= 128)) || fail "falsify carried on after an interrupt (got $status):"$'\n'"$(cat "$work/interrupted.out")"
  ! grep -q 'defect(s)' "$work/interrupted.out" || fail "an interrupted falsify still printed its summary"
  cmp -s "$fal/impl.sh" "$work/impl.sh.pristine" || fail "an interrupted falsify did not put impl.sh back"
  git -C "$fal" diff --quiet || fail "an interrupted falsify left the working tree dirty"

  echo "== a mutant that could not be written is not a survivor"
  # A write that fails leaves the pristine code in place; the suite passes against it, and
  # that used to be reported as SURVIVED for a guard the suite does cover. git tracks only
  # the executable bit, so the read-only file still counts as a clean tree.
  if [[ $EUID -eq 0 ]]; then
    echo "   skipped: running as root, which can write a read-only file"
  else
    chmod a-w "$fal/impl.sh"
    status=0
    fal_out=$(cd "$fal" && tsh falsify -l "$work/logs" -- sh suite.sh 2>&1) || status=$?
    chmod u+w "$fal/impl.sh"
    ((status == 70)) || fail "falsify measured a mutant it could not write (got $status):"$'\n'"$fal_out"
    ! grep -q 'SURVIVED' <<<"$fal_out" || fail "falsify credited a read-only source file with a survivor"
  fi

  echo "== falsify refuses the situations where its answer would be meaningless"
  status=0
  (cd "$fal" && tsh falsify -l "$work/logs" -- sh -c 'exit 1') >/dev/null 2>&1 || status=$?
  ((status == 85)) || fail "falsify measured against an already-failing suite (got $status, want 85)"
  status=0
  (cd "$fal" && tsh falsify -l "$work/logs" -- sh -c 'echo "collected 0 items"; exit 0') \
    >/dev/null 2>&1 || status=$?
  ((status == 85)) || fail "falsify measured against a suite that never really ran (got $status, want 85)"
  echo dirt >"$fal/impl.sh.tmp" && mv "$fal/impl.sh.tmp" "$fal/impl.sh"
  status=0
  (cd "$fal" && tsh falsify -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "falsify started on a dirty tree, where an interrupted restore looks like your own edits (got $status)"
  git -C "$fal" checkout -q -- .
  status=0
  : >"$fal/tests/empty.sh"
  (cd "$fal" && tsh falsify -d tests/empty.sh -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "falsify accepted an empty defect list, which proves nothing (got $status)"
  # A defect declared as one nothing can catch is expected to survive, and no finding;
  # the day the suite catches it, the declaration is stale
  printf "defect 'strip/spaces' 'impl.sh' \"tr -d ' '\" 'cat' 'spaces stay' expect survived 'no caller strips yet'\n" >"$fal/tests/expected.sh"
  status=0
  fal_out=$(cd "$fal" && tsh falsify -d tests/expected.sh -l "$work/logs" --out "$work/fo3" -- sh suite.sh 2>&1) || status=$?
  ((status == 0)) || fail "a defect declared as expected to survive was reported as a survivor (got $status):"$'\n'"$fal_out"
  grep -q '^expected  strip/spaces: no caller strips yet' <<<"$fal_out" || fail "falsify did not report the expected survivor as expected:"$'\n'"$fal_out"
  grep -qx 'strip/spaces' "$work/fo3/expected.txt" || fail "falsify.out/expected.txt does not name the expected survivor"
  printf "defect 'clamp/negative' 'impl.sh' 'if [ \"\$1\" -lt 0 ]' 'if false' 'negatives leak' expect survived 'wrong'\n" >"$fal/tests/expected-wrong.sh"
  status=0
  fal_out=$(cd "$fal" && tsh falsify -d tests/expected-wrong.sh -l "$work/logs" --out "$work/fo3" -- sh suite.sh 2>&1) || status=$?
  ((status == 87)) || fail "a declaration the suite disproved was not reported stale (got $status, want 87):"$'\n'"$fal_out"
  grep -q '^stale     clamp/negative: declared as one nothing can catch' <<<"$fal_out" || fail "falsify did not say the expectation was disproved:"$'\n'"$fal_out"
  printf "defect 'x/y' 'impl.sh' 'a' 'b' 'c' expect caught 'z'\n" >"$fal/tests/expected-bad.sh"
  status=0
  (cd "$fal" && tsh falsify -d tests/expected-bad.sh -l "$work/logs" --out "$work/fo3" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "falsify accepted 'expect caught', which is not a thing (got $status)"
  # The template is the thing people copy, so every form it shows has to parse: falsify
  # must get as far as the files it names, which this fixture does not have
  status=0
  tpl_out=$(cd "$fal" && tsh falsify -d "$HERE/templates/defects.sh" -l "$work/logs" -- sh suite.sh 2>&1) || status=$?
  ((status == 64)) || fail "templates/defects.sh is not a list falsify accepts (got $status):"$'\n'"$tpl_out"
  grep -q 'which cannot be read' <<<"$tpl_out" ||
    fail "templates/defects.sh was refused before its entries were read:"$'\n'"$tpl_out"
  grep -q "expect survived '" templates/defects.sh || fail "templates/defects.sh shows no declared exception"
  # A defect in a test file is "caught" by whatever it breaks and reads as coverage
  printf 'helper=1\n' >"$fal/tests/helper.sh"
  git -C "$fal" add tests/helper.sh && git -C "$fal" commit -q -m "a helper under tests/"
  printf "defect 'helper/edited' 'tests/helper.sh' 'helper=1' 'helper=2' 'nothing'\n" >"$fal/tests/in-tests.sh"
  status=0
  (cd "$fal" && tsh falsify -d tests/in-tests.sh -l "$work/logs" --out "$work/fo2" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "falsify accepted a defect aimed at a test file (got $status)"
  status=0
  (cd "$fal" && tsh falsify -d tests/in-tests.sh --any-file -l "$work/logs" --out "$work/fo2" -- sh suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 83)) || fail "falsify with --any-file did not run the defect in the test file (got $status, want 83)"

  echo "== prove takes the fix out of a commit and requires its tests to go red"
  # A clone, with commits of every shape prove has to tell apart: a test that pins its
  # fix, a test that does not, a fix without which nothing builds, a commit with no fix
  prove_repo="$work/prove-repo"
  git clone -q "$fal" "$prove_repo"
  git -C "$prove_repo" config user.name check
  git -C "$prove_repo" config user.email check@example.invalid
  pcommit() { # pcommit MESSAGE
    git -C "$prove_repo" add -A
    git -C "$prove_repo" commit -q -m "$1"
  }
  # The suite has to live where prove can tell it from the code: under tests/
  mkdir -p "$prove_repo/tests"
  git -C "$prove_repo" mv suite.sh tests/suite.sh
  pcommit "the suite moves under tests/"
  # (a) a test that pins its fix
  # shellcheck disable=SC2016  # the $1 belongs to the fixture's own sh
  printf 'double() { echo $(( $1 * 2 )); }\n' >>"$prove_repo/impl.sh"
  # shellcheck disable=SC2016  # the $(...) belongs to the fixture's own sh
  printf '[ "$(double 2)" = "4" ] || { echo "double is wrong"; exit 1; }\n' >>"$prove_repo/tests/suite.sh"
  pcommit "double, with a test that pins it"
  pinned=$(git -C "$prove_repo" rev-parse HEAD)
  status=0
  prove_out=$(cd "$prove_repo" && tsh prove -l "$work/logs" -- sh tests/suite.sh 2>&1) || status=$?
  ((status == 0)) || fail "prove exited $status on a commit whose test pins its fix (want proven, 0):"$'\n'"$prove_out"
  grep -q '^proven:' <<<"$prove_out" || fail "prove did not say the commit was proven:"$'\n'"$prove_out"
  git -C "$prove_repo" diff --quiet || fail "prove left the fix taken away"
  # (b) a test that does not pin its fix
  # shellcheck disable=SC2016  # the $1 belongs to the fixture's own sh
  printf 'triple() { echo $(( $1 * 3 )); }\n' >>"$prove_repo/impl.sh"
  printf 'echo "also fine"\n' >>"$prove_repo/tests/suite.sh"
  pcommit "triple, with a test that asserts nothing about it"
  status=0
  prove_out=$(cd "$prove_repo" && tsh prove -l "$work/logs" -- sh tests/suite.sh 2>&1) || status=$?
  ((status == 83)) || fail "prove exited $status on a commit whose test does not pin its fix (want VACUOUS, 83):"$'\n'"$prove_out"
  grep -q '^VACUOUS:' <<<"$prove_out" || fail "prove did not call the vacuous commit vacuous:"$'\n'"$prove_out"
  git -C "$prove_repo" diff --quiet || fail "prove left the vacuous fix taken away"
  # (c) a fix without which nothing builds: the commit adds the file the build checks
  # shellcheck disable=SC2016  # the $1 belongs to the fixture's own sh
  printf '#!/bin/sh\nquad() { echo $(( $1 * 4 )); }\n' >"$prove_repo/impl2.sh"
  # shellcheck disable=SC2016  # the $(...) belongs to the fixture's own sh
  printf '. ./impl2.sh\n[ "$(quad 2)" = "8" ] || { echo "quad is wrong"; exit 1; }\n' >>"$prove_repo/tests/suite.sh"
  pcommit "quad, in a new file"
  status=0
  prove_out=$(cd "$prove_repo" && tsh prove -b 'sh -n impl2.sh' -l "$work/logs" -- sh tests/suite.sh 2>&1) || status=$?
  ((status == 88)) || fail "prove exited $status where taking the fix away breaks the build (want 88):"$'\n'"$prove_out"
  [[ -f "$prove_repo/impl2.sh" ]] || fail "prove did not put back the file the commit added"
  [[ -z "$(git -C "$prove_repo" status --porcelain)" ]] || fail "prove left the tree dirty after removing and restoring a new file"
  # (d) a commit with no fix in it
  printf 'helper=2\n' >"$prove_repo/tests/helper.sh"
  pcommit "only a test file"
  status=0
  (cd "$prove_repo" && tsh prove -l "$work/logs" -- sh tests/suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "prove accepted a commit with no fix to take away (got $status)"
  # (e) a commit that is not HEAD is proven in a worktree, and the tree in front of you is left alone
  status=0
  prove_out=$(cd "$prove_repo" && tsh prove "$pinned" -l "$work/logs" -- sh tests/suite.sh 2>&1) || status=$?
  ((status == 0)) || fail "prove exited $status on an older commit whose test pins its fix (want 0):"$'\n'"$prove_out"
  [[ "$(git -C "$prove_repo" worktree list | wc -l)" -eq 1 ]] || fail "prove left a worktree behind"
  [[ -z "$(git -C "$prove_repo" status --porcelain)" ]] || fail "prove of an older commit touched the tree in front of you"
  status=0
  (cd "$prove_repo" && tsh prove no-such-ref -l "$work/logs" -- sh tests/suite.sh) >/dev/null 2>&1 || status=$?
  ((status == 64)) || fail "prove accepted a ref that does not exist (got $status)"

  echo "== the help text lists every subcommand the dispatcher accepts"
  # The usage text is read out of this file's own header by line range, so it drifts the
  # moment a subcommand is added without moving the range. This is that drift check.
  help=$(tsh --help)
  subs=()
  while IFS= read -r sub; do subs+=("$sub"); done < <(sed -n 's/^  \([a-z-]*\)) cmd_[a-z_]*.*/\1/p' t.sh)
  # An extractor that matches nothing would leave the loop below empty and read as "no
  # drift" — the exact way a broken check goes on looking like a working one
  ((${#subs[@]} >= 2)) || fail "only ${#subs[@]} subcommand(s) could be read out of t.sh — the extractor is broken"
  for sub in "${subs[@]}"; do
    grep -qF "t.sh $sub" <<<"$help" ||
      fail "t.sh dispatches '$sub' but its help never mentions it — the usage line range has drifted"
  done
}

# The steps below prove the checks above can fail, by breaking one thing at a time in a
# throwaway copy. T_CHECK_NESTED stops the copy from recursing into this same section.
check_proofs() {
  # The gate must refuse a mode it does not have, or a typo would run nothing and pass
  ! "$BASH" ./check.sh wat >/dev/null 2>&1 || fail "the gate accepted a mode it does not have"

  copy() {
    local dest="$1"
    # Everything git tracks and nothing else, so the list cannot drift from the repository
    # the way a hand-written one did with every new file. Untracked files that are not
    # ignored come along too: a check being written must be provable before it is
    # committed, and `git archive` would only carry HEAD.
    # cp rather than tar: `tar --null -T -` is GNU and bsdtar, and the busybox tar a
    # bash-3.2 container brings along has neither
    local f
    git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
      mkdir -p "$dest/$(dirname "$f")"
      cp -p "$f" "$dest/$f"
    done
  }
  nested() { (cd "$1" && T_CHECK_NESTED=1 "$BASH" ./check.sh "$mode" >/dev/null 2>&1); }

  # A planted defect must make the copy fail FOR ITS OWN REASON. Asserting only that the
  # copy failed lets one broken check take credit for another's proof — which is how the
  # duplicate-marker rule sat here unproven, its copy failing on the dead-entry rule
  # instead.
  catches() { # catches DIR EXPECTED-FRAGMENT DESCRIPTION
    local dir="$1" want="$2" what="$3" out
    # stderr only: every refusal goes there, and the family's gates print their own
    # "all clear" lines to stdout under the same check-skill:/check-pins: prefix
    out=$( (cd "$dir" && T_CHECK_NESTED=1 "$BASH" ./check.sh "$mode" 2>&1 >/dev/null) || :)
    local line
    line=$(grep -m 1 -E '^check(-skill|-pins)?:' <<<"$out" || :)
    [[ -n "$line" ]] || fail "$what: the copy did not fail at all"
    [[ "$line" == *"$want"* ]] ||
      fail "$what: the copy failed for another reason — $line"
  }

  echo "== an untouched copy passes, so a copy that fails below fails for its defect"
  # The question every falsification rests on and the one easiest to forget: if a pristine
  # copy already fails, then "the broken copy failed" says nothing, and every proof below is
  # vacuous while the gate stays green. This repository shipped exactly that bug for four
  # commits, after a step was added that a copy could not satisfy.
  copy "$work/pristine"
  # The copy has to be complete, or a copy that fails below could be failing on the gap
  while IFS= read -r tracked; do
    [[ -e "$work/pristine/$tracked" ]] || fail "the copy step lost $tracked"
  done < <(git ls-files --cached --others --exclude-standard)
  nested "$work/pristine" ||
    fail "an untouched copy does not pass the gate — every 'able to fail' proof below would be meaningless"

  # One planted defect per line. HALF is the half of the gate the defect belongs to, lint
  # or behaviour, and the row is skipped when that half is not being run. FRAGMENT is the
  # text the copy's own failure must carry, and the mutator says how the defect is planted:
  #   append FILE TEXT          add TEXT to the end of FILE
  #   write  FILE TEXT          replace FILE with TEXT
  #   sed    FILE SCRIPT MARK   run SCRIPT over FILE; MARK must be in the result
  #   awk    FILE PROGRAM MARK  the same, with awk
  #   drop   FILE TEXT          delete every line holding TEXT; none may remain
  #   rm     FILE               delete FILE
  # A mutation that did not land is a failure of its own, never a silent pass: a sed whose
  # pattern drifted from t.sh would otherwise leave a pristine copy, and the pristine copy
  # passes, which reads exactly like a defect that was caught.
  planted=0
  plant() { # plant HALF NAME FRAGMENT DESCRIPTION MUTATOR FILE ARGS...
    local half="$1" name="$2" want="$3" what="$4" how="$5" file="$6"
    shift 6
    [[ "$mode" == all || "$mode" == "$half" ]] || return 0
    local dir="$work/plant-$name"
    echo "== able to fail: $what"
    # Two rows with one name would share a copy, and the second would inherit the first's
    # defect on top of its own — which is how a proof once failed for another's reason
    [[ ! -e "$dir" ]] || fail "plant: the name '$name' is used by two rows"
    copy "$dir"
    case "$how" in
      append) printf '%s' "$1" >>"$dir/$file" ;;
      write) printf '%s' "$1" >"$dir/$file" ;;
      sed)
        sed "$1" "$dir/$file" >"$dir/$file.new" && mv "$dir/$file.new" "$dir/$file"
        grep -qF -- "$2" "$dir/$file" || fail "$what: the defect was not planted — '$2' is not in $file"
        ;;
      awk)
        awk "$1" "$dir/$file" >"$dir/$file.new" && mv "$dir/$file.new" "$dir/$file"
        grep -qF -- "$2" "$dir/$file" || fail "$what: the defect was not planted — '$2' is not in $file"
        ;;
      drop)
        grep -vF -- "$1" "$dir/$file" >"$dir/$file.new" && mv "$dir/$file.new" "$dir/$file"
        ! grep -qF -- "$1" "$dir/$file" || fail "$what: the defect was not planted — '$1' is still in $file"
        ;;
      rm) rm -f "$dir/$file" ;;
      *) fail "plant: no such mutator '$how'" ;;
    esac
    [[ ! -x "$file" || ! -e "$dir/$file" ]] || chmod +x "$dir/$file"
    catches "$dir" "$want" "$what"
    planted=$((planted + 1))
  }

  # shellcheck disable=SC2016  # every $ below is t.sh's own source text being matched, not an expansion
  {
    plant lint nofront "does not open with a frontmatter block" "a SKILL.md with no frontmatter" \
      write SKILL.md $'no frontmatter here\n'
    plant lint wrapped "hard-wraps a paragraph" "a hard-wrapped paragraph" \
      append README.md $'\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n'
    plant lint wrapped-reference "hard-wraps a paragraph" "a hard-wrapped paragraph in a reference" \
      append references/verdict.md $'\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n'
    plant lint orphan "reaches it" "a reference nothing links to" \
      write references/nothing-points-here.md ''
    plant lint deadlink "which does not exist" "a link to a missing file" \
      append SKILL.md $'\nSee [the missing one](references/not-a-file.md).\n'
    plant lint deadanchor "where no heading has that anchor" "a link to a nonexistent heading" \
      append SKILL.md $'\nSee [nowhere](references/verdict.md#no-such-heading).\n'
    plant behaviour crlf "reddened a healthy CRLF run" "a run that keeps the carriage return in its markers" \
      drop t.sh "line=\"\${line%\$'\\r'}\""
    plant lint badflag "which that subcommand does not accept" "a documented flag the parser does not have" \
      append references/verdict.md $'\n```sh\nt.sh run -b \'cargo build\' -- cargo test\n```\n'
    plant lint dead "a dead entry guards nothing" "a marker matching nothing" \
      append markers/default.txt $'a marker matching nothing\n'
    plant lint noisy "it would redden healthy runs" "a marker that fires on a healthy run" \
      append markers/default.txt $'test session starts\n'
    plant lint unproven "has no fixture at" "a marker set with no fixture" \
      write markers/invented.txt $'no tests ran\n'
    plant lint unwatched "watched by nobody" "action pins with no dependabot" \
      rm .github/dependabot.yml
    plant lint unwatched-actions "does not watch the github-actions" "a dependabot that watches something else" \
      write .github/dependabot.yml $'version: 2\nupdates:\n  - package-ecosystem: npm\n    directory: /\n    schedule:\n      interval: weekly\n'
    # An ignored key is a policy silently not in effect, which is worse than no config at
    # all: the repository believes markers are loaded that never were
    plant behaviour lenient "unknown key" "a config that ignores an unknown key" \
      sed t.sh 's|^      \*) die "config: \$conf:\$n — unknown key.*|      *) : ;;|' '*) : ;;'
    # `die` in a $(...) exits the subshell, so the caller carries on with an empty string.
    # Written that way, the empty-marker-set refusal would not refuse — and an empty marker
    # list makes every run a pass while the check still looks like it is working.
    plant behaviour subshell "accepted an empty marker set" "a run that never validated its markers" \
      sed t.sh 's/^  load_markers$/  MARKER_PATTERNS=()/' 'MARKER_PATTERNS=()'
    # A harness with no pipefail that reads $? after the pipe. Both halves are one defect:
    # under pipefail alone, $? still happens to be right whenever the FIRST command is the
    # one that failed, so planting only the $? would prove nothing.
    plant behaviour blind "for a command that exited 7" "a run reading tee's status" \
      sed t.sh 's/^set -uo pipefail$/set -u/; s/local -a ps=("${PIPESTATUS\[@\]}")/local -a ps=($?)/' 'local -a ps=($?)'
    plant behaviour undocumented "its help never mentions it" "a subcommand missing from the help" \
      awk t.sh '/^  flaky\) cmd_flaky/ && !done { print "  wat) cmd_run \"$@\" ;;"; done=1 } { print }' 'wat) cmd_run'
    plant behaviour raw "should be 1 to git bisect" "a probe returning a raw signal status" \
      sed t.sh 's/^        \*) return 1 ;;$/        *) return "$status" ;; # planted/' '# planted'
    # Dropping the `printf x` lets command substitution eat the file's last newline, so
    # every restore leaves the tree dirty by one byte — invisible to a string comparison,
    # obvious to git
    plant behaviour trailing "byte for byte" "a falsify that loses the trailing newline" \
      sed t.sh 's/__content=\$(cat "\$2" \&\& printf x)/__content=$(cat "$2")/' '__content=$(cat "$2")'
    # Replaced by a no-op that still reads the variable, or the copy fails on shellcheck's
    # unused-variable warning instead of on the check
    plant behaviour badallow "grep cannot compile" "a run that applies an allow regex it never checked" \
      sed t.sh 's/^    \[\[ -z "\$complaint" \]\] || die "allow:.*$/    : "$complaint" # planted/' '# planted'
    plant behaviour carryon "carried on after an interrupt" "a falsify whose interrupt handler returns" \
      sed t.sh "s/^  trap 'end_mutant; restore_all; cleanup_worktree; trap - INT; kill -INT \$\$' INT$/  trap 'end_mutant; restore_all' INT/" "trap 'end_mutant; restore_all' INT"
    plant behaviour unrecorded ".txt does not name" "a falsify that keeps its findings to the terminal" \
      sed t.sh 's|^    printf '"'"'%s\\n'"'"' "\$2" >>"\$out/\$list.txt"$|    : "$out/$list.txt" # planted|' '# planted'
    plant behaviour vacuous "want proven" "a prove that never takes the fix away" \
      sed t.sh 's/^      printf '"'"'%s'"'"' "\${befores\[\$i\]}" >"\${src\[\$i\]}" || fatal "prove: cannot write.*$/      : # planted/' '# planted'
    plant behaviour leftover "left a worktree behind" "a falsify --worktree that does not clean up" \
      sed t.sh 's/^    git -C "\$root" worktree remove --force "\$wt" >\/dev\/null 2>&1 || :$/    : # planted/' '# planted'
    plant behaviour unsince "ran nothing and did not say so" "a falsify --since that passes an empty selection in silence" \
      sed t.sh 's/^    printf '"'"'nothing to falsify: .*$/    : # planted/' '# planted'
    plant behaviour unannotated "did not annotate the survivor" "a falsify that keeps its findings out of the diff" \
      sed t.sh 's/^        annotate error "\$file" "\$line" "SURVIVED \$name: \$why"$/        : # planted/' '# planted'
    plant behaviour unexpected "was reported as a survivor" "a falsify that ignores a declared exception" \
      sed t.sh 's/^    if \[\[ -n "\$expect" \]\]; then$/    if false; then # planted/' '# planted'
    plant behaviour nowhere "where the edit is" "a falsify that names a survivor without its line" \
      drop t.sh '  - %s\n'
    plant behaviour anyfile "aimed at a test file" "a falsify that edits test files" \
      sed t.sh 's/^      looks_like_test_file "\${DEF_FILE\[\$i\]}" || continue$/      continue # planted/' '# planted'
    plant behaviour nodeadline "nothing timed it out" "a falsify with no deadline" \
      sed t.sh 's/^    if \[\[ -n "\$deadline" \]\] \&\& ((waited >= deadline \* 10)); then$/    if false; then # planted/' '# planted'
    plant behaviour surrender "want 89" "a bisect that reports an all-skipped history as resolved" \
      sed t.sh 's/^    return 89$/    return 0 # planted/' '# planted'
    plant behaviour muted "hid run's refusal" "a flaky that mutes the harness's own refusals" \
      sed t.sh 's|>/dev/null 2>"\$stamp/run-\$i.err"|>/dev/null 2>/dev/null|' '>/dev/null 2>/dev/null'
    plant behaviour anytail "accepted -t abc" "a run that takes -t on trust" \
      drop t.sh 'die "run: -t needs a number'
    plant behaviour twice "named twice printed" "a run that loads a marker set as often as it is named" \
      sed t.sh 's/^        add_marker_file "\$RESOLVED"$/        MARKER_FILES+=("$RESOLVED")/' 'MARKER_FILES+=("$RESOLVED")'
    plant behaviour unresolved "through the symlink" "a harness that does not resolve its own symlink" \
      sed t.sh 's/^while \[\[ -L "\$self" \]\]; do$/while false; do/' 'while false; do'
    # The write goes to /dev/null rather than being deleted: deleting it leaves RUN_VERDICT
    # unreferenced, and the copy would then fail on shellcheck instead of on the check
    plant behaviour nosidecar "did not record" "a run that keeps its verdict to itself" \
      sed t.sh 's|>"\$log\.verdict"|>/dev/null|' 'printf '"'"'%s\n'"'"' "$RUN_VERDICT" >/dev/null'
    if [[ $EUID -eq 0 ]]; then
      echo "   skipped: the unwritable-log and unwritten-mutant checks themselves are skipped as root"
    else
      plant behaviour nolog "nowhere to put its log" "a run that cannot write its log" \
        drop t.sh ': >"$log" || fatal'
      plant behaviour unwritten "could not write" "a falsify that does not check its write" \
        sed t.sh 's/ || fatal "falsify: cannot write \$file.*$/ # planted/' '# planted'
    fi
  }

  # t.sh travels to repositories that run CI on macOS, which ships bash 3.2, and that is
  # the one place it has broken before. A grep for bash-4 syntax was the guard once; a grep
  # is a proxy, matching the constructs somebody thought to list, and it let nine through
  # on its first audit. The mechanism is this: the behaviour half under the real 3.2, on a
  # macOS runner, with two constructs planted that only a 3.2 rejects. Under a newer bash
  # they are no defect at all, so this block runs only where T_CHECK_BASH32 says which
  # bash this is, and first checks that claim.
  if [[ -n "${T_CHECK_BASH32:-}" ]]; then
    echo "== this bash is the 3.2 the proof is about"
    ((BASH_VERSINFO[0] == 3)) ||
      fail "T_CHECK_BASH32 is set, but this is bash $BASH_VERSION — on macOS, run: /bin/bash ./check.sh behaviour"
    ! "$BASH" -c 'declare -A m' >/dev/null 2>&1 || fail "T_CHECK_BASH32 is set, but this bash accepts declare -A"
    plant behaviour bash4-declare "(got 70)" "a harness that declares an associative array" \
      awk t.sh '{ print } /^set -uo pipefail$/ { print "declare -A t_sh_probe || exit 70" }' 'declare -A t_sh_probe'
    # mapfile is not found, the marker list stays empty, and run refuses every command —
    # the class of regression this bash was found unable to run
    # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
    plant behaviour bash4-mapfile "expected 79, got 64" "a harness reading its markers with mapfile" \
      sed t.sh 's/^    while IFS= read -r line; do MARKER_PATTERNS+=("\$line"); done < <(read_markers "\$file")$/    mapfile -t MARKER_PATTERNS < <(read_markers "$file")/' 'mapfile -t MARKER_PATTERNS'
  fi

  # Two mutations, so a hand-written block: the duplicate has to be present in the set's
  # own fixture too, or the copy fails on the dead-entry rule first and the duplicate rule
  # is never reached — which is exactly how this proof was passing without proving anything
  if [[ "$mode" != behaviour ]]; then
    echo "== able to fail: a set repeating a default marker"
    copy "$work/plant-dupe"
    # In other letters and with a suffix, which an exact comparison would have let through
    printf 'No Tests Ran in 0.01s\n' >>"$work/plant-dupe/markers/go.txt"
    printf 'No Tests Ran in 0.01s\n' >>"$work/plant-dupe/tests/fixtures/lying/go.log"
    catches "$work/plant-dupe" "repeats a marker that markers/default.txt" "a set repeating a default marker"
    planted=$((planted + 1))
  fi

  # The table above is the proof; a table that lost its rows would prove nothing while
  # the gate stayed green. The count is per half, so a half cannot borrow the other's rows.
  case "$mode" in
    lint) want_planted=13 ;;
    behaviour) want_planted=26 ;;
    all) want_planted=39 ;;
  esac
  ((planted >= want_planted)) ||
    fail "only $planted defects were planted for mode '$mode', not $want_planted — the falsification table has lost rows"
}

case "$mode" in
  lint) check_lint ;;
  behaviour) check_behaviour ;;
  all)
    check_lint
    check_behaviour
    ;;
esac
[[ -n "${T_CHECK_NESTED:-}" ]] || check_proofs

echo
echo "check: everything holds"
