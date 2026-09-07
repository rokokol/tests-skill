# Proving a check can fail

A check that has never been red is a decoration: nobody knows whether it guards anything, and it will keep being green after the thing it watches stops working. The literature has a name for the common case — a *pseudo-tested* method, one a coverage tool calls covered and whose whole body can be deleted without a single test failing — and measured it at between six and fifty-three percent of the methods in real projects, coverage notwithstanding. The discipline is the same wherever a check is born.

- **Red first.** A new check runs against the pre-fix state, or against a deliberately broken input, and is watched failing — *then* the code that turns it green lands. When a check is adopted into a repository that already violates it, that first red run on the real violation is the proof; only then align the state.
- **Checkers ship self-tests.** A gate that lints, greps or compares runs itself against known-bad fixtures and exits non-zero unless those fixtures fail. This repository's [`check.sh`](../check.sh) does exactly that with itself, and every one of its steps was watched failing before it was trusted.
- **Extractors refuse to find nothing.** Any check that parses a list out of a file — markers, flags, subcommand names — must fail loudly when it extracts zero items. A loop over an empty list passes silently, which is indistinguishable from "no problems found".
- **Whole-line assertions on generated text.** `grep -qxF`, not a substring match: two similar outputs make a substring check pass for the wrong one, and it will be the wrong one exactly when it matters.
- **Un-mute before diagnosing.** When one environment fails where the rest pass, the first move is removing the `2>/dev/null`. An older tool rejecting newer syntax disappears into muted stderr and presents as "empty output".
- **Probe the mechanism, not a proxy.** A check must measure the thing the code actually depends on. A grep for bash-4 syntax matched the constructs somebody thought to list and let nine through; a run under a real bash 3.2 is the mechanism, and it found three more bugs the grep could never see.
- **A check must not share the blind spot of what it checks.** Comparing `$(cat file)` with `$(cat file)` cannot see a lost trailing newline, because command substitution strips it from both sides. Compare bytes with `cmp`, or ask `git diff`, which has no opinion about what a line is.
- **A refusal must run where it can actually refuse.** In shell, `exit` inside a `$(...)`, a `( )` or a pipeline stage ends the subshell, and the caller carries on with an empty string. A guard written there does not guard: it prints to stderr and is ignored. Validate before the substitution, in the shell that can still stop.
- **A check that hangs when it fails is not a check.** A watchdog around anything that can loop, so the failure is a red line and not a job that a runner kills an hour later with no name attached.

## The four-command version

The smallest falsification needs no harness. Write the test, run it green; take the fix out, run it, and it must go red; put the fix back, run it green. Four commands, and the middle one is the only evidence that the test is about the fix. `t.sh prove HEAD -- CMD` does exactly that for one commit: it splits the commit's files into tests and code by the same rule below, takes the code back to what it was before the commit, keeps the tests, and requires the suite to go red — `proven`, or `VACUOUS` when the tests pass without the fix, which means they pin nothing the commit did. It is the cost of a test and its code sharing a commit, and it is cheap.

## Falsifying a suite: `t.sh falsify`

A green suite says the code passes. Whether it would fail if the code stopped working is a separate question, and it is answered mechanically: break one guard on purpose, rerun the suite, and see whether it notices.

`t.sh falsify` reads [`tests/defects.sh`](../templates/defects.sh) — a plain bash file calling `defect NAME FILE FIND REPLACE CONSEQUENCE`, one entry per guard, written by hand. **Nothing is generated.** Tools that invent mutants produce hundreds per change, most of them noise, and the studies that made them useful at scale did so by suppressing the noise until a handful per file was left; a hand-written list starts where they ended, with the useful knowledge — what each guard is *for* — that only a person has. The file is `source`d, so it is code: read it in review like code, and never run a defect list you have not read.

Six verdicts, and the distinctions between them are the whole point:

- **`caught`** — the suite went red. That guard is genuinely covered.
- **`SURVIVED`** — the suite stayed green with the guard broken, and the entry's consequence sentence is printed with the file, the line and the edit. That sentence, in operator's terms, names what nobody checks. It is the output worth reading, and the run exits 83.
- **`expected`** — the entry was declared `expect survived REASON`, an edit nothing can observe, and it survived as declared. No finding. The day the suite does catch it, the declaration is reported `stale`, so an exception cannot outlive its truth.
- **`stale`** — the find text no longer matches exactly once in the file, or a declared exception was disproved. Not guessed at, not silently skipped: a defect list that has drifted from its code stops testing what it was written for, and this is how it says so. Exit 87.
- **`unusable`** — the edit stopped the code building, so the tests were never asked. This is the verdict that keeps the report honest in compiled languages: without it, every syntax-breaking edit would be credited as `caught` and the suite would appear to cover code nothing touches. Exit 88, and a fault of the entry, never of the suite.
- **`TIMEDOUT`** — the suite did not finish within the deadline, five times its unbroken time or twenty seconds, whichever is more. A neutered guard is often a loop that no longer ends; neither the suite's credit nor its fault. Exit 84.

What was found is left in `falsify.out/`: one file of names per verdict, which is what a diff between two runs or a grep in CI wants, a log per defect, and `results.json`. On a GitHub runner a survivor is also an annotation on its file and line, in the diff of the pull request, because a finding next to the code is read by whoever is about to merge it and a finding in a log by whoever opens the log.

The safety properties that make it something you can run on a Friday:

- **Build and test are separate phases** (`-b`), which is what makes `unusable` reachable at all.
- **A suite already red aborts the run.** Falsification measures the distance between green and red; starting red there is no distance, and every `caught` would be an artefact. A suite that "passes" while its log says nothing ran is refused for the same reason. Exit 85.
- **The working tree must be clean**, and a defect in a test, vendored or generated file is refused: a test file is executed, so an edit there is "caught" by whatever it breaks and proves nothing. `--worktree` edits a checkout of HEAD in a git worktree instead of the files in front of you, so a format-on-save, a file watcher or a commit made mid-run cannot meet a mutant.
- **The original is held in memory and written back in a trap** covering interrupt and termination, then compared byte for byte. A marker names the defect in flight while it is on disk, `FALSIFY-IN-PROGRESS` in the worktree or `in-flight` under `falsify.out/`, so a mutant that outlives a run is found by the name of what put it there.
- **`--since REF` runs only the defects in files changed since a ref**, for a pull request. It is a filter and not a proof — a change in one file breaks the tests of another — so the full list runs on the default branch, and an empty selection is said out loud.

## Writing the defect list

Write one entry as each guard is written, and it doubles as prose documentation of what the guard is for. The shapes, in order of what they find:

1. **The whole body of a function replaced by a constant of the right type.** This is the pseudo-tested-method probe, and the edit that finds the most while keeping the find text unique: a body is long, an operator is one character in twenty places. The suite that survives it covers that function with nothing.
2. **One guard neutered.** `if x < 0` to `if false`, a filter dropped, a comparison widened (`>=` to `>`), an early return removed, `any` swapped for `all`, an error branch replaced by a plain return, a `?` or a `try` turned into the happy path. Each asks about one behaviour. The catalogue per language is in `references/ecosystems/`.

And the rules that keep the list worth reading:

- **Neuter, do not break.** Edits that keep the code valid and change what it does are the ones that ask about behaviour. An edit that breaks syntax asks about the parser, and is reported `unusable`.
- **Write the consequence in the operator's words** — "something that did not answer reads as healthy and quiet", not "the unreachable branch is skipped". When the suite survives, that sentence is the finding, and it should be legible to whoever would have been paged.
- **Never against logging, formatting, comments or a trivial accessor.** A survivor there teaches nothing and trains everyone to skim the report; the tools that run at scale suppress exactly these and went from fifteen percent of their findings being acted on to over eighty.
- **About seven per file, one per behaviour, never two on the same line.** Past that the report stops changing what people write. Random samples of five percent of a generated mutant set carry almost all of its signal; twenty chosen defects carry more.
- **Declare what nothing can catch, on the line.** `expect survived REASON` for an edit that changes the code without changing anything a caller can observe — the order of a cosmetic sort, a log message — with the reason next to the claim, where the next reader will find it.
- **A caught defect can still be a bad one.** When a defect is caught by forty unrelated tests, the suite noticed but cannot say what; the entry is aimed too high. One focused test going red is the shape to aim for, because it is the shape whose failure message names the cause.

## The entry to legacy code

A suite whose value is unknown gets its first defect list from *characterization*: write an assertion you know to be wrong about what a function returns, run it, and let the failure message tell you what the code actually does; pin that as the expected value, and now write the defect that would change it. The first is a test of the code as it is, the second is the proof that the test is about the code. Repeat for every function that matters, and the list documents the behaviour nobody wrote down.

## What this does and does not prove

Falsification catches one failure mode of a test suite: the test that cannot fail. The other one — the *change-detector* test, which fails for edits that change no behaviour because it asserts the implementation's shape rather than its result — is invisible to it, and only reading the test catches it; see [layers.md](layers.md) for that catalogue. And the score is not the goal. A suite where every defect is caught has been shown to catch twenty defects; the finding worth having is the survivor, read by the person who can write the test, which is why the sentence beside it is the part written with care. **Copying a defect list proves nothing.** The mechanism travels; the knowledge does not. A falsifier that has only ever printed `caught` may simply be matching nothing — run it, watch something survive, and only then believe the green. The evidence for every claim above is in [sources.md](sources.md).
