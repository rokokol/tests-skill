# Go

## Run it so it cannot lie quietly

```sh
t.sh run -- go test ./... -count=1 -race -shuffle=on
```

- `-count=1` — the only supported way to defeat the test cache. Without it a "passing" run
  may have executed nothing, printing `(cached)` beside each package.
- `-race` — Go's race detector is cheap enough to leave on in CI and finds the class of bug
  that otherwise appears as an unstable test.
- `-shuffle=on` — randomises order within a package, so a test depending on a neighbour's
  leftovers fails immediately rather than eventually.
- `go vet ./...` runs as part of `go test`, but only a subset; run it separately for the rest.

## Green that lies

| Line | What happened |
|---|---|
| `? pkg [no test files]` | normal per package — alarming if it is *every* package |
| `ok pkg 0.001s [no tests to run]` | `-run` matched nothing; a typo in the regex reads as success |
| `(cached)` | nothing executed; you are reading an old verdict |
| `panic:` in a passing run | a goroutine panicked after the test returned |
| `DATA RACE` without `-race` failing | the detector reports but the build must be run with `-race` to fail |
| `testing.Short()` branches | `-short` in CI quietly skips the expensive half |

`[no test files]` and `[no tests to run]` are the reason those markers are **not** in
`t.sh`'s default table: in any real module most packages have no tests, and a default that
fires on them would be switched off on day one. They ship as an opt-in set instead —
`t.sh run -m go -- go test ./... -count=1` — worth adopting once the repository expects
tests everywhere; before that, grep for the count of `ok ` lines instead. `markers/go.txt`
also carries `(cached)`, `[build failed]` and `[setup failed]`.

## Determinism

- `t.TempDir()` and `t.Setenv()` — both undo themselves; a manual `os.Setenv` leaks into
  every later test in the binary.
- `t.Cleanup()` rather than `defer` in helpers, so cleanup survives a `t.Fatal`.
- Port `0` and read back the assigned address; a hardcoded port fails under `-p` parallelism.
- `t.Parallel()` is where shared state surfaces. Adding it to an existing test and watching
  it fail is a finding, not a regression.
- A `time.Sleep` waiting for a goroutine is the standard flake; wait on a channel or poll
  a condition with a deadline that fails loudly.

## For `tests/defects.sh`

Go's compiler rejects most careless edits, which makes the `unusable` verdict essential —
always run falsify with `-b 'go build ./...'`. Edits that stay valid: a comparison widened
(`>=` to `>`), an `if err != nil` body replaced with a bare `return nil`, a bounds check
turned into `if false`, a filter condition inverted to `true`. Beware edits that leave a
variable unused: Go treats that as a compile error, so it becomes `unusable` rather than a
measurement.
