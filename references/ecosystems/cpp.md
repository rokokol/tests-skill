# C++

Two things are different here. The build is a real phase that can fail on its own, and a test can pass while the program has already corrupted its own memory.

## Run it so it cannot lie quietly

```sh
t.sh run -- cmake --build build -j
t.sh run -m cpp -- ctest --test-dir build --output-on-failure
```

- `--output-on-failure` — otherwise ctest prints a table of names and you never see why.
- **Building is its own gated step, not a preamble.** A run whose build quietly used yesterday's binaries answers about yesterday's code, and a build failure folded into the test command reads as a mysterious test failure. Two `t.sh run` invocations keep them apart. (`falsify` and `bisect` take `-b` instead, because there the harness has to tell the two apart without you watching.)
- Warnings as errors on your own targets (`-Wall -Wextra -Werror`), not on vendored ones.
- Sanitizers in a dedicated CI job — `-fsanitize=address,undefined` — because they catch what a passing test cannot: use-after-free, overflow, unaligned access. `ASAN_OPTIONS=detect_leaks=1`, `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`.

## Green that lies

The sanitizer lines are in the default set already; the ctest and gtest ones ship as `markers/cpp.txt`, opted into with `-m cpp`:

| Line | What happened |
|---|---|
| `No tests were found!!!` | ctest found no registered tests and may still exit 0 |
| `Total Test time` with 0 tests | a label or regex filter matched nothing |
| `[  PASSED  ] 0 tests` | gtest ran nothing; a `--gtest_filter` typo does this |
| `runtime error: ...` from UBSan | reported without failing unless `halt_on_error` is set |
| `LeakSanitizer: detected memory leaks` | printed at exit, after the test already passed |
| a test that passes only in Debug | an assertion doing real work inside `assert()`, which `NDEBUG` removes |

That last one deserves care: anything with a side effect inside `assert()` disappears in a release build, so the release binary behaves differently from the one that was tested.

## Fail on nothing ran, natively

ctest has the switch and defaults it off: `ctest --no-tests=error` fails a run that found no tests, and without it the default on the command line is `ignore`, which prints `No tests were found!!!` and exits 0 — the marker in `markers/cpp.txt` is for the runs that never got the flag. It arrived in CMake 3.17, and since 3.26 `CTEST_NO_TESTS_ACTION=error` in the environment does the same for every invocation. The build half has no switch at all: `ninja: no work to do.` and `make: Nothing to be done for 'test'.` both exit 0, which is fine when the binaries are current and a lie when the build was pointed at yesterday's tree, so the test command should always follow the build command in the same job, and a run whose build printed nothing is worth a second look.

## Determinism

- `std::filesystem::temp_directory_path()` plus a unique subdirectory per test, removed afterwards.
- Fix the seed of any RNG and print it on failure.
- Iteration order of `unordered_map` is unspecified and differs between standard libraries; sort before comparing.
- Threads plus `EXPECT_*` from a non-main thread is undefined in gtest — collect results and assert on the main thread.
- Static initialisation order across translation units is unspecified; a test that depends on it passes until the link order changes.

## For `tests/defects.sh`

The compiler rejects most edits, so `unusable` is the common verdict unless the entries are chosen carefully — and running with `-b` is mandatory, or the report will credit the compiler's work to the suite. Edits that stay valid: a comparison widened, a `std::clamp` replaced by its input, an `if (ptr)` guard replaced with `if (true)`, a loop bound reduced by one, `.at()` swapped for `[]`. Prefer edits inside a function body over anything touching a declaration, since a changed signature breaks every call site at once and tells you nothing.
