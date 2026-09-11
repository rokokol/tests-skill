# Shell scripts and bats

Shell is where the verdict rules were learned, because it is the one language whose default behaviour is to carry on after a failure and exit 0

## Run it so it cannot lie quietly

```sh
t.sh run -- bats --print-output-on-failure tests/
t.sh run -- ./tests/run.sh
```

Every script under test, and every harness, opens with `set -euo pipefail`. What each flag does, where `-e` does not fire, how `PIPESTATUS` is read before the next command replaces it, why zsh's `$pipestatus` is not the same thing, and why the shebang is `#!/usr/bin/env bash` rather than `sh` are the [bash-best-practices](https://github.com/rokokol/bash-best-practices-skill) skill's, in its `references/shape.md` and `references/harness.md`; what follows is what testing shell adds

## Green that lies

`1..0`, `command not found` and `segmentation fault` are in the default set; the rest ship as `markers/shell.txt`, opted into with `-m shell`:

| Line | What happened |
|---|---|
| `1..0` | a TAP producer planned zero tests |
| `command not found` | a step was skipped and the script carried on around it |
| `unbound variable` | with `-u` this is a failure; without it, an empty string spread everywhere |
| `: No such file or directory` in a passing run | a path assumption held on one machine only |
| nothing at all | a `for` loop over an empty glob, which succeeds |

Two shapes that make a suite lie — a `for` loop returning only its last iteration's status, and `yes | cmd` failing under `pipefail` on `yes`'s ordinary SIGPIPE death — are language rules rather than testing ones, and live in the bash-best-practices skill's `references/shape.md`

## Fail on nothing ran, natively

bats has it the right way round: a suite with no tests exits 1 unless `--allow-empty-suite` says otherwise, so the rule is not to pass that flag; the `1..0` marker in the default set is for the TAP producers that do not. One bats behaviour interacts with this harness: in focus mode — a `# bats:focus` tag — a successful run's exit code is **forced to 1** so a focused run cannot be mistaken for a full one, and `BATS_NO_FAIL_FOCUS_RUN=1` disables that, which bats documents as the setting for `git bisect`. Under `t.sh bisect`, a focused suite without it marks every commit bad

## Determinism and isolation

- One `mktemp -d` with a template plus a `trap … EXIT` for cleanup, never a fixed path under `/tmp` — the spelling is the bash-best-practices skill's, in `references/shape.md`
- Stub external tools by putting a directory first on `PATH` — and then **assert that the stub is what resolves** (`command -v tool` equals your stub, and the stub is executable). A stub the script never reaches hands the suite the real tool, and for something like a compositor client or a package manager that means the suite is driving the real system while reporting success
- Stubs written as `#!/bin/sh`, not `#!/usr/bin/env bash`: a sandbox may have no `/usr/bin`
- Anything interactive gets a `timeout`, or a prompt style nobody predicted becomes a hanging job rather than a red one

## For `tests/defects.sh`

Neuter a condition rather than deleting a line: `if [ "$n" -lt 0 ]` becomes `if false`, a `grep -q pattern` becomes `true`, a `tr -d ' '` becomes `cat`. Pair it with `-b 'bash -n script.sh'` so a syntax-breaking edit is reported `unusable` instead of being credited to the suite
