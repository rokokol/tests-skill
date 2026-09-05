# The verdict: what a run actually told you

A test run answers a question. Two things routinely stand between the answer and the
person reading it, and both are invisible: a pipe that replaces the status, and an output
nobody read because the status looked fine.

## The status belongs to the last command in the pipeline

```sh
pytest -q | tail -n 40        # exits 0 when pytest exits 1
go test ./... | grep -v skip  # exits 0 whenever grep matched something
cargo test | tee build.log    # exits 0 unless tee itself failed
```

Every one of these is written to make output readable, and every one of them throws the
answer away. In a `Makefile` recipe, a CI `run:` step, a `just` target or an interactive
shell, the pipeline's status is the *last* command's, and `tail` always succeeds.

Three fixes, in order of preference:

- **Do not pipe.** Redirect to a file, let the command's own status stand, then read the
  file. This is what `t.sh run` does, and why it prints the tail only after the verdict is
  already decided — output printed before a verdict can become the verdict.
- **`${PIPESTATUS[0]}`** — bash, immediately after the pipeline, before any other command
  runs (including `echo`). Note that this is bash-specific: zsh spells it `$pipestatus` and
  indexes from 1, and a line copied between the two silently yields an empty string.
- **`set -o pipefail`** — makes the pipeline report the *last* non-zero status in it. Good
  as a blanket safety net, imprecise as an answer: if the command succeeds and `tee` fails
  on a full disk, pipefail reports a test failure that did not happen.

The same trap wears other clothes. `cmd &` then `wait` without checking; `$?` read after an
intervening `echo`; a `for` loop whose body fails while the loop returns the status of its
last iteration; a shell function whose final command is a log line. In each, the status you
end up acting on belongs to something other than the thing you ran.

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

So a pass has two conditions, not one: the status says so **and** the output agrees.
`t.sh run` mechanises exactly that — it greps the log for markers of a run that did not
happen and refuses to call such a run a pass, whatever its status.

Choosing markers is the part that needs judgement. A marker that fires on healthy runs
gets the whole check switched off within a day, which protects nothing: `[no test files]`
in a Go workspace and `running 0 tests` in a Rust one are printed by perfectly good runs,
so they belong in a per-repo `-p` rather than in a default. Conversely `T_ALLOW` excuses a
marker a repository genuinely expects — a negative test asserting a traceback — and the
line that excuses it documents the exception where the next reader will find it.

## Verification before completion

The rule is not about suites; it is about claims. Before writing that something works, run
the thing that would prove it does not and read the whole output.

- A fix is verified by reproducing the original symptom and watching it stop, not by the
  fix looking correct.
- A test is verified by watching it fail before the code exists — otherwise you have
  proven only that it passes.
- A build is verified by its own exit status, read directly.
- A program is verified by running it and reading its log, not by its suite being green.
  A suite tests what someone thought to test; the program does what it does.
- Another agent's report is not evidence. Neither is "this should work", "the change is
  trivial", or having been careful.

The phrases that reliably precede a false claim — "should be fine", "just this once", "the
agent said it passed", "obviously correct" — are worth treating as a signal to go and run
the command instead.
