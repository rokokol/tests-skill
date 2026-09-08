# A test that disagrees with itself

An unstable test is one that passes and fails on the same code. It is worse than a missing test, because it teaches everyone that red means "press the button again" — and once that habit exists, a genuine failure gets rerun too. The largest suites measured keep the share of unstable tests near a sixth of a percent and find that somewhere around one percent the suite stops being believed; a repository has less headroom than that, not more

## Prove it before you chase it

One red run is not evidence of instability; it may be a real bug that only your machine's timing exposes. The evidence is **both outcomes on the same code**: `t.sh flaky 20 -- <cmd>` runs the same command twenty times and reports how many runs disagreed with the first, pointing at the first divergent log. It keeps no history and computes no statistics — it exists to turn "it failed once, probably nothing" into a fact, so the cause can be found. The marker sets and patterns `run` takes apply to every one of the runs:

```sh
t.sh flaky 20 -m rust -- cargo test --workspace --no-fail-fast
```

Two bars, in opposite directions. To call a test unstable, the runs must disagree at least once; a test that failed once and agreed with itself twenty times afterwards was a real failure on a real condition that has since changed, and that is a different investigation. To call it fixed, fifty runs must agree under the conditions that used to break it — the parallelism, the load, the order — because a fix verified by three quiet runs on a quiet laptop is the same guess with a smaller sample

If twenty runs agree, the instability is elsewhere: in the CI machine's load, in the order the suite happens to run in, in a neighbouring test's leftovers. Reproduce it there — the same order (`pytest -p randomly --randomly-seed=last`, `go test -shuffle=<seed>`, `vitest --sequence.seed`), a single worker, the same container — rather than concluding the test is fine. And a failure caused by the runner and not the test — a backend that did not come up, a browser that took forty seconds to open a blank page — is classified out before it is counted: a cheap health probe first, and a machine that fails it is a machine, not a flake

## Classify it, because the fix depends on the cause

| Category | What it looks like | The fix, in one line |
|---|---|---|
| **timing** | `sleep 0.5` then assert; passes until the machine is loaded | wait for the condition — the file, the port, the log line, the state — with a deadline that fails loudly |
| **shared state** | the same temporary directory, database row, fixed port, environment variable, module-level cache; passes alone, fails in parallel | give each test its own, and let the framework allocate the port |
| **order** | one test leaves state another happens to need; passes in one order, fails in another | randomise the order in CI so it fails on the day it is introduced; bisect the order to find the polluter |
| **time and dates** | `now()`, timezones, midnight, the last week of a month, a timeout tuned to one machine | inject the clock; a fixed timezone in CI |
| **unordered as ordered** | dictionary iteration, set serialisation, filesystem listing, concurrent log lines | sort before comparing, or compare as sets |
| **external** | a name resolved, a URL fetched, a package mirror | not a test to fix but a test to move: it belongs outside the gate |
| **the code itself** | a genuine race in the code under test | the most valuable finding; the test is right, and an automatic retry hides exactly this one |

The categories matter because the fix for one is wrong for another: a longer timeout does nothing for a polluted order, a sorted comparison does nothing for a race. A test that cannot be placed in the table has not been diagnosed yet

Waiting for a condition is the fix for the first row and most of the second, and it is one small helper, not a discipline: `wait_for(condition, description, timeout)` polls every ten milliseconds or so, calls the getter inside the loop rather than once before it, and fails with the description and the last observed state when the timeout expires. A bare sleep is defensible in one place only — when the thing waited for has no observable condition at all — and then the comment beside it says why, in terms of the system's known behaviour, so the next reader does not double it

The order of setup matters more than it looks: a fake clock installed after the page or the module loaded misses the timers they already set; a network stub that lets an unstubbed request through gives a green run against the real world. Fake timers before the clock is set, the stub before the navigation, and unhandled requests as errors, not pass-throughs

## The policy

**Never auto-retry inside the gate.** `--reruns`, `retries: 2`, `nextest --retries`, `jest.retryTimes`, a `for` loop around the suite: each converts a real race into a green run. A gate whose green is produced by repetition answers a question nobody asked. Where retries exist for reasons outside the gate, the tool's own switch keeps the verdict honest — Playwright's `--fail-on-flaky-tests`, nextest's `--flaky-result fail`, without which a test that passed on retry is counted as a pass

When a test is unstable and cannot be fixed today:

1. **Take it out of the gate explicitly** — mark it, move it to a job that runs and does not block — so the gate goes back to meaning something. `skip` is not quarantine: a skipped test is dead code that still reads as coverage, while a quarantined one keeps running where its result is visible
2. **Record the debt where it is visible**: a row in the repository's quarantine file naming the test, the date, the category above, what is suspected, who is on the hook and when it expires — see [curation.md](curation.md) for the file. A quarantine with no name and no date is a deletion that still costs CI minutes
3. **Give it a deadline, and a short one.** Two weeks is the usual; a row past its expiry is a decision that was not made, and a gate can refuse it. A test quarantined for a year should be deleted, and the deletion noted — an honest gap is better than a comforting one
4. **Watch the size of the file.** More than a few percent of the suite in quarantine is not a list of unstable tests; it is a suite whose infrastructure is unstable, and the fix is there

Deleting an unstable test is a legitimate outcome, provided it is deliberate and the test was not the only thing seeing a race in the code. What is not legitimate is leaving it in the gate while everyone silently reruns

## The one place a retry is defensible

A check whose subject is genuinely outside the repository — a package mirror, a CDN, a live site — may retry, because its failures are about someone else's afternoon. But such a check should not have been gating a pull request in the first place; it belongs to the weekly drift detector. That split is the [ci](https://github.com/rokokol/ci-skill) skill's gate-versus-detector rule, and it is the real fix for most "flaky CI". The evidence for the numbers above is in [sources.md](sources.md)
