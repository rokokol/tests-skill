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

# The skill's own name, as the frontmatter, the readme and the symlink all spell it
skill_name=tests

fail() {
  echo "check: $1" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Say which tool is missing, rather than dying halfway through with a bare "command not
# found" that the reader then has to trace back to a step
missing=()
for tool in actionlint shellcheck shfmt git; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
((${#missing[@]} == 0)) ||
  fail "missing: ${missing[*]} — they are pinned in the flake, so run this as: nix develop -c ./check.sh"

echo "== the scripts parse and lint"
for s in "${scripts[@]}"; do bash -n "$s"; done
shellcheck "${scripts[@]}"
shfmt -d -i 2 -ci "${scripts[@]}"

echo "== nothing here needs a bash newer than the one macOS ships"
# t.sh is meant to be vendored into other repositories, and some of them run CI on macOS,
# which ships bash 3.2. Two of these were found the expensive way, on a runner none of this
# was written on: `[[ -v VAR ]]` is 4.2+, `mapfile` is 4.0+, `declare -A` is 4.0+.
# `sort -V` is a neighbouring trap — not a bash version but a GNU one, absent from BSD sort.
#
# Every literal is split by a bracket expression so the pattern cannot match its own source
# line, and the planted constructs live in a fixture for the same reason: a guard that
# reddens the commit introducing it gets deleted rather than fixed.
bash4_pattern='\[\[[^]]*[-]v [A-Za-z_]|mapfil[e] |readarra[y] |declar[e] -A|loca[l] -A|\$\{[A-Za-z_]+,[,]\}|\$\{[A-Za-z_]+\^[\^]\}|sor[t] -[A-Za-z]*V'
bash4=$(grep -nE "$bash4_pattern" "${scripts[@]}" | grep -vE ':[[:space:]]*#' || :)
[[ -z "$bash4" ]] || fail "a construct newer than bash 3.2 (or GNU-only) in a script meant to travel:"$'\n'"$bash4"
planted_count=0
while IFS= read -r planted; do
  [[ -z "$planted" || "$planted" == \#* ]] && continue
  planted_count=$((planted_count + 1))
  printf '%s\n' "$planted" >"$work/planted.sh"
  grep -qE "$bash4_pattern" "$work/planted.sh" ||
    fail "the bash-3.2 guard does not catch: $planted"
done <tests/fixtures/bash4-constructs.sh
((planted_count >= 8)) || fail "only $planted_count constructs were read from the fixture — the extractor is broken"

echo "== the workflows are valid, and their tools come from the lock rather than a registry"
# actionlint needs a git project to find workflows in, which the throwaway copies below are
# not. Skipping it there is what lets a planted defect be the reason a copy fails; without
# this the copies would all die here, and every "able to fail" proof would be vacuous while
# the gate stayed green. Outside a nested run the workflows must exist.
if [[ -n "${T_CHECK_NESTED:-}" ]]; then
  echo "   skipped in the nested copy, which carries no workflows"
else
  [[ -d .github/workflows ]] || fail ".github/workflows is missing — nothing gates this repository"
  actionlint
  # This repo follows its own advice about pinning: a job that resolves a tool at run time
  # changes behaviour with zero change in the repository. The guard is here as well as in
  # the workflow, so it also fails locally rather than only after a push.
  if grep -rEn 'nix (run|shell) nixpkgs#|npx +[a-z@.-]|pip +install |go +install .*@latest' .github/workflows; then
    fail "an unpinned registry lookup in a workflow — pin the tool in the flake's dev shell and use nix develop"
  fi
fi

echo "== SKILL.md carries the frontmatter an agent loads it by"
# A skill whose frontmatter is malformed or renamed is simply never loaded, and nothing
# says so: the agent just never reaches for it.
head -1 SKILL.md | grep -qx -- '---' || fail "SKILL.md does not open with a frontmatter block"
front=$(sed -n '2,/^---$/p' SKILL.md)
for key in name description license; do
  grep -q "^$key:" <<<"$front" || fail "SKILL.md frontmatter has no $key"
done
grep -qx "name: $skill_name" <<<"$front" ||
  fail "SKILL.md does not call this skill '$skill_name', which is what the readme and the symlink call it"

echo "== no paragraph in the readme is hard-wrapped"
# GitHub soft-wraps, so a manual break inside a paragraph only means a one-word edit
# reflows every line after it. This is the one rule of the create-readme skill that a
# reader cannot see and a script can decide; the rest of that skill's rules live with it.
hard_wrapped() { # hard_wrapped FILE -> prints the offending line numbers
  awk '
    /^```/ { fence = !fence; prev = 0; next }
    fence { next }
    # blank, heading, table, list, quote, html, badge, link or indented line: not prose
    /^[[:space:]]*$/ || /^[#|>< ]/ || /^[-*+]/ || /^!\[/ || /^\[/ { prev = 0; next }
    { if (prev) print NR; prev = 1 }
  ' "$1"
}
wrapped=$(hard_wrapped README.md)
[[ -z "$wrapped" ]] ||
  fail "README.md hard-wraps a paragraph at line(s): $(tr '\n' ' ' <<<"$wrapped")— one paragraph is one line"

echo "== every reference is reachable, and every link and anchor resolves"
# A reference nothing links to is never loaded, so it rots unread while reading as
# maintained. Reachability is transitive: SKILL.md may delegate to a reference that links on.
docs=(SKILL.md README.md)
while IFS= read -r ref; do docs+=("$ref"); done < <(find references -type f -name '*.md' | sort)
((${#docs[@]} > 2)) || fail "no references were found — the extractor is broken"
for ref in "${docs[@]:2}"; do
  base=$(basename "$ref")
  grep -qrF "$base" SKILL.md references/ ||
    fail "$ref exists but nothing links to it — it will rot unread"
done

# Every relative link resolves to a file that exists, and every #anchor to a heading in it
for doc in "${docs[@]}"; do
  dir=$(dirname "$doc")
  while IFS= read -r link; do
    target="${link%%#*}"
    anchor="${link#*#}"
    [[ "$anchor" == "$link" ]] && anchor=""
    if [[ -n "$target" ]]; then
      path="$dir/$target"
      [[ -e "$path" ]] || fail "$doc links to $target, which does not exist"
    else
      path="$doc"
    fi
    [[ -n "$anchor" && -f "$path" ]] || continue
    # GitHub's anchor form: lowercase, spaces to dashes, punctuation dropped
    if ! sed -n 's/^#\{1,6\} *//p' "$path" |
      tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-\n' |
      grep -qx -- "$anchor"; then
      fail "$doc links to #$anchor in $path, where no heading has that anchor"
    fi
  done < <(grep -o '](\([^)]*\))' "$doc" | sed 's/^](//; s/)$//' | grep -v '^[a-z]*://')
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
# every run, so the copy is dead weight that reads as extra coverage
for set_file in markers/*.txt; do
  [[ "$set_file" == markers/default.txt ]] && continue
  dupe=$(comm -12 \
    <(grep -v '^#' markers/default.txt | grep -v '^$' | sort) \
    <(grep -v '^#' "$set_file" | grep -v '^$' | sort))
  [[ -z "$dupe" ]] ||
    fail "$set_file repeats markers that markers/default.txt already applies to every run: $dupe"
done

echo "== run refuses a marker set that would leave it checking nothing"
status=0
./t.sh run -t 0 -l "$work/logs" -m no-such-set -- true >/dev/null 2>&1 || status=$?
((status == 64)) || fail "run accepted a marker set that does not exist (got $status)"
: >"$work/empty-markers.txt"
status=0
./t.sh run -t 0 -l "$work/logs" -m "$work/empty-markers.txt" -- true >/dev/null 2>&1 || status=$?
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
  (cd "$conf" && "$HERE/t.sh" run -t 0 -l "$work/logs" "$@") >/dev/null 2>&1 || got=$?
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
(cd "$conf" && "$HERE/t.sh" flaky 2 -- sh -c 'echo "1 passed"; exit 0') >/dev/null 2>&1 || :
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
T_CONFIG=templates/t.conf ./t.sh run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed"; exit 0' \
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
./t.sh run -t 0 -l "$work/logs" -m "$crlf_markers" \
  -- sh -c 'printf "Compiling windows-link v0.2.1\r\ntest result: ok. 12 passed\r\n"; exit 0' \
  >/dev/null 2>&1 || status=$?
((status == 0)) || fail "a CRLF marker file reddened a healthy CRLF run (got $status)"
status=0
./t.sh run -t 0 -l "$work/logs" -m "$crlf_markers" \
  -- sh -c 'printf "collected 0 items\r\n"; exit 0' >/dev/null 2>&1 || status=$?
((status == 79)) || fail "a CRLF marker file stopped catching what it names (got $status)"

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
((status == 79)) || fail "run reported $status for a green run whose log said no tests were collected"

echo "== an honest green run is still a pass"
status=0
./t.sh run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed in 1.83s"; exit 0' >/dev/null 2>&1 || status=$?
((status == 0)) || fail "run reported $status for a healthy run — it would cry wolf"

echo "== run writes the kind of verdict it reached beside the log"
# A number cannot say whether 79 was the harness's verdict or the command's own status,
# so the kind goes in a sidecar, and the subcommands that run cmd_run in a subshell
# read that instead of guessing from the number
for pair in 'fail:exit 7' 'lied:echo "collected 0 items"; exit 0' 'pass:echo "47 passed"; exit 0'; do
  want=${pair%%:*}
  cmd=${pair#*:}
  rm -f "$work/verdict.log" "$work/verdict.log.verdict"
  T_LOGFILE="$work/verdict.log" ./t.sh run -t 0 -l "$work/logs" -- sh -c "$cmd" >/dev/null 2>&1 || :
  grep -qx "$want" "$work/verdict.log.verdict" 2>/dev/null ||
    fail "run did not record '$want' beside its log for: $cmd"
done

echo "== T_ALLOW excuses a marker the repository expects, and nothing else"
status=0
T_ALLOW='expected: no tests ran' ./t.sh run -t 0 -l "$work/logs" \
  -- sh -c 'echo "expected: no tests ran"; exit 0' >/dev/null 2>&1 || status=$?
((status == 0)) || fail "T_ALLOW did not excuse the line it names (got $status)"
status=0
T_ALLOW='something else entirely' ./t.sh run -t 0 -l "$work/logs" \
  -- sh -c 'echo "expected: no tests ran"; exit 0' >/dev/null 2>&1 || status=$?
((status == 79)) || fail "T_ALLOW excused a line it does not name (got $status) — it excuses everything"
# A regex grep cannot compile used to leave the filtered log empty, and an empty log has
# no markers: the worst shape, because a typo in the excuse list made every run a pass
status=0
T_ALLOW='expected(' ./t.sh run -t 0 -l "$work/logs" \
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
  ./t.sh run -t 0 -l "$readonly_dir" -- sh -c 'exit 0' >/dev/null 2>&1 || status=$?
  ((status == 70)) || fail "run started with nowhere to put its log (got $status)"
fi

echo "== run refuses a command that was not put after --"
status=0
./t.sh run sh -c 'exit 0' >/dev/null 2>&1 || status=$?
((status == 64)) || fail "run accepted a command without -- (got $status); guessing is how the wrong thing gets run"

echo "== run refuses a tail length that is not a number, and counts a marker set once"
status=0
./t.sh run -t abc -l "$work/logs" -- sh -c 'exit 1' >/dev/null 2>&1 || status=$?
((status == 64)) || fail "run accepted -t abc (got $status); (( )) reads a word as zero, so the tail silently vanished"
findings=$(./t.sh run -t 0 -m rust -m rust -l "$work/logs" -- sh -c 'echo "running 0 tests"; exit 0' 2>&1 |
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
((status == 86)) || fail "flaky missed a command whose runs disagreed (got $status)"

echo "== flaky refuses the arguments that would make it meaningless"
status=0
./t.sh flaky 1 -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>&1 || status=$?
((status == 64)) || fail "flaky accepted a single run, which cannot show disagreement (got $status)"
status=0
./t.sh flaky 3 -l "$work/logs" sh -c 'exit 0' >/dev/null 2>&1 || status=$?
((status == 64)) || fail "flaky accepted a command that was not put after -- (got $status)"
# A refusal has to be heard. flaky mutes the command's output for each run, and for a
# while muted run's own refusals with it: `flaky 3 -x` exited 2 without a word.
status=0
./t.sh flaky 3 -x -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>"$work/flaky.err" || status=$?
((status == 64)) || fail "flaky accepted an unknown flag (got $status)"
grep -q 'flaky:' "$work/flaky.err" || fail "flaky refused an unknown flag without saying so"
status=0
./t.sh flaky 3 -m no-such-set -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>"$work/flaky.err" || status=$?
((status == 64)) || fail "flaky accepted a marker set that does not exist (got $status)"
[[ -s "$work/flaky.err" ]] || fail "flaky refused a marker set silently"
# And a refusal only run can make, once the loop has started, is shown too
status=0
T_ALLOW='expected(' ./t.sh flaky 3 -l "$work/logs" -- sh -c 'exit 0' >/dev/null 2>"$work/flaky.err" || status=$?
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
bisect_out=$(cd "$repo" && "$HERE/t.sh" bisect "$first_good" -b 'test -f builds' -- test -f passes 2>&1) ||
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
bisect_out=$(cd "$repo" && "$HERE/t.sh" bisect "$first_good" --first-parent -b 'test -f builds' -- test -f passes 2>&1) ||
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
stuck_out=$(cd "$stuck" && "$HERE/t.sh" bisect "$stuck_good" -b 'test -f builds' -- false 2>&1) || status=$?
((status == 89)) || fail "bisect exited $status where nothing between good and bad could answer (want 89):"$'\n'"$stuck_out"
grep -q 'INCONCLUSIVE' <<<"$stuck_out" || fail "bisect did not say its answer was inconclusive"
[[ "$(git -C "$stuck" rev-parse --abbrev-ref HEAD)" == master ]] ||
  fail "an inconclusive bisect left the repository detached"

echo "== bisect refuses to start over a bisect already in progress"
# git bisect start resets an in-progress bisect without a word
git -C "$repo" bisect start >/dev/null
status=0
(cd "$repo" && "$HERE/t.sh" bisect "$first_good" -- true) >/dev/null 2>&1 || status=$?
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
  (cd "$repo" && "$HERE/t.sh" bisect-probe -l "$work/logs" "$@") >/dev/null 2>&1 || got=$?
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
(cd "$repo" && "$HERE/t.sh" bisect "$first_good" -- true) >/dev/null 2>&1 || status=$?
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

echo "== a mutant that could not be written is not a survivor"
# A write that fails leaves the pristine code in place; the suite passes against it, and
# that used to be reported as SURVIVED for a guard the suite does cover. git tracks only
# the executable bit, so the read-only file still counts as a clean tree.
if [[ $EUID -eq 0 ]]; then
  echo "   skipped: running as root, which can write a read-only file"
else
  chmod a-w "$fal/impl.sh"
  status=0
  fal_out=$(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh suite.sh 2>&1) || status=$?
  chmod u+w "$fal/impl.sh"
  ((status == 70)) || fail "falsify measured a mutant it could not write (got $status):"$'\n'"$fal_out"
  ! grep -q 'SURVIVED' <<<"$fal_out" || fail "falsify credited a read-only source file with a survivor"
fi

echo "== falsify refuses the situations where its answer would be meaningless"
status=0
(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh -c 'exit 1') >/dev/null 2>&1 || status=$?
((status == 64)) || fail "falsify measured against an already-failing suite (got $status)"
status=0
(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh -c 'echo "collected 0 items"; exit 0') \
  >/dev/null 2>&1 || status=$?
((status == 64)) || fail "falsify measured against a suite that never really ran (got $status)"
echo dirt >"$fal/impl.sh.tmp" && mv "$fal/impl.sh.tmp" "$fal/impl.sh"
status=0
(cd "$fal" && "$HERE/t.sh" falsify -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
((status == 64)) || fail "falsify started on a dirty tree, where an interrupted restore looks like your own edits (got $status)"
git -C "$fal" checkout -q -- .
status=0
: >"$fal/tests/empty.sh"
(cd "$fal" && "$HERE/t.sh" falsify -d tests/empty.sh -l "$work/logs" -- sh suite.sh) >/dev/null 2>&1 || status=$?
((status == 64)) || fail "falsify accepted an empty defect list, which proves nothing (got $status)"

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
    # Everything the docs link to has to come along, or a copy fails on a dead link rather
    # than on the defect it was built to carry
    mkdir -p "$dest/tests/fixtures/lying" "$dest/templates"
    cp t.sh check.sh SKILL.md README.md CHANGELOG.md LICENSE "$dest/"
    cp -r references markers "$dest/"
    cp templates/defects.sh templates/t.conf "$dest/templates/"
    cp tests/fixtures/*.log "$dest/tests/fixtures/"
    cp tests/fixtures/lying/*.log "$dest/tests/fixtures/lying/"
    cp tests/fixtures/bash4-constructs.sh "$dest/tests/fixtures/"
  }
  nested() { (cd "$1" && T_CHECK_NESTED=1 ./check.sh >/dev/null 2>&1); }

  # A planted defect must make the copy fail FOR ITS OWN REASON. Asserting only that the
  # copy failed lets one broken check take credit for another's proof — which is how the
  # duplicate-marker rule sat here unproven, its copy failing on the dead-entry rule
  # instead.
  catches() { # catches DIR EXPECTED-FRAGMENT DESCRIPTION
    local dir="$1" want="$2" what="$3" out
    out=$( (cd "$dir" && T_CHECK_NESTED=1 ./check.sh 2>&1) || :)
    local line
    line=$(grep -m 1 '^check:' <<<"$out" || :)
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
  nested "$work/pristine" ||
    fail "an untouched copy does not pass the gate — every 'able to fail' proof below would be meaningless"

  echo "== the frontmatter check is able to fail"
  copy "$work/nofront"
  printf 'no frontmatter here\n' >"$work/nofront/SKILL.md"
  catches "$work/nofront" "does not open with a frontmatter block" "a SKILL.md with no frontmatter"

  echo "== the hard-wrap check is able to fail"
  copy "$work/wrapped"
  printf '\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n' \
    >>"$work/wrapped/README.md"
  catches "$work/wrapped" "hard-wraps a paragraph" "a hard-wrapped paragraph"

  echo "== the reachability check is able to fail: a reference nothing links to"
  copy "$work/orphan"
  : >"$work/orphan/references/nothing-points-here.md"
  catches "$work/orphan" "nothing links to it" "a reference nothing links to"

  echo "== the link check is able to fail: a link to a file that is not there"
  copy "$work/deadlink"
  printf '\nSee [the missing one](references/not-a-file.md).\n' >>"$work/deadlink/SKILL.md"
  catches "$work/deadlink" "which does not exist" "a link to a missing file"

  echo "== the anchor check is able to fail: a link to a heading that does not exist"
  copy "$work/deadanchor"
  printf '\nSee [nowhere](references/verdict.md#no-such-heading).\n' >>"$work/deadanchor/SKILL.md"
  catches "$work/deadanchor" "where no heading has that anchor" "a link to a nonexistent heading"

  echo "== the CRLF guard is able to fail"
  copy "$work/crlf"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed "s|^    line=\"\${line%\$'\\\\r'}\"$||" t.sh >"$work/crlf/t.sh.new" &&
    mv "$work/crlf/t.sh.new" "$work/crlf/t.sh"
  chmod +x "$work/crlf/t.sh"
  catches "$work/crlf" "reddened a healthy CRLF run" "a run that keeps the carriage return in its markers"

  echo "== the documented-flag check is able to fail: the mistake a reader actually hit"
  copy "$work/badflag"
  printf '\n```sh\nt.sh run -b '"'"'cargo build'"'"' -- cargo test\n```\n' \
    >>"$work/badflag/references/verdict.md"
  catches "$work/badflag" "which that subcommand does not accept" "a documented flag the parser does not have"

  echo "== the marker check is able to fail: a dead entry"
  copy "$work/dead"
  printf 'a marker matching nothing\n' >>"$work/dead/markers/default.txt"
  catches "$work/dead" "a dead entry guards nothing" "a marker matching nothing"

  echo "== the marker check is able to fail: an entry that fires on a healthy run"
  copy "$work/noisy"
  printf 'test session starts\n' >>"$work/noisy/markers/default.txt"
  catches "$work/noisy" "it would redden healthy runs" "a marker that fires on a healthy run"

  echo "== the duplicate check is able to fail: a set repeating a default marker"
  # The duplicate has to be present in the set's own fixture too, or the copy fails on the
  # dead-entry rule first and the duplicate rule is never reached — which is exactly how
  # this proof was passing without proving anything
  copy "$work/dupe"
  printf 'no tests ran\n' >>"$work/dupe/markers/go.txt"
  printf 'no tests ran in 0.01s\n' >>"$work/dupe/tests/fixtures/lying/go.log"
  catches "$work/dupe" "repeats markers that markers/default.txt" "a set repeating a default marker"

  echo "== the marker check is able to fail: a set with no fixture behind it"
  copy "$work/unproven"
  printf 'no tests ran\n' >"$work/unproven/markers/invented.txt"
  catches "$work/unproven" "has no fixture at" "a marker set with no fixture"

  echo "== the unknown-key refusal is able to fail: a config that ignores what it cannot parse"
  # The tempting form. An ignored key is a policy silently not in effect, which is worse
  # than no config at all: the repository believes markers are loaded that never were.
  copy "$work/lenient"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed 's|^      \*) die "config: \$conf:\$n — unknown key.*|      *) : ;;|' t.sh >"$work/lenient/t.sh.new" &&
    mv "$work/lenient/t.sh.new" "$work/lenient/t.sh"
  chmod +x "$work/lenient/t.sh"
  grep -qF '*) : ;;' "$work/lenient/t.sh" || fail "the lenient-config fixture was not planted"
  catches "$work/lenient" "unknown key" "a config that ignores an unknown key"

  echo "== a refusal written inside a subshell is able to fail"
  # `die` in a $(...) exits the subshell, so the caller carries on with an empty string.
  # Written that way, the empty-marker-set refusal would not refuse — and an empty marker
  # list makes every run a pass while the check still looks like it is working.
  copy "$work/subshell"
  sed 's/^  load_markers$/  MARKER_PATTERNS=()/' t.sh >"$work/subshell/t.sh.new" &&
    mv "$work/subshell/t.sh.new" "$work/subshell/t.sh"
  chmod +x "$work/subshell/t.sh"
  grep -qF 'MARKER_PATTERNS=()' "$work/subshell/t.sh" || fail "the unvalidated-markers fixture was not planted"
  catches "$work/subshell" "accepted an empty marker set" "a run that never validated its markers"

  echo "== the status check is able to fail: run reading the pipeline instead of the command"
  # The regression as it actually occurs: a harness with no pipefail that reads $? after
  # the pipe. Both halves are one defect — under pipefail alone, $? still happens to be
  # right whenever the *first* command is the one that failed, so planting only the $?
  # would prove nothing.
  copy "$work/blind"
  # shellcheck disable=SC2016  # the $? is the defect being planted, not an expansion
  sed -e 's/^set -uo pipefail$/set -u/' -e 's/local -a ps=("${PIPESTATUS\[@\]}")/local -a ps=($?)/' \
    t.sh >"$work/blind/t.sh.new" && mv "$work/blind/t.sh.new" "$work/blind/t.sh"
  chmod +x "$work/blind/t.sh"
  grep -qF 'local -a ps=($?)' "$work/blind/t.sh" || fail "the blind-status fixture was not planted"
  catches "$work/blind" "for a command that exited 7" "a run reading tee's status"

  echo "== the help-drift check is able to fail: a subcommand the help never mentions"
  copy "$work/undocumented"
  awk '/^  flaky\) cmd_flaky/ && !done { print "  wat) cmd_run \"$@\" ;;"; done=1 } { print }' \
    t.sh >"$work/undocumented/t.sh.new" && mv "$work/undocumented/t.sh.new" "$work/undocumented/t.sh"
  chmod +x "$work/undocumented/t.sh"
  grep -qF 'wat) cmd_run' "$work/undocumented/t.sh" || fail "the undocumented-subcommand fixture was not planted"
  catches "$work/undocumented" "its help never mentions it" "a subcommand missing from the help"

  echo "== the bisect status mapping is able to fail: statuses passed through raw"
  copy "$work/raw"
  # shellcheck disable=SC2016  # the $status is the defect being planted, not an expansion
  sed 's/^        \*) return 1 ;;$/        *) return "$status" ;; # planted/' t.sh >"$work/raw/t.sh.new" &&
    mv "$work/raw/t.sh.new" "$work/raw/t.sh"
  chmod +x "$work/raw/t.sh"
  grep -qF '# planted' "$work/raw/t.sh" || fail "the raw-status fixture was not planted"
  catches "$work/raw" "should be 1 to git bisect" "a probe returning a raw signal status"

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
  catches "$work/trailing" "byte for byte" "a falsify that loses the trailing newline"

  echo "== the allow-regex refusal is able to fail: the check that runs before the command"
  copy "$work/badallow"
  sed '/^    ((rc != 2)) || die "allow:/d' t.sh >"$work/badallow/t.sh.new" && mv "$work/badallow/t.sh.new" "$work/badallow/t.sh"
  chmod +x "$work/badallow/t.sh"
  ! grep -qF 'die "allow:' "$work/badallow/t.sh" || fail "the unvalidated-allow fixture was not planted"
  catches "$work/badallow" "grep cannot compile" "a run that applies an allow regex it never checked"

  echo "== the unwritten-mutant check is able to fail: a write taken on trust"
  copy "$work/unwritten"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed 's/ || fatal "falsify: cannot write \$file.*$//' t.sh >"$work/unwritten/t.sh.new" && mv "$work/unwritten/t.sh.new" "$work/unwritten/t.sh"
  chmod +x "$work/unwritten/t.sh"
  ! grep -qF 'falsify: cannot write' "$work/unwritten/t.sh" || fail "the unwritten-mutant fixture was not planted"
  if [[ $EUID -eq 0 ]]; then
    echo "   skipped: running as root, where the check itself is skipped"
  else
    catches "$work/unwritten" "could not write" "a falsify that does not check its write"
  fi

  echo "== the inconclusive-bisect check is able to fail: git's surrender read as success"
  copy "$work/surrender"
  sed 's/^    return 89$/    return 0/' t.sh >"$work/surrender/t.sh.new" && mv "$work/surrender/t.sh.new" "$work/surrender/t.sh"
  chmod +x "$work/surrender/t.sh"
  ! grep -qF 'return 89' "$work/surrender/t.sh" || fail "the surrender fixture was not planted"
  catches "$work/surrender" "want 89" "a bisect that reports an all-skipped history as resolved"

  echo "== the heard-refusal check is able to fail: flaky muting run's stderr with the command's"
  copy "$work/muted"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed 's|>/dev/null 2>"\$stamp/run-\$i.err"|>/dev/null 2>/dev/null|' t.sh >"$work/muted/t.sh.new" &&
    mv "$work/muted/t.sh.new" "$work/muted/t.sh"
  chmod +x "$work/muted/t.sh"
  grep -qF '>/dev/null 2>/dev/null' "$work/muted/t.sh" || fail "the muted-refusal fixture was not planted"
  catches "$work/muted" "hid run's refusal" "a flaky that mutes the harness's own refusals"

  echo "== the -t check is able to fail: a tail length taken on trust"
  copy "$work/anytail"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed '/^        \[\[ "\$tail_n" =~ \^\[0-9\]+\$ \]\] || die "run: -t needs a number/d' t.sh >"$work/anytail/t.sh.new" &&
    mv "$work/anytail/t.sh.new" "$work/anytail/t.sh"
  chmod +x "$work/anytail/t.sh"
  ! grep -qF 'die "run: -t needs a number' "$work/anytail/t.sh" || fail "the unvalidated-tail fixture was not planted"
  catches "$work/anytail" "accepted -t abc" "a run that takes -t on trust"

  echo "== the duplicate-set check is able to fail: a set named twice, loaded twice"
  copy "$work/twice"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed 's/^        add_marker_file "\$RESOLVED"$/        MARKER_FILES+=("$RESOLVED")/' t.sh >"$work/twice/t.sh.new" &&
    mv "$work/twice/t.sh.new" "$work/twice/t.sh"
  chmod +x "$work/twice/t.sh"
  # shellcheck disable=SC2016  # t.sh's own source text, not an expansion
  grep -qF '        MARKER_FILES+=("$RESOLVED")' "$work/twice/t.sh" || fail "the loaded-twice fixture was not planted"
  catches "$work/twice" "named twice printed" "a run that loads a marker set as often as it is named"

  echo "== the symlink check is able to fail: a harness that reads dirname of the link"
  copy "$work/unresolved"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed 's/^while \[\[ -L "\$self" \]\]; do$/while false; do/' t.sh >"$work/unresolved/t.sh.new" &&
    mv "$work/unresolved/t.sh.new" "$work/unresolved/t.sh"
  chmod +x "$work/unresolved/t.sh"
  grep -qF 'while false; do' "$work/unresolved/t.sh" || fail "the unresolved-symlink fixture was not planted"
  catches "$work/unresolved" "through the symlink" "a harness that does not resolve its own symlink"

  echo "== the verdict sidecar check is able to fail"
  copy "$work/nosidecar"
  # The write goes to /dev/null rather than being deleted: deleting it leaves RUN_VERDICT
  # unreferenced, and the copy would then fail on shellcheck instead of on the check
  # shellcheck disable=SC2016  # $log is t.sh's own source text being matched, not an expansion
  sed 's|>"\$log\.verdict"|>/dev/null|' t.sh >"$work/nosidecar/t.sh.new" && mv "$work/nosidecar/t.sh.new" "$work/nosidecar/t.sh"
  chmod +x "$work/nosidecar/t.sh"
  # shellcheck disable=SC2016  # t.sh's own source text, not an expansion
  ! grep -qF '>"$log.verdict"' "$work/nosidecar/t.sh" || fail "the missing-sidecar fixture was not planted"
  catches "$work/nosidecar" "did not record" "a run that keeps its verdict to itself"

  echo "== the log-is-writable guard is able to fail"
  copy "$work/nolog"
  # shellcheck disable=SC2016  # $log is t.sh's own source text being matched, not an expansion
  guard=': >"$log" || fatal'
  grep -vF "$guard" t.sh >"$work/nolog/t.sh.new" && mv "$work/nolog/t.sh.new" "$work/nolog/t.sh"
  chmod +x "$work/nolog/t.sh"
  ! grep -qF "$guard" "$work/nolog/t.sh" || fail "the missing-guard fixture was not planted"
  catches "$work/nolog" "nowhere to put its log" "a run that cannot write its log"
fi

echo
echo "check: everything holds"
