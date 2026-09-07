# Shell scripts and bats

Shell is where the verdict rules were learned, because it is the one language whose default behaviour is to carry on after a failure and exit 0.

## Run it so it cannot lie quietly

```sh
t.sh run -- bats --print-output-on-failure tests/
t.sh run -- ./tests/run.sh
```

Every script under test, and every harness, opens with:

```sh
set -euo pipefail
```

- `-e` stops at the first failing command — but **not** inside `if`, `while`, `&&`, `||`, or a function whose result is tested, which is where most surprises live.
- `-u` makes an unset variable an error, so a typo'd name is not silently empty. `${VAR:-}` where empty is legitimate.
- `-o pipefail` makes a pipeline report the last non-zero status. Without it, `false | true` succeeds — and so does `pytest | tail`.

`${PIPESTATUS[0]}` is bash, and must be read immediately after the pipeline: any command in between, `echo` included, replaces it. **zsh spells it `$pipestatus` and indexes from 1**, so a line copied from a bash script silently yields an empty string there. Scripts get `#!/usr/bin/env bash`, not `sh`, when they use any of this.

## Green that lies

`1..0`, `command not found` and `segmentation fault` are in the default set; the rest ship as `markers/shell.txt`, opted into with `-m shell`:

| Line | What happened |
|---|---|
| `1..0` | a TAP producer planned zero tests |
| `command not found` | a step was skipped and the script carried on around it |
| `unbound variable` | with `-u` this is a failure; without it, an empty string spread everywhere |
| `: No such file or directory` in a passing run | a path assumption held on one machine only |
| nothing at all | a `for` loop over an empty glob, which succeeds |

Two shapes worth knowing:

- **A `for` loop returns its last iteration's status**, so a loop that fails in the middle and succeeds at the end succeeds. Track failures in a counter and exit on it.
- **`yes | cmd` under `pipefail`** turns `yes`'s normal SIGPIPE death into a pipeline failure. Use `yes 2>/dev/null | cmd` or restructure.

## Determinism and isolation

- `mktemp -d` plus a `trap ... EXIT` for cleanup. Never a fixed path under `/tmp`.
- Stub external tools by putting a directory first on `PATH` — and then **assert that the stub is what resolves** (`command -v tool` equals your stub, and the stub is executable). A stub the script never reaches hands the suite the real tool, and for something like a compositor client or a package manager that means the suite is driving the real system while reporting success.
- Stubs written as `#!/bin/sh`, not `#!/usr/bin/env bash`: a sandbox may have no `/usr/bin`.
- Anything interactive gets a `timeout`, or a prompt style nobody predicted becomes a hanging job rather than a red one.

## For `tests/defects.sh`

Neuter a condition rather than deleting a line: `if [ "$n" -lt 0 ]` becomes `if false`, a `grep -q pattern` becomes `true`, a `tr -d ' '` becomes `cat`. Pair it with `-b 'bash -n script.sh'` so a syntax-breaking edit is reported `unusable` instead of being credited to the suite.
