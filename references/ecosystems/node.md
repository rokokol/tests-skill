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
| `test.skip` / `test.only` committed | `.only` silently reduces the run to one test |

A committed `.only` is worth a lint rule of its own (`eslint-plugin-no-only-tests`, vitest's `--allowOnly=false`): it turns a full suite into one test while every status line still says the run passed

## Fail on nothing ran, natively

The runners here mostly have the switch, and mostly have it the right way round: jest fails when it finds no test files, vitest's `passWithNoTests` is `false` by default, playwright fails unless `--pass-with-no-tests` says otherwise. So the rule is not to add the flag that mutes them. Two traps that are not muting but look like passing:

- **mocha's exit code is the number of failures** unless `--posix-exit-codes` is set, and an exit code is a byte: 256 failures exit 0. cypress does the same. `--posix-exit-codes` gives 0 or 1, and `--fail-zero` fails an empty suite, which mocha otherwise passes
- **jest prints `No tests found, exiting with code 1` even when `--passWithNoTests` has made the real exit code 0.** The line is true about what jest wanted and false about what happened, which makes it a marker of a muted empty run rather than only of a failed one

The `.only` family is the other silent reduction: vitest's `--allowOnly` defaults to the inverse of `CI`, mocha 12 sets `--forbid-only` when `CI` is set, playwright has `--forbid-only` and, separately, `--fail-on-flaky-tests` for a run whose green came from a retry. And a config key nobody validates is a gate that is not there: jest reads `coverageThreshold`, singular, and ignores a misspelt `coverageThresholds` without a word, so the threshold you set is enforced only if you watched it fail once

## Determinism

- `vi.useFakeTimers()` / `jest.useFakeTimers()` for anything with a timeout, and fake the clock rather than sleeping
- `fs.mkdtemp(os.tmpdir())` per test, cleaned in `afterEach`
- Reset module state between tests (`vi.resetModules()`); an ES module's top-level state persists for the whole worker
- Unhandled promise rejections can pass silently in older setups — fail the run on them
- The default is multi-process: a test writing to a fixed port, a fixed database name or a shared file will pass alone and fail in the suite

## For `tests/defects.sh`

JavaScript accepts almost any edit, which is convenient here: a `filter(...)` dropped, a `===` widened to `==`, a guard's body replaced with `return true`, an `await` removed to turn a resolved value into a promise. TypeScript sources need `-b 'npx tsc --noEmit'` so an edit the type checker rejects is reported `unusable` — see [typescript.md](typescript.md)
