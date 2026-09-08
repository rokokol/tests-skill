# pytest

## Run it so it cannot lie quietly

```sh
t.sh run -- pytest -q --strict-markers --strict-config -W error -p no:randomly
```

- `--strict-markers` / `--strict-config` — a typo in a marker name or an unknown setting is an error rather than a silent no-op. Without them, `@pytest.mark.slwo` simply does nothing and the test runs where you thought it would not
- `-W error` — turns warnings into failures. A `DeprecationWarning` from your own code is a scheduled outage; a suite that prints it forever is not reading it
- `--maxfail` and `-x` are for iterating, never for the gate: the run stops early and the summary describes a fraction of the suite
- `-p no:cacheprovider` in containers, so a stale `.pytest_cache` cannot change collection
- Randomise order in CI (`pytest-randomly`, or `-p no:randomly` pinned with a seed you print) so order dependence fails on the day it is introduced

## Green that lies

The unambiguous two are already in the default set; the noisier ones ship as `markers/pytest.txt`, opted into with `t.sh run -m pytest -- pytest -q`:

| Line | What happened |
|---|---|
| `collected 0 items` | a path, a filter or a rename meant nothing was found |
| `no tests ran in 0.01s` | same, and the exit status may still be 0 with `--exitfirst` |
| `27 skipped` with no expectation | a `skipif` condition became true everywhere |
| `xfailed` growing | tests marked expected-to-fail are a to-do list nobody reads |
| `PytestUnraisableExceptionWarning` | an exception in a destructor or a thread went nowhere |
| `errors` in the summary | collection failed for a file; those tests never ran at all |

`pytest` exits 5 on "no tests collected". Many wrappers coerce that to 0, and CI shows a green tick over a suite that did not exist. `t.sh run` flags the log line regardless

## Fail on nothing ran, natively

pytest exits 5 when nothing was collected, unconditionally: there is no flag to make an empty run pass, and none is needed. What turns that into a lie is a wrapper — a Makefile recipe with `|| true`, a CI step that maps 5 to 0 because "no tests here yet" — so the rule for pytest is the opposite of most runners: never soften the status, and let `t.sh run` read the log for the wrappers you did not write. The same principle for the rest of the run: `--strict-markers` and `--strict-config` make a typo an error instead of a silent no-op, `-W error` makes a warning a failure. Where a runner has such a switch, it is better than a marker; where it has none, the marker is all there is

## Determinism

- `tmp_path` / `tmp_path_factory`, never a hardcoded `/tmp/mytest`
- `monkeypatch` for environment and `cwd`; it undoes itself, `os.environ[...] = ...` does not
- `freezegun` or an injected clock for anything touching `now()`
- `-n auto` (xdist) is where shared state surfaces: a suite that passes serially and fails in parallel has a shared-resource bug, not a parallelism problem
- Fixture scope is the usual culprit — a `session` fixture holding mutable state is shared by every test that asks for it

## For `tests/defects.sh`

Python is forgiving enough that most useful edits stay valid: `if False:` on a guard, a dropped `if` in a filter, `>=` widened to `>`, an early `return None`, a raise turned into a `pass`. Avoid edits that break the import — a `SyntaxError` fails collection, and a suite that failed to collect noticed the parser, not the behaviour. Run with `-b 'python -m compileall -q src'` so that case is reported as `unusable` rather than credited
