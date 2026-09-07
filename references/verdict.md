# The verdict: what a run actually told you

A test run answers a question. Two things routinely stand between the answer and the person reading it, and both are invisible: a pipe that replaces the status, and an output nobody read because the status looked fine.

## The status belongs to the last command in the pipeline

```sh
pytest -q | tail -n 40        # exits 0 when pytest exits 1
go test ./... | grep -v skip  # exits 0 whenever grep matched something
cargo test | tee build.log    # exits 0 unless tee itself failed
```

Every one of these is written to make output readable, and every one of them throws the answer away. In a `Makefile` recipe, a CI `run:` step, a `just` target or an interactive shell, the pipeline's status is the *last* command's, and `tail` always succeeds.

Three fixes, in order of preference:

- **Do not pipe.** Redirect to a file, let the command's own status stand, then read the file. This is what `t.sh run` does, and why it prints the tail only after the verdict is already decided — output printed before a verdict can become the verdict.
- **`${PIPESTATUS[0]}`** — bash, immediately after the pipeline, before any other command runs (including `echo`). Note that this is bash-specific: zsh spells it `$pipestatus` and indexes from 1, and a line copied between the two silently yields an empty string.
- **`set -o pipefail`** — makes the pipeline report the *last* non-zero status in it. Good as a blanket safety net, imprecise as an answer: if the command succeeds and `tee` fails on a full disk, pipefail reports a test failure that did not happen.

The same trap wears other clothes. `cmd &` then `wait` without checking; `$?` read after an intervening `echo`; a `for` loop whose body fails while the loop returns the status of its last iteration; a shell function whose final command is a log line. In each, the status you end up acting on belongs to something other than the thing you ran.

## Exit 0 is a claim, and the log is the evidence

A status of zero means "the process chose to exit zero". These all do:

| What the log says | What it means |
|---|---|
| `collected 0 items`, `no tests ran` | a filter, a rename or a missing file meant nothing ran |
| `no test files`, `running 0 tests` | this target has no tests — fine per package, alarming for the run |
| `1..0` | a TAP producer planned zero tests |
| a traceback in a passing test | an exception was swallowed by a `try` nobody meant as control flow |
| `command not found` inside a suite | a step was skipped, and the suite carried on around it |
| a service that starts, then logs `ERROR` | the process is up; the thing it exists to do is not |
| `--passWithNoTests`, `|| true`, `continue-on-error` | somebody already decided failures do not count |

So a pass has two conditions, not one: the status says so **and** the output agrees. `t.sh run` mechanises exactly that — it greps the log for markers of a run that did not happen and refuses to call such a run a pass, whatever its status.

Choosing markers is the part that needs judgement, so they live as data in `markers/*.txt` rather than inside the harness, and the list is meant to grow as runs teach you new ways of lying quietly.

- **`markers/default.txt`** always applies, and may hold only lines a healthy run never prints. `[no test files]` in a Go workspace and `running 0 tests` in a Rust one appear on perfectly good runs, and a marker that cries wolf gets the whole check switched off within a day — which protects nothing.
- **`markers/<ecosystem>.txt`** holds exactly those noisier lines, opted into per repository with `-m go`, `-m rust`, `-m pytest`, and so on, or with `-m path/to/your-own.txt`.
- **`-p 'text'`** adds a single marker for one run, which is how a new one usually starts life before it earns a place in a file.
- **`T_ALLOW='regex'`** excuses a marker a repository genuinely expects — a negative test asserting a traceback — and the line that excuses it documents the exception where the next reader will find it.

Two rules keep the files honest, and `check.sh` enforces both: every entry in every set must catch a line in that set's fixture, so a dead marker cannot sit there looking like a guard; and every entry in the default set must additionally stay silent on a healthy fixture. A set that resolves to nothing — a missing file, an empty one, a name that does not exist — is a refusal to run, never a quiet pass.

## The repository's own policy

Typing `-m rust -p '...'` on every invocation is how a policy gets forgotten, so a repository can declare it once in `tests/t.conf` ([template](../templates/t.conf)):

```
markers   rust
markers   tests/markers.txt
pattern   thread 'main' panicked
allow     expected: no tests ran
logdir    .test-logs
```

Three properties matter more than the format:

- **It carries policy, never the command.** What runs stays after `--`, in the line you typed. A config that supplied the command would mean a green run whose subject nobody can see without opening a file — and the whole point of this harness is that the verdict and what it is about are both visible.
- **It is read from the current directory only.** No search up the tree: a config found three directories away is a config nobody knew was in effect. `T_CONFIG` points elsewhere, and `T_CONFIG=` turns it off.
- **A broken config refuses rather than being ignored.** An unknown key, a key with no value, a marker set that does not exist — each stops the run and names the line. A typo that is skipped leaves a repository believing in markers that were never loaded, which is worse than having no config at all.

What you pass on the command line adds to it: `-m` and `-p` append, `-l` and `T_ALLOW` override.

## Verification before completion

The rule is not about suites; it is about claims. Before writing that something works, run the thing that would prove it does not and read the whole output.

- A fix is verified by reproducing the original symptom and watching it stop, not by the fix looking correct.
- A test is verified by watching it fail before the code exists — otherwise you have proven only that it passes.
- A build is verified by its own exit status, read directly.
- A program is verified by running it and reading its log, not by its suite being green. A suite tests what someone thought to test; the program does what it does.
- Another agent's report is not evidence. Neither is "this should work", "the change is trivial", or having been careful.

The phrases that reliably precede a false claim — "should be fine", "just this once", "the agent said it passed", "obviously correct" — are worth treating as a signal to go and run the command instead.
