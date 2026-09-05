# Rust

## Run it so it cannot lie quietly

```sh
t.sh run -b 'cargo build --workspace --all-targets' -- cargo test --workspace --no-fail-fast
```

- `--workspace` — without it, `cargo test` in a workspace root may test one member and
  report success for the whole thing.
- `--no-fail-fast` — otherwise the first failing target stops the run and the summary
  describes a fraction of it.
- `cargo clippy --workspace --all-targets -- -D warnings` and `cargo fmt --check` as
  separate steps; `--all-targets` is what makes clippy look at the tests too, which is
  where the sloppiest code usually is.
- Pin the toolchain in `rust-toolchain.toml`. An unpinned toolchain changes a run's
  behaviour with zero change in the repository.

## Green that lies

| Line | What happened |
|---|---|
| `running 0 tests` | normal per target — a filter that matches nothing prints only this |
| `test result: ok. 0 passed; 0 filtered out` | the run was empty and exited 0 |
| `warning: unused ...` | often the visible half of a `#[cfg(...)]` that removed real code |
| `Doc-tests` absent | doc tests do not run under `cargo nextest`; they are a separate step |
| `#[ignore]` accumulating | a to-do list that never turns red |
| a panic in a spawned thread | the thread dies, the test may still pass |

`running 0 tests` is printed for every target without tests — doc-test targets and empty
integration targets included — so it is not in `t.sh`'s default table. Add it with `-p`
only in a crate where every target really is expected to have tests.

## Determinism

- `tempfile::TempDir` for filesystem work; it removes itself on drop.
- Inject the clock and the RNG rather than calling `SystemTime::now()` or `thread_rng()`
  in the code under test. Seed anything random and print the seed on failure.
- `cargo test` runs tests in parallel threads by default, so anything touching a process
  global — environment variables, the current directory, a `static mut`, a global logger —
  is shared. `std::env::set_var` is the classic: it affects the whole test binary.
  `--test-threads=1` hides the bug rather than fixing it.
- `assert_eq!` on a `HashMap` iteration order will pass locally and fail elsewhere; compare
  as sets or sort first.

## Hardware, GPUs and other things CI does not have

Define a trait for the boundary — audio input, inference backend, clipboard, hotkeys — with
the real implementation in the binary crate and a fake in the tests. Prefer this over
`#[cfg(feature = ...)]`: feature flags multiply the build matrix, and the combination
nobody tested is the one that ships. The real device then needs exactly one
environment-layer test, run by hand before a release.

## For `tests/defects.sh`

Always pass `-b 'cargo build --workspace --all-targets'`: without the build phase, an edit
the compiler rejects is indistinguishable from a defect the tests caught, and the report
would credit coverage that does not exist. Edits that stay compilable: a `?` replaced with
`.unwrap_or_default()`, a `match` arm's body swapped for the other arm's value, a bound
widened, a `filter(...)` dropped, a `saturating_sub` turned into `-`. Watch for edits that
leave an unused variable or an unreachable pattern — with `-D warnings` those become
`unusable`.
