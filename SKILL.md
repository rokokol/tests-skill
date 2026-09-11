---
name: tests
description: "What it is — a standard for tests that mean something when they are green: a verdict no pipe can swallow, logs read even at exit 0, every check watched failing before it is trusted, test-first with a falsification pass behind it, commits granular enough to bisect, and no compatibility shims for a shape that was never released. Use when writing, running or reviewing tests, judging whether a green run or an exit code proves anything, finding the commit that broke a test or the earlier test that pollutes it, deciding what to do about a test that passes and fails on the same code, or setting up testing in a new repo. Triggers: tests, test suite, coverage, TDD, flaky, mock, fixture, golden file, bisect, which commit broke it, test pollution, .only, exit code, pipefail, debugging, mutation, property-based, e2e, quarantine, напиши тест, покрытие, тесты падают, зелёный прогон, нестабильный тест, какой коммит сломал, падает только в общем прогоне, код возврата, отладка, карантин."
license: MIT
---

# tests

A suite tells you the code passed. It does not tell you the suite would have noticed if the code had stopped working — and that second question is the only one a green run is worth anything for. Everything here serves it: a verdict that cannot be swallowed by a pipe, a log that gets read even when the status says success, a check watched failing before anyone trusts it, and a history granular enough to ask *which commit* later

The core below is not negotiable, because each rule is true in every language and every repository. Everything past it — how many layers of test to keep, how much to mock, how big a step to take — is a real choice with a real cost, and this skill states the cost rather than the answer. [`t.sh`](t.sh) beside this file is the operational half

## The core

- **The status you act on is the command's own.** `cmd | tail -n 40` exits 0 for a suite that just failed, because the status belongs to `tail`; so does `| tee`, `| grep`, and every pipeline whose shell has no `pipefail`. Capture `${PIPESTATUS[0]}`, or run the command and read the log afterwards. Never let a summarising pipe stand between a run and its verdict. See [references/verdict.md](references/verdict.md)
- **Exit 0 is not a synonym for success — read the log.** `collected 0 items`, `no tests ran`, a traceback logged by a test that still passed, a service that started cleanly and then filled its own log with errors: all of these exit 0. A run is a pass when its status says so *and* its output agrees. See [references/verdict.md](references/verdict.md)
- **Nothing is done until it has been run and watched.** Before saying a thing works, execute the command that would prove it wrong and read the whole output. "Should work", "the change is trivial", and a subagent's report are not evidence. This applies to the real program as much as to its suite: start it, drive it, read its log
- **Test first, then prove the test can fail.** Write the test before the code, watch it fail for the reason you intended, then make it pass — and afterwards, separately, break the code on purpose and require the suite to notice. The first half stops you writing a test that only describes what the code already does; the second catches the test that passes no matter what. A check that has never been red is a decoration. See [references/tdd.md](references/tdd.md) and [references/falsifiability.md](references/falsifiability.md)
- **Never weaken a check to get a green run.** An assertion loosened, a test skipped or deleted, a threshold lowered, an error swallowed, a retry added — each is the code passing a test that no longer asks the question. When a test is wrong, fix the test to ask the right question; when the code is wrong, fix the code. There is no third move
- **Evidence is a run made after the last edit, read by someone other than the author of the claim.** A run from before the change proves nothing about it, and re-running unchanged code proves nothing twice. When one session wrote both the code and its tests, the tests describe the code rather than constrain it: the constraint comes from a test written first, a case somebody else wrote, or a falsification pass — never from the same hand grading its own work. See [references/verdict.md](references/verdict.md)
- **One logical change per commit, the test and the code it pins together.** The red was watched before the commit; the commit carries both and passes; `t.sh prove HEAD -- CMD` takes the fix back out and requires the test to notice. That is what makes `git bisect` able to answer, and bisect is how a regression stops being an argument. See [references/commits.md](references/commits.md)
- **A test that passes and fails on the same code gets fixed or quarantined, never retried.** An automatic rerun converts a real race into a green run and teaches everyone to press the button. Prove the instability, then either fix the cause or take the test out of the gate with a dated, visible debt entry naming who is on the hook and when it expires. See [references/flaky.md](references/flaky.md)
- **Three failed fixes mean the model is wrong, not the fix.** No fix before a cause, one hypothesis at a time, and after the third that did not hold, stop and say so with the three that were tried. See [references/debugging.md](references/debugging.md)
- **No compatibility shim for a shape that was never released.** Until the version ships, a rename is a rename: the old name, its callers and its tests go in the same commit. Anything not part of a published contract never earns a shim at all. See [references/no-legacy.md](references/no-legacy.md)
- **Keep a running todo list while you work.** One item per red-green-refactor cycle, one for the falsification pass, one per test you quarantine. It is a small ritual and it is what keeps the second half of a plan from evaporating once the first half goes green

Following the letter of a rule while breaking its point is breaking the rule; the rules are short so the point can be read

## The two modes

Both are the core applied at a different moment; say which one you are in

- **`tdd`** — the code does not exist yet. The loop is red, green, refactor, one behaviour at a time, and the red is watched, not assumed
- **`falsify`** — the code exists and the suite is green. The question is no longer "does it pass" but "would it notice", answered by breaking guards on purpose. This is the mode for inherited code, for a suite whose value is unknown, and for the pass that follows every `tdd` session

## Where the periphery starts

These are choices, and [references/layers.md](references/layers.md) gives the criterion rather than the verdict: how many layers of test to keep and what each can and cannot answer; how much to replace with fakes and what a fake stops proving; whether to keep golden files; what belongs in the gate and what belongs in a suite run by hand. [references/debugging.md](references/debugging.md) is the discipline for a failure whose cause is not yet known, and [references/curation.md](references/curation.md) for a suite that has grown past what it earns. [references/sources.md](references/sources.md) is where every rule's evidence lives

`references/ecosystems/` carries the per-language specifics — the flags that stop a run lying quietly, that language's own shapes of "green that lies", its determinism traps, and what makes a usable defect entry there: [pytest](references/ecosystems/pytest.md) · [shell and bats](references/ecosystems/shell.md) · [go](references/ecosystems/go.md) · [rust](references/ecosystems/rust.md) · [node](references/ecosystems/node.md) · [typescript](references/ecosystems/typescript.md) · [c++](references/ecosystems/cpp.md) · [jvm](references/ecosystems/jvm.md) · [.net](references/ecosystems/dotnet.md) · [php](references/ecosystems/php.md) · [playwright and end-to-end](references/ecosystems/playwright.md)

## The harness

[`t.sh`](t.sh) is the mechanical half of the core, so following it costs less than not: one subcommand per question a test run raises. `t.sh help` is the reference — every subcommand with the question it answers, its flags, the variables and the exit codes — so run `t.sh help [SUB]` before an unfamiliar command rather than guessing one from this page

The command is always explicit, after `--`: a harness that guesses what your suite is runs the wrong thing on the day it matters. A repository's *policy* — which marker sets apply, which lines are excused — can live in `tests/t.conf`, which never carries the command for the same reason. Its own verdicts sit in an exit-code band no test runner uses, 64 to 89, so a suite's own 2 or 4 is never mistaken for one

## Taking the harness into another repository

`t.sh` and `markers/` are what this skill hands to other repositories, and `t.sh` reads its markers from the directory beside it, so the two travel together. They come by the ci skill's vendoring cascade rather than by hand: `vendor-sync.sh add scripts/t.sh rokokol/tests-skill t.sh` and `vendor-sync.sh add scripts/markers/ rokokol/tests-skill markers/` write the copies and their lock lines, and the weekly cascade brings every later fix. A fix to a copy belongs here, where every copy then gets it. What stays the repository's own is written there, not taken: `tests/t.conf` for its policy and `tests/defects.sh` for falsify, starting from `templates/`. The mechanism itself is described once, in the ci skill's [vendored files](https://github.com/rokokol/ci-skill/blob/master/references/bump-cascade.md#vendored-files)

## Layout

```
SKILL.md              this file — the core, the modes, the harness, the checklist
t.sh                  the harness — `t.sh help` for every subcommand, flag, variable and code
markers/              what a lying log says, as data: default.txt always, the rest via -m
references/           one spec per rule, ecosystems/ for the per-language specifics, sources.md for the evidence
templates/            defects.sh for falsify, t.conf for a repository's own policy
check.sh              this repo's own gate, self-tested against known-bad inputs
check-sh.sh           the bash-best-practices skill's checker, holding t.sh's help and the docs to its dispatcher, vendored
tests/fixtures/       lying/ the runs the markers must catch, clean/ the healthy ones they must not
```

CI doctrine — what may gate a pull request, pinning, badges, dependency cascades — is not duplicated here: it lives in the [ci](https://github.com/rokokol/ci-skill) skill. What may go in a commit *message* lives in [ai-commit-trailers](https://github.com/rokokol/ai-commit-trailers-skill)

## Before you say it works

- The command came from the repository's CI or its wrapper, not from a guess — [tdd.md](references/tdd.md)
- The status you acted on is the command's own, and the log was read even at exit 0 — [verdict.md](references/verdict.md)
- The test was seen red before it was seen green, and the commit demonstrates it: `t.sh prove HEAD -- CMD` — [tdd.md](references/tdd.md), [commits.md](references/commits.md)
- At least one defect was tried against the suite, and what survived is in the report, not in your memory — [falsifiability.md](references/falsifiability.md)
- Nothing was weakened, skipped or retried to get here — [flaky.md](references/flaky.md)
- The run you are quoting happened after the last edit — [verdict.md](references/verdict.md)
- The report names the commands, their statuses, and what could not be checked — [verdict.md](references/verdict.md)
