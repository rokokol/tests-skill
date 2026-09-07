---
name: tests
description: "What it is — a standard for tests that mean something when they are green: a verdict no pipe can swallow, logs read even at exit 0, every check watched failing before it is trusted, test-first with a falsification pass behind it, commits granular enough to bisect, and no compatibility shims for a shape that was never released. Use when writing or reviewing tests, running a suite, judging whether a green run proves anything, chasing a regression to the commit that caused it, deciding what to do about a test that passes and fails on the same code, or setting up testing in a new repo. Triggers: tests, test suite, coverage, TDD, flaky, mock, fixture, golden file, bisect, regression, напиши тест, покрытие, тесты падают, зелёный прогон, нестабильный тест, найти коммит."
license: MIT
---

# tests

A suite tells you the code passed. It does not tell you the suite would have noticed if the code had stopped working — and that second question is the only one a green run is worth anything for. Everything here serves it: a verdict that cannot be swallowed by a pipe, a log that gets read even when the status says success, a check watched failing before anyone trusts it, and a history granular enough to ask *which commit* later.

The core below is not negotiable, because each rule is true in every language and every repository. Everything past it — how many layers of test to keep, how much to mock, how big a step to take — is a real choice with a real cost, and this skill states the cost rather than the answer. [`t.sh`](t.sh) beside this file is the operational half.

## The core

- **The status you act on is the command's own.** `cmd | tail -n 40` exits 0 for a suite that just failed, because the status belongs to `tail`; so does `| tee`, `| grep`, and every pipeline whose shell has no `pipefail`. Capture `${PIPESTATUS[0]}`, or run the command and read the log afterwards. Never let a summarising pipe stand between a run and its verdict. See [references/verdict.md](references/verdict.md).
- **Exit 0 is not a synonym for success — read the log.** `collected 0 items`, `no tests ran`, a traceback logged by a test that still passed, a service that started cleanly and then filled its own log with errors: all of these exit 0. A run is a pass when its status says so *and* its output agrees. See [references/verdict.md](references/verdict.md).
- **Nothing is done until it has been run and watched.** Before saying a thing works, execute the command that would prove it wrong and read the whole output. "Should work", "the change is trivial", and a subagent's report are not evidence. This applies to the real program as much as to its suite: start it, drive it, read its log.
- **Test first, then prove the test can fail.** Write the test before the code, watch it fail for the reason you intended, then make it pass — and afterwards, separately, break the code on purpose and require the suite to notice. The first half stops you writing a test that only describes what the code already does; the second catches the test that passes no matter what. A check that has never been red is a decoration. See [references/tdd.md](references/tdd.md) and [references/falsifiability.md](references/falsifiability.md).
- **One logical change per commit, each commit standing on its own.** The failing test is its own commit, the fix is the next one, and every commit in between builds and passes. That is what makes `git bisect` able to answer, and bisect is how a regression stops being an argument. See [references/commits.md](references/commits.md).
- **A test that passes and fails on the same code gets fixed or quarantined, never retried.** An automatic rerun converts a real race into a green run and teaches everyone to press the button. Prove the instability, then either fix the cause or take the test out of the gate with a dated, visible debt entry naming who is on the hook. See [references/flaky.md](references/flaky.md).
- **No compatibility shim for a shape that was never released.** Until the version ships, a rename is a rename: the old name, its callers and its tests go in the same commit. Anything not part of a published contract never earns a shim at all. See [references/no-legacy.md](references/no-legacy.md).
- **Keep a running todo list while you work.** One item per red-green-refactor cycle, one for the falsification pass, one per test you quarantine. It is a small ritual and it is what keeps the second half of a plan from evaporating once the first half goes green.

## The two modes

Both are the core applied at a different moment; say which one you are in.

- **`tdd`** — the code does not exist yet. The loop is red, green, refactor, one behaviour at a time, and the red is watched, not assumed.
- **`falsify`** — the code exists and the suite is green. The question is no longer "does it pass" but "would it notice", answered by breaking guards on purpose. This is the mode for inherited code, for a suite whose value is unknown, and for the pass that follows every `tdd` session.

## Where the periphery starts

These are choices, and [references/layers.md](references/layers.md) gives the criterion rather than the verdict: how many layers of test to keep and what each can and cannot answer; how much to replace with fakes and what a fake stops proving; whether to keep golden files; what belongs in the gate and what belongs in a suite run by hand. [references/debugging.md](references/debugging.md) is the discipline for a failure whose cause is not yet known, and [references/curation.md](references/curation.md) for a suite that has grown past what it earns. [references/sources.md](references/sources.md) is where every rule's evidence lives.

`references/ecosystems/` carries the per-language specifics — the flags that stop a run lying quietly, that language's own shapes of "green that lies", its determinism traps, and what makes a usable defect entry there: [pytest](references/ecosystems/pytest.md) · [shell and bats](references/ecosystems/shell.md) · [go](references/ecosystems/go.md) · [rust](references/ecosystems/rust.md) · [node](references/ecosystems/node.md) · [typescript](references/ecosystems/typescript.md) · [c++](references/ecosystems/cpp.md) · [jvm](references/ecosystems/jvm.md) · [.net](references/ecosystems/dotnet.md) · [php](references/ecosystems/php.md) · [playwright and end-to-end](references/ecosystems/playwright.md)

## The harness

[`t.sh`](t.sh) is the mechanical half of the core, so following it costs less than not:

| Command | What it answers |
|---|---|
| `t.sh run -- CMD` | did it pass — status kept honest, whole log kept, log read even at 0 |
| `t.sh flaky N -- CMD` | do repeated runs of the same code disagree |
| `t.sh bisect GOOD -- CMD` | which commit broke it, skipping the ones that cannot answer |
| `t.sh falsify -- CMD` | which guards the suite would not notice being broken |

The command is always explicit, after `--`: a harness that guesses what your suite is runs the wrong thing on the day it matters. A repository's *policy* — which marker sets apply, which lines are excused — can live in `tests/t.conf`, which never carries the command for the same reason. `t.sh --help` carries the flags.

## Layout

```
SKILL.md              this file — the core, the modes, the harness
t.sh                  run / flaky / bisect / falsify
markers/              what a lying log says, as data: default.txt always, the rest via -m
references/           one spec per rule, plus ecosystems/ for the per-language specifics
templates/            defects.sh for falsify, t.conf for a repository's own policy
check.sh              this repo's own gate, self-tested against known-bad inputs
tests/fixtures/       the known-bad inputs those checks are proven to catch
```

CI doctrine — what may gate a pull request, pinning, badges, dependency cascades — is not duplicated here: it lives in the [ci](https://github.com/rokokol/ci-skill) skill. What may go in a commit *message* lives in [ai-commit-trailers](https://github.com/rokokol/ai-commit-trailers-skill).
