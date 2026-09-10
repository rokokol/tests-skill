<div align="center">

# tests skill

**A green run that means something ⊂(‘ω’⊂ )))Σ≡=─༄༅༄༅༄༅༄༅༄༅**

![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=flat&logo=anthropic&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![ci](https://github.com/rokokol/tests-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/rokokol/tests-skill/actions/workflows/ci.yml)

</div>

A suite tells you the code passed. It does not tell you the suite would have noticed if the code had stopped working — and that second question is the only one a green run is worth anything for

This skill teaches an agent to keep the answer honest: a verdict no pipe can swallow, a log that gets read even when the status says success, a check watched failing before anyone trusts it, a history granular enough to ask *which commit* later, and no compatibility shim for a shape that was never released. `t.sh` beside it is the mechanical half, so following the rules costs less than not

## Contents

- [Install](#install)
- [The core](#the-core)
- [The harness](#the-harness)
- [Markers and policy](#markers-and-policy)
- [Falsifying a suite](#falsifying-a-suite)
- [Tests](#tests)
- [Layout](#layout)

## Install

```sh
git clone https://github.com/rokokol/tests-skill ~/Projects/tests
ln -s ~/Projects/tests ~/.claude/skills/tests
```

Or straight into the skills directory your agent reads:

```sh
git clone https://github.com/rokokol/tests-skill ~/.claude/skills/tests
```

> [!NOTE]
> A skill has no version to pin — it is read at whatever revision you have checked out, so `git pull` is the whole upgrade path and the changelog is dated rather than numbered

Then ask Claude Code to write, run or review tests, or reach for it by name. [SKILL.md](SKILL.md) carries the rules and `references/` the reasoning behind each

## The core

| | |
|---|---|
| **[The status you act on is the command's own](references/verdict.md)** | `pytest \| tail -n 40` exits 0 for a suite that just failed, because the status belongs to `tail`. So does `\| tee`, `\| grep`, and every pipeline in a shell without `pipefail`. Never let a summarising pipe stand between a run and its verdict |
| **[Exit 0 is not a synonym for success](references/verdict.md)** | `collected 0 items`, `no tests ran`, a traceback logged by a passing test, a service that starts cleanly and then fills its own log with errors — all of these exit 0. A pass is a status that says so *and* an output that agrees |
| **Nothing is done until it has been run and watched** | Before saying a thing works, execute the command that would prove it wrong and read the whole output. "Should work", "the change is trivial" and a subagent's report are not evidence |
| **[Test first, then prove the test can fail](references/tdd.md)** | Write the test, watch it fail for the reason you intended, make it pass — and afterwards, separately, break the code on purpose and require the suite to notice. A check that has never been red is a decoration |
| **Never weaken a check to get a green run** | An assertion loosened, a test skipped, a threshold lowered, a retry added: each is the code passing a test that no longer asks the question. Fix the test to ask the right question, or fix the code; there is no third move |
| **[Evidence is a run after the last edit, read by someone else](references/verdict.md)** | A run from before the change proves nothing about it. When one session wrote both the code and its tests, the tests describe the code rather than constrain it, and the constraint comes from a test written first, a case somebody else wrote, or a falsification pass |
| **[One logical change per commit, the test and its code together](references/commits.md)** | The red is watched before the commit, the commit carries both and passes, and `t.sh prove` takes the fix back out to show the test notices. That is what makes `git bisect` able to answer, and bisect is how a regression stops being an argument |
| **[Three failed fixes mean the model is wrong](references/debugging.md)** | No fix before a cause, one hypothesis at a time, and after the third that did not hold, stop and say so with the three that were tried |
| **[Fix or quarantine, never retry](references/flaky.md)** | A test that passes and fails on the same code gets fixed or taken out of the gate with a dated, visible debt entry. An automatic rerun converts a real race into a green run and teaches everyone to press the button |
| **[No shim for a shape that was never released](references/no-legacy.md)** | Until the version ships, a rename is a rename: the old name, its callers and its tests go in the same commit. Anything that was never a published contract never earns a shim at all |
| **Keep a running todo list** | One item per red-green-refactor cycle, one for the falsification pass, one per test you quarantine. Small ritual; it is what keeps the second half of a plan from evaporating once the first half goes green |

The core is not negotiable because every rule in it is true in any language. Everything past it — [how many layers to keep, how much to fake, what coverage is worth](references/layers.md) — is a real choice with a real cost, and the skill states the cost rather than the answer. `references/ecosystems/` carries the per-language specifics for pytest, shell, go, rust, node, typescript, c++, the jvm, .net, php, and playwright with the rest of end-to-end

## The harness

[`t.sh`](t.sh) is the mechanical half — the command is always explicit after `--`, because a harness that guesses what your suite is runs the wrong thing on the day it matters:

| Command | What it answers |
|---|---|
| `t.sh run -- CMD` | did it pass — status kept honest, whole log kept, log read even at exit 0 |
| `t.sh flaky N -- CMD` | do repeated runs of the same code disagree with each other |
| `t.sh focused [PATH...]` | is a `.only` left in the source, so the runner skips most of the suite and exits 0 |
| `t.sh quarantine [FILE]` | is a test out of the gate past the date somebody promised to look at it |
| `t.sh pollute VICTIM -- CMD` | which earlier test makes this one fail, by halving the order |
| `t.sh bisect GOOD -- CMD` | which commit broke it, skipping the ones that cannot answer |
| `t.sh falsify -- CMD` | which guards the suite would not notice being broken |
| `t.sh prove [REF] -- CMD` | does the commit's own test go red when its fix is taken away |

`run` is the only place a verdict is formed and the others call it, so `bisect` cannot drift away from `run` about what counts as a failure. It exits with the command's own status and writes the kind of verdict beside the log as `LOG.verdict`, one word; its own verdicts sit in a band no test runner uses, 64 to 89, because the low numbers were tried first and collide: GNU make exits 2 on any error, pytest uses 2 to 5, and cargo-nextest exits 4 for "no tests ran", the very thing `run` exists to catch. `t.sh help` carries every flag, variable and code, and the gate reads that help against the parsers so the two cannot drift

`bisect` speaks git's vocabulary properly: 125 for a commit that cannot answer — one that will not build, has no test runner yet, or whose log says nothing ran — a crash clamped to "bad" rather than the 139 that would abort the whole session, and a Ctrl-C passed through so it does abort. It names the culprit on its own line, reports a history where only such commits are left as `INCONCLUSIVE`, keeps git's session log for a replay, and refuses to start over a bisect already in progress

## Markers and policy

What counts as "the log said otherwise" is data, not code: [`markers/`](markers/) holds one line per way a run lies about itself. `default.txt` always applies and may only contain lines a healthy run never prints; anything noisier is a per-ecosystem set opted into with `-m rust`, or your own file with `-m tests/markers.txt`. Every set has a real healthy run of its tool kept beside it, and no marker may fire on one, because the rust set once did and reddened every good `cargo test`. A set that resolves to nothing — missing, empty, misspelled — is a refusal to run rather than a quiet pass, and where the runner itself can refuse an empty run, each ecosystem reference names that switch instead

A repository declares its own policy once in `tests/t.conf` ([template](templates/t.conf)) rather than retyping flags — which marker sets apply, which lines are excused, where logs go. It is read from the current directory only, and it **never carries the command**: what runs stays after `--`, in the line you typed, so a green run's subject is always visible where the verdict is. An unknown key or a missing marker set stops the run and names the line, because a typo that is skipped leaves you believing in markers that were never loaded

## Falsifying a suite

```sh
t.sh falsify -b 'cargo build --workspace' -- cargo test --workspace
```

It applies, one at a time, edits written by hand in the repository's own `tests/defects.sh` and requires the suite to notice. **Nothing is generated** — tools that invent mutants produce hundreds per change and made themselves useful by suppressing them down to a handful; a hand-written list starts there, with the one thing only a person has, what each guard is for

Six verdicts, and the distinctions are the point: `caught`; `SURVIVED`, with the consequence sentence that names what nobody checks and the file, line and edit beside it; `expected`, for an edit declared on its line as one nothing can observe, which turns `stale` the day the suite does catch it; `stale`, the find text no longer matching exactly once, so the list has drifted from its code; `unusable`, the edit stopped it building, so the tests were never asked; and `TIMEDOUT`, the run did not finish within five times the unbroken suite's time. Each kind of not-caught has its own exit code, so CI can tell a weak suite from a rotten list, and each is an annotation on the file and line on a GitHub runner

It refuses to start on a dirty tree, against an already-red suite, or with a defect aimed at a test file; holds the original in memory; restores it in a trap that covers an interrupt; and compares byte for byte afterwards. `--worktree` edits a checkout in a git worktree instead of the files in front of you, `--since REF` runs only the defects in files a pull request touched, and what was found is left in `falsify.out/`: one file of names per verdict, a log per defect, `results.json`

`t.sh prove HEAD -- CMD` is the smallest falsification, done for one commit: the commit's test files stay, its code goes back to what it was, and the suite must go red — `proven`, or `VACUOUS` when the tests pass without the fix and so pin nothing the commit did. It is what "a test and its fix are one commit" costs, and it is cheap

> [!IMPORTANT]
> Copying a defect list proves nothing. The mechanism travels, the knowledge does not — a falsifier that has only ever printed `caught` may simply be matching nothing. Run it, watch something survive, and only then believe the green

## Tests

```sh
nix develop -c ./check.sh              # both halves
nix develop -c ./check.sh lint         # what the skill ships: scripts, workflows, docs, markers
/bin/bash ./check.sh behaviour         # what the harness does, under any bash from 3.2 up
```

The lint half runs the [ci](https://github.com/rokokol/ci-skill) skill's own gates for a skill repository, `check-skill.sh` and `check-pins.sh`, copied verbatim, lints every script, holds every document to one paragraph per line, and reads the marker files exactly as `run` reads them: every entry must catch a line in its set's lying fixture and stay quiet on a real healthy run of its tool, kept under `tests/fixtures/clean/`, so a dead marker cannot sit there looking like a guard and a noisy one cannot redden good runs

The behaviour half is proven the same way: a command exiting 7 through a pipe must still be reported 7; a green run whose log says nothing was collected must not be a pass; a config with an unknown key must refuse rather than skip it; `bisect` must name the known culprit across a history containing a commit that will not build and say `INCONCLUSIVE` where nothing can answer; `falsify` must return each of its verdicts on a fixture built to produce exactly one of each, time out a defect that hangs, and put the source back byte for byte after an interrupt; `prove` must tell a test that pins its fix from one that does not. CI runs this half on a macOS runner under `/bin/bash` 3.2, with a `declare -A` and a `mapfile` planted in copies that must fail there, because a grep for bash-4 syntax was the guard once and let nine constructs through

Then every check is proven able to fail: a copy of the repository per planted defect, and each copy must fail for its own defect's reason. Every one of them was watched failing first — a dozen found real bugs in this repository while being written, three of them only under a real bash 3.2

## Layout

```
SKILL.md              the rules an agent reads, and the checklist before "it works"
t.sh                  the harness; `t.sh help` lists every subcommand
markers/              what a lying log says, as data: default.txt always, the rest via -m
references/           one spec per rule, ecosystems/ per language, sources.md for the evidence
templates/            defects.sh for falsify, t.conf for a repository's own policy
check.sh              the self-testing gate, in a lint half and a behaviour half
check-skill.sh        the ci skill's gate for a skill repository, verbatim
check-pins.sh         the ci skill's pin guard for the workflows, verbatim
tests/fixtures/       lying/ the runs the markers must catch, clean/ the healthy ones they must not
```

CI doctrine — what may gate a pull request, pinning, badges, dependency cascades — is not duplicated here; it lives in the [ci](https://github.com/rokokol/ci-skill) skill. What may go in a commit *message* lives in [ai-commit-trailers](https://github.com/rokokol/ai-commit-trailers-skill)
