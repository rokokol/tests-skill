# Node: vitest, jest, node:test

## Run it so it cannot lie quietly

```sh
t.sh run -- npx vitest run --passWithNoTests=false
t.sh run -- npx jest --ci --passWithNoTests=false --detectOpenHandles
t.sh run -- node --test
```

- **`--passWithNoTests=false`** is the single most important flag here. Many templates and monorepo scripts set the opposite so that a package without tests does not break the build — and from then on, a broken glob or a renamed directory is a green run
- `vitest run`, not `vitest`: the bare command starts watch mode, which in CI either hangs until the job times out or exits 0 having run nothing
- `--ci` (jest) stops it writing new snapshots on the fly. Without it, a changed output quietly becomes the new expectation
- Install with `npm ci`, never `npm install`, so the lockfile decides what runs

## Green that lies

These ship as `markers/node.txt`, opted into with `t.sh run -m node -- npx vitest run`:

| Line | What happened |
|---|---|
| `No test files found, exiting with code 0` | the glob matched nothing and someone allowed it |
| `Tests: 0 total` | same, from jest |
| `1 snapshot written` in CI | the expectation was regenerated, not checked |
| `Test suite failed to run` | the file never executed; its tests are absent, not passing |
| `A worker process has failed to exit gracefully` | something is still running; state leaks into the next run |
| `Jest did not exit one second after` | a handle nobody closed; the run does not end, and in CI that is the job timeout |
| `obsolete,` | a stored expectation nothing compares against any more, from the `Snapshots:` totals line |

A committed `.only` is not among them, and cannot be: see [below](#a-forgotten-only-is-not-in-the-log)

## Fail on nothing ran, natively

The runners here mostly have the switch, and mostly have it the right way round: jest fails when it finds no test files, vitest's `passWithNoTests` is `false` by default, playwright fails unless `--pass-with-no-tests` says otherwise. So the rule is not to add the flag that mutes them. Two traps that are not muting but look like passing:

- **mocha's exit code is the number of failures** unless `--posix-exit-codes` is set, and an exit code is a byte: 256 failures exit 0. cypress does the same. `--posix-exit-codes` gives 0 or 1, and `--fail-zero` fails an empty suite, which mocha otherwise passes
- **jest names the code it is about to exit with, and on 30.5.0 it names the right one.** `--passWithNoTests` gives `No tests found, exiting with code 0` and an exit of 0; without it, code 1 and an exit of 1. The sentence tells you which of the two happened, so a log carrying `exiting with code 0` is a run that found nothing and was told not to mind

The `.only` family is the other silent reduction: vitest's `--allowOnly` defaults to the inverse of `CI`, mocha 12 sets `--forbid-only` when `CI` is set, playwright has `--forbid-only` and, separately, `--fail-on-flaky-tests` for a run whose green came from a retry. And a config key nobody validates is a gate that is not there: jest reads `coverageThreshold`, singular, and ignores a misspelt `coverageThresholds` without a word, so the threshold you set is enforced only if you watched it fail once

## Determinism

- `vi.useFakeTimers()` / `jest.useFakeTimers()` for anything with a timeout, and fake the clock rather than sleeping
- `fs.mkdtemp(os.tmpdir())` per test, cleaned in `afterEach`
- Reset module state between tests (`vi.resetModules()`); an ES module's top-level state persists for the whole worker
- Unhandled promise rejections can pass silently in older setups — fail the run on them
- The default is multi-process: a test writing to a fixed port, a fixed database name or a shared file will pass alone and fail in the suite

## A forgotten `.only` is not in the log

`test.only`, `it.only` and `describe.only` run one test and skip the rest of the file. They are the right tool while you are chasing one failure among fifty, and the whole problem is that they survive a commit: CI then runs the one, prints `Tests: 1 passed | 2 skipped (3)`, exits 0, and the suite has stopped running while the build stays green

No runner says so. Measured on jest 30 and vitest 3: neither prints the words `test.only` anywhere, and the only trace is a skip count that a suite skipping a test for a missing browser produces just as readily. `markers/node.txt` carried those three strings for a while, and they could not have matched anything a runner wrote

The guard is the configuration:

- **vitest**: `allowOnly: false`, or `--allowOnly=false`, which turns it into `[Vitest] Unexpected .only modifier` and exit 1
- **playwright**: `forbidOnly: true`
- **jest**: nothing built in; the standard answer is eslint with `jest/no-focused-tests`

This is one of a family, and the family is worth recognising by shape rather than by name. `.only`, `--pass-with-no-tests`, `--passWithNoTests`, `-DskipTests`, `-x`: each was added for an honest local reason, each turns a CI run into a lie when it outlives the commit that needed it, and not one of them is visible in a log — the runner either says nothing or says exactly what it says for the legitimate case. A marker cannot reach any of them. The switch that forbids it can, and `t.sh focused` finds the ones that live in the source

## For `tests/defects.sh`

JavaScript accepts almost any edit, which is convenient here: a `filter(...)` dropped, a `===` widened to `==`, a guard's body replaced with `return true`, an `await` removed to turn a resolved value into a promise. TypeScript sources need `-b 'npx tsc --noEmit'` so an edit the type checker rejects is reported `unusable` — see [typescript.md](typescript.md)
