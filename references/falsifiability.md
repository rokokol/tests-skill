# Proving a check can fail

A check that has never been red is a decoration: nobody knows whether it guards anything, and it will keep being green after the thing it watches stops working. The discipline is the same wherever a check is born.

- **Red first.** A new check runs against the pre-fix state, or against a deliberately broken input, and is watched failing — *then* the code that turns it green lands. When a check is adopted into a repository that already violates it, that first red run on the real violation is the proof; only then align the state.
- **Checkers ship self-tests.** A gate that lints, greps or compares runs itself against known-bad fixtures and exits non-zero unless those fixtures fail. This repository's [`check.sh`](../check.sh) does exactly that with itself, and every one of its steps was watched failing before it was trusted.
- **Extractors refuse to find nothing.** Any check that parses a list out of a file — markers, flags, subcommand names — must fail loudly when it extracts zero items. A loop over an empty list passes silently, which is indistinguishable from "no problems found".
- **Whole-line assertions on generated text.** `grep -qxF`, not a substring match: two similar outputs make a substring check pass for the wrong one, and it will be the wrong one exactly when it matters.
- **Un-mute before diagnosing.** When one environment fails where the rest pass, the first move is removing the `2>/dev/null`. An older tool rejecting newer syntax disappears into muted stderr and presents as "empty output".
- **Probe the mechanism, not a proxy.** A check must measure the thing the code actually depends on. Asking one tool whether a feature works, when a different tool does the work downstream, holds until the two disagree — and then it answers for the wrong one.
- **A check must not share the blind spot of what it checks.** Comparing `$(cat file)` with `$(cat file)` cannot see a lost trailing newline, because command substitution strips it from both sides. Compare bytes with `cmp`, or ask `git diff`, which has no opinion about what a line is.
- **A refusal must run where it can actually refuse.** In shell, `exit` inside a `$(...)`, a `( )` or a pipeline stage ends the subshell, and the caller carries on with an empty string. A guard written there does not guard: it prints to stderr and is ignored. Validate before the substitution, in the shell that can still stop.

## Falsifying a suite: `t.sh falsify`

A green suite says the code passes. Whether it would fail if the code stopped working is a separate question, and it is answered mechanically: break one guard on purpose, rerun the suite, and see whether it notices.

`t.sh falsify` reads [`tests/defects.sh`](../templates/defects.sh) — a plain bash file calling `defect NAME FILE FIND REPLACE CONSEQUENCE`, one entry per guard, written by hand. **Nothing is generated.** Tools that invent mutants mostly produce code that will not compile, and a compiler error is not a test noticing anything; the useful knowledge here is what each guard is *for*, and only a person has it.

Four verdicts, and the distinctions between them are the whole point:

- **`caught`** — the suite went red. That guard is genuinely covered.
- **`SURVIVED`** — the suite stayed green with the guard broken, and the entry's consequence sentence is printed. That sentence, in operator's terms, names what nobody checks. It is the output worth reading.
- **`stale`** — the find text no longer matches exactly once in the file. Not guessed at, not silently skipped: a defect list that has drifted from its code stops testing what it was written for, and this is how it says so.
- **`unusable`** — the edit stopped the code building, so the tests were never asked. This is the verdict that keeps the report honest in compiled languages: without it, every syntax-breaking edit would be credited as `caught` and the suite would appear to cover code nothing touches.

The safety properties that make it something you can run on a Friday:

- **Build and test are separate phases** (`-b`), which is what makes `unusable` reachable at all.
- **A suite already red aborts the run.** Falsification measures the distance between green and red; starting red there is no distance, and every `caught` would be an artefact. A suite that "passes" while its log says nothing ran is refused for the same reason.
- **The working tree must be clean.** This command edits your source on purpose, and on a dirty tree an interrupted restore is indistinguishable from your own edits.
- **The original is held in memory and written back in a trap** covering interrupt and termination, then compared byte for byte. Restoring from memory rather than from git means an interrupted run cannot leave a mutated tree even if git is unavailable.

## Writing the defect list

Write one entry as each guard is written, and it doubles as prose documentation of what the guard is for. Two rules make the entries useful:

- **Neuter, do not break.** `if False:`, a dropped filter, a widened comparison, a constant return. Edits that keep the code valid and change what it does are the ones that ask about behaviour. An edit that breaks syntax asks about the parser.
- **Write the consequence in the operator's words** — "something that did not answer reads as healthy and quiet", not "the unreachable branch is skipped". When the suite survives, that sentence is the finding, and it should be legible to whoever would have been paged.

**Copying a defect list proves nothing.** The mechanism travels; the knowledge does not. A falsifier that has only ever printed `caught` may simply be matching nothing — run it, watch something survive, and only then believe the green.
