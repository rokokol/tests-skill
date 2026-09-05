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

echo "== the workflows are valid, and their tools come from the lock rather than a registry"
actionlint
# This repo follows its own advice about pinning: a job that resolves a tool at run time
# changes behaviour with zero change in the repository. The guard is here as well as in the
# workflow, so it also fails locally rather than only after a push.
if grep -rEn 'nix (run|shell) nixpkgs#|npx +[a-z@.-]|pip +install |go +install .*@latest' .github/workflows; then
  fail "an unpinned registry lookup in a workflow — pin the tool in the flake's dev shell and use nix develop"
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
((status == 2)) || fail "run accepted a marker set that does not exist (got $status)"
: >"$work/empty-markers.txt"
status=0
./t.sh run -t 0 -l "$work/logs" -m "$work/empty-markers.txt" -- true >/dev/null 2>&1 || status=$?
((status == 2)) || fail "run accepted an empty marker set, which reads as a working check (got $status)"

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
in_conf 3 "a marker set named in the config applies" -- sh -c 'echo "running 0 tests"; exit 0'
policy 'pattern thread panicked in setup'
in_conf 3 "a pattern named in the config applies" -- sh -c 'echo "thread panicked in setup"; exit 0'
policy 'allow expected: no tests ran'
in_conf 0 "a line the config excuses is excused" -- sh -c 'echo "expected: no tests ran"; exit 0'
policy 'command cargo test'
in_conf 2 "an unknown key refuses rather than reading as no policy" -- true
policy 'markers'
in_conf 2 "a key with no value refuses" -- true
policy 'markers nosuchset'
in_conf 2 "a marker set the config names but does not exist refuses" -- true
rm -f "$conf/tests/t.conf"
in_conf 0 "a repository with no config is the normal case" -- sh -c 'echo "47 passed"; exit 0'
# The template is the thing people copy, so it has to parse — an example config that the
# harness refuses would teach the format wrong on the first try
status=0
T_CONFIG=templates/t.conf ./t.sh run -t 0 -l "$work/logs" -- sh -c 'echo "47 passed"; exit 0' \
  >/dev/null 2>&1 || status=$?
((status == 0)) || fail "templates/t.conf is not a config t.sh accepts (got $status)"

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
    mkdir -p "$dest/tests/fixtures/lying" "$dest/templates"
    cp t.sh check.sh SKILL.md README.md "$dest/"
    cp -r references markers "$dest/"
    cp templates/defects.sh "$dest/templates/"
    cp tests/fixtures/*.log "$dest/tests/fixtures/"
    cp tests/fixtures/lying/*.log "$dest/tests/fixtures/lying/"
  }
  nested() { (cd "$1" && T_CHECK_NESTED=1 ./check.sh >/dev/null 2>&1); }

  echo "== the frontmatter check is able to fail"
  copy "$work/nofront"
  printf 'no frontmatter here\n' >"$work/nofront/SKILL.md"
  ! nested "$work/nofront" || fail "a SKILL.md with no frontmatter passed the gate — nothing would load it"

  echo "== the hard-wrap check is able to fail"
  copy "$work/wrapped"
  printf '\nThis paragraph is hard-wrapped across\ntwo lines, which GitHub would reflow\n' \
    >>"$work/wrapped/README.md"
  ! nested "$work/wrapped" || fail "a hard-wrapped paragraph passed the gate"

  echo "== the reachability check is able to fail: a reference nothing links to"
  copy "$work/orphan"
  : >"$work/orphan/references/nothing-points-here.md"
  ! nested "$work/orphan" || fail "a reference nothing links to passed the gate"

  echo "== the link check is able to fail: a link to a file that is not there"
  copy "$work/deadlink"
  printf '\nSee [the missing one](references/not-a-file.md).\n' >>"$work/deadlink/SKILL.md"
  ! nested "$work/deadlink" || fail "a link to a missing file passed the gate"

  echo "== the anchor check is able to fail: a link to a heading that does not exist"
  copy "$work/deadanchor"
  printf '\nSee [nowhere](references/verdict.md#no-such-heading).\n' >>"$work/deadanchor/SKILL.md"
  ! nested "$work/deadanchor" || fail "a link to a nonexistent heading passed the gate"

  echo "== the marker check is able to fail: a dead entry"
  copy "$work/dead"
  printf 'a marker matching nothing\n' >>"$work/dead/markers/default.txt"
  ! nested "$work/dead" || fail "a marker matching nothing passed the gate — the marker check catches nothing"

  echo "== the marker check is able to fail: an entry that fires on a healthy run"
  copy "$work/noisy"
  printf 'test session starts\n' >>"$work/noisy/markers/default.txt"
  ! nested "$work/noisy" || fail "a marker that fires on the clean fixture passed the gate"

  echo "== the duplicate check is able to fail: a set repeating a default marker"
  copy "$work/dupe"
  printf 'no tests ran\n' >>"$work/dupe/markers/go.txt"
  ! nested "$work/dupe" || fail "a set repeating a default marker passed the gate — the copy adds nothing"

  echo "== the marker check is able to fail: a set with no fixture behind it"
  copy "$work/unproven"
  printf 'no tests ran\n' >"$work/unproven/markers/invented.txt"
  ! nested "$work/unproven" || fail "a marker set with no fixture passed the gate — its entries are unproven"

  echo "== the unknown-key refusal is able to fail: a config that ignores what it cannot parse"
  # The tempting form. An ignored key is a policy silently not in effect, which is worse
  # than no config at all: the repository believes markers are loaded that never were.
  copy "$work/lenient"
  # shellcheck disable=SC2016  # t.sh's own source text is being matched, not expanded
  sed 's|^      \*) die "config: \$conf:\$n — unknown key.*|      *) : ;;|' t.sh >"$work/lenient/t.sh.new" &&
    mv "$work/lenient/t.sh.new" "$work/lenient/t.sh"
  chmod +x "$work/lenient/t.sh"
  grep -qF '*) : ;;' "$work/lenient/t.sh" || fail "the lenient-config fixture was not planted"
  ! nested "$work/lenient" || fail "a config that ignores an unknown key passed the gate"

  echo "== a refusal written inside a subshell is able to fail"
  # `die` in a $(...) exits the subshell, so the caller carries on with an empty string.
  # Written that way, the empty-marker-set refusal would not refuse — and an empty marker
  # list makes every run a pass while the check still looks like it is working.
  copy "$work/subshell"
  sed 's/^  load_markers$/  MARKER_PATTERNS=()/' t.sh >"$work/subshell/t.sh.new" &&
    mv "$work/subshell/t.sh.new" "$work/subshell/t.sh"
  chmod +x "$work/subshell/t.sh"
  grep -qF 'MARKER_PATTERNS=()' "$work/subshell/t.sh" || fail "the unvalidated-markers fixture was not planted"
  ! nested "$work/subshell" || fail "a run that never validated its markers passed the gate"

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
