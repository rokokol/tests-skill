# .NET: dotnet test with xUnit, NUnit or MSTest

## Run it so it cannot lie quietly

```sh
t.sh run -- dotnet build --no-restore -warnaserror
t.sh run -- dotnet test --no-build --settings ci.runsettings
```

- **Two invocations, not one.** `dotnet test` builds first by default, and a compile error then reads as a test failure. Build in its own step, with `-warnaserror` on your own projects, then test with `--no-build` against exactly what was built
- `--no-restore` after one explicit `dotnet restore --locked-mode`: the lock file decides what runs, not the feed's mood that morning
- `--blame-hang-timeout 5m` — a test that hangs is otherwise a job that hangs until the runner kills it, with no name attached
- `-c Release` in CI, because `Debug.Assert` disappears in it: a test that passes only in Debug is asserting inside a call that the release build removes, the same trap as C++'s `assert()`

## Fail on nothing ran, natively

Which runner is underneath decides what "nothing ran" does. With VSTest, the runner behind `dotnet test` for most projects, the only exit codes are 0 and 1, and a run that discovers no tests prints `No test is available in ...` as a warning and exits 0; `<RunConfiguration><TreatNoTestsAsError>true</TreatNoTestsAsError></RunConfiguration>` in the runsettings turns that into a failure. With Microsoft.Testing.Platform, the runner that xUnit v3, NUnit and MSTest can be built on and the default for `dotnet test` from .NET 10, the exit codes mean something — 2 for a failed test, 3 for a session aborted by Ctrl-C, 8 for zero tests under `--zero-tests-policy`, 9 for fewer tests than `--minimum-expected-tests N` — and the second of those is the stronger guard, because it also catches half the suite disappearing. The same platform has the mute button this whole harness exists to fight: `--ignore-exit-code` and `TESTINGPLATFORM_EXITCODE_IGNORE` make any of those a 0, and a run with either in its log is a run whose green means nothing

## Green that lies

| Line | What happened |
|---|---|
| `No test is available in` | VSTest found nothing and, by default, did not mind |
| `Skipped: N` where N grew | `[Fact(Skip = ...)]`, `[Ignore]`, `Assert.Inconclusive` — a to-do list that never turns red |
| `--no-build` after a source change | the tests ran against yesterday's assemblies |
| `warning MSB` in a passing run | the build has something to say; `-warnaserror` makes it say it once, loudly |
| a test green in Debug only | the assertion lives in `Debug.Assert`, which Release removes |

## Determinism

- `Path.GetTempFileName()` or a `Path.Combine(Path.GetTempPath(), Guid)` directory per test, removed in `Dispose`; never a fixed path
- `TimeProvider` (.NET 8+) or an injected clock rather than `DateTime.Now` in the code under test; `Random.Shared` is unseeded by design
- xUnit runs test classes in parallel by default and tests within a class in sequence; a static field shared across classes is where the flakiness lives. `[Collection]` groups what must not run together, and is the wrong fix when the answer is to stop sharing
- Culture: `1.5` parses differently under `de-DE`, and a CI runner's culture is not yours. Set `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` or the culture explicitly

## For `tests/defects.sh`

`-b 'dotnet build --no-restore'` is mandatory, because C# rejects most careless edits and an edit the compiler rejects looks exactly like a defect the tests caught. Edits that stay compilable: `>=` to `>`, `if (x is null)` to `if (false)`, a `throw` replaced by `return default`, a `.Where(...)` dropped, a method body replaced by `return default!`, a `?? fallback` removed. Nullable warnings under `-warnaserror` make some of these `unusable` rather than a measurement

## The marker set

`markers/dotnet.txt`, opted into with `-m dotnet`, carries two lines, both captured from a real `dotnet test` on .NET SDK 8.0.424 with VSTest 17.11.1 that exited 0:

- `No test matches the given testcase filter` — a `--filter` that matched nothing. Not one test ran and the status says success
- `No test is available in` — the assembly held no test the adapter could see: a missing adapter package, a framework mismatch, a project that is not a test project

This is the ecosystem where the idea is clearest. Both are ordinary CI shapes, both exit 0 by default, and a wrapper reading only the status calls each of them a pass. The native switches above turn both into a failure where they are set — `TreatNoTestsAsError` under VSTest covers a run that discovers or selects zero tests, `--minimum-expected-tests` under Microsoft.Testing.Platform — and the marker set is for the runs that never got them
