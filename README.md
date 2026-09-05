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
| **[One logical change per commit](references/commits.md)** | The failing test is its own commit, the fix is the next one, and every commit in between builds and passes. That is what makes `git bisect` able to answer, and bisect is how a regression stops being an argument |
| **[Fix or quarantine, never retry](references/flaky.md)** | A test that passes and fails on the same code gets fixed or taken out of the gate with a dated, visible debt entry. An automatic rerun converts a real race into a green run and teaches everyone to press the button |
| **[No shim for a shape that was never released](references/no-legacy.md)** | Until the version ships, a rename is a rename: the old name, its callers and its tests go in the same commit. Anything that was never a published contract never earns a shim at all |
| **Keep a running todo list** | One item per red-green-refactor cycle, one for the falsification pass, one per test you quarantine. Small ritual; it is what keeps the second half of a plan from evaporating once the first half goes green |

The core is not negotiable because every rule in it is true in any language. Everything past it — [how many layers to keep, how much to fake, what coverage is worth](references/layers.md) — is a real choice with a real cost, and the skill states the cost rather than the answer. `references/ecosystems/` carries the per-language specifics for pytest, shell, go, rust, node, typescript and c++

## The harness

[`t.sh`](t.sh) is the mechanical half — the command is always explicit after `--`, because a harness that guesses what your suite is runs the wrong thing on the day it matters:

| Command | What it answers |
|---|---|
| `t.sh run -- CMD` | did it pass — status kept honest, whole log kept, log read even at exit 0 |
| `t.sh flaky N -- CMD` | do repeated runs of the same code disagree with each other |
| `t.sh bisect GOOD -- CMD` | which commit broke it, skipping the ones that cannot answer |
| `t.sh falsify -- CMD` | which guards the suite would not notice being broken |

`run` is the only place a verdict is formed and the other three call it, so `bisect` cannot drift away from `run` about what counts as a failure. It exits with the command's own status, except **3** when the command exited 0 while its log said otherwise, and **4** when repeated runs disagreed

`bisect` speaks git's vocabulary properly: 125 for a commit that cannot answer — one that will not build, has no test runner yet, or whose log says nothing ran — and a crash clamped to "bad" rather than the 139 that would abort the whole session

## Markers and policy

What counts as "the log said otherwise" is data, not code: [`markers/`](markers/) holds one line per way a run lies about itself. `default.txt` always applies and may only contain lines a healthy run never prints; anything noisier is a per-ecosystem set opted into with `-m rust`, or your own file with `-m tests/markers.txt`. A set that resolves to nothing — missing, empty, misspelled — is a refusal to run rather than a quiet pass

A repository declares its own policy once in `tests/t.conf` ([template](templates/t.conf)) rather than retyping flags — which marker sets apply, which lines are excused, where logs go. It is read from the current directory only, and it **never carries the command**: what runs stays after `--`, in the line you typed, so a green run's subject is always visible where the verdict is. An unknown key or a missing marker set stops the run and names the line, because a typo that is skipped leaves you believing in markers that were never loaded

## Falsifying a suite

```sh
t.sh falsify -b 'cargo build --workspace' -- cargo test --workspace
```

It applies, one at a time, edits written by hand in the repository's own `tests/defects.sh` and requires the suite to notice. **Nothing is generated** — tools that invent mutants mostly produce code that will not compile, and a compiler error is not a test noticing anything

Four verdicts, and the distinctions are the point: `caught`, `SURVIVED` (printing the entry's consequence sentence, which names what nobody checks), `stale` (the find text no longer matches exactly once, so the list has drifted from its code) and `unusable` (the edit stopped it building, so the tests were never asked — the verdict that keeps a compiled language's report honest)

It refuses to start on a dirty tree or against an already-red suite, holds the original in memory, restores it in a trap that covers an interrupt, and compares byte for byte afterwards

> [!IMPORTANT]
> Copying a defect list proves nothing. The mechanism travels, the knowledge does not — a falsifier that has only ever printed `caught` may simply be matching nothing. Run it, watch something survive, and only then believe the green

## Tests

```sh
nix develop -c ./check.sh
```

Lints what the skill ships, checks that SKILL.md is loadable and that every reference, link and heading anchor resolves — then proves each of those able to fail against a deliberately broken copy. The marker files are read by the gate exactly as `run` reads them, and every entry must catch a line in its own fixture while no default one may fire on a healthy log, so a dead marker cannot sit there looking like a guard

The behavioural halves are proven the same way: a command exiting 7 through a pipe must still be reported 7; a green run whose log says nothing was collected must not be a pass; a config with an unknown key must refuse rather than skip it; `bisect` must name the known culprit across a history containing a commit that will not build; and `falsify` must return `caught`, `SURVIVED`, `stale` and `unusable` on a fixture built to produce exactly one of each. Every one of them was watched failing first — several found real bugs in this repository while being written

## Layout

```
SKILL.md              the rules an agent reads
t.sh                  the harness: run / flaky / bisect / falsify
markers/              what a lying log says, as data: default.txt always, the rest via -m
references/           one spec per rule, plus ecosystems/ for the per-language specifics
templates/            defects.sh for falsify, t.conf for a repository's own policy
check.sh              the self-testing gate
tests/fixtures/       the known-bad inputs the checks must catch
```

CI doctrine — what may gate a pull request, pinning, badges, dependency cascades — is not duplicated here; it lives in the [ci](https://github.com/rokokol/ci-skill) skill. What may go in a commit *message* lives in [ai-commit-trailers](https://github.com/rokokol/ai-commit-trailers-skill)
