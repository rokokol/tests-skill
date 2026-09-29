# Pitfalls

Traps found while working on this repository, kept so the next person editing it does not pay for them twice. Nothing in `SKILL.md` or `references/` links here on purpose: this is a maintainer's note about the gate and the harness themselves, not part of the standard they describe. Permanent choices the gate makes against the obvious route are in `DEVIATIONS.md`

---

## Backgrounding the gate needs `set -m`, or its signal probes report nothing

**Where it bites:** `check_behaviour` in `check.sh`, which asserts what `bisect-probe` makes of a command killed by a signal, `probe 130 "is interrupted by the user" -- sh -c 'kill -INT $$'` among them; `run_rows` brackets the batch in `set -m`

**Reproduction:** sixteen copies started with a plain `&` failed identically on that line; the same sixteen under `set -m` were all clean

**Misleading result:** the failure at least announces itself; the danger is reading it as a load problem and relaxing the check

**Mechanism:** a background job of a non-interactive shell starts with `SIGINT` and `SIGQUIT` ignored, and everything it spawns inherits that — the rule and its measurement are the [bash-best-practices](https://github.com/rokokol/bash-best-practices-skill) skill's, in its `references/pitfalls.md`

**Safe route:** start a background batch of the gate under `set -m`

---

## The behaviour half survives heavy concurrency, and its deadlines are not the fragile part

**Where it bites:** the deadlines and waits of the behaviour half in `check.sh`, the hang check's `--timeout 1` and the interrupt check among them

**Reproduction:** sixteen behaviour halves run at once finished in 11 s against 9.7 s for one alone, all sixteen green, with the `--timeout 1` deadline of the hang check untouched

**Misleading result:** a flaky wait looks like a deadline too tight for "load"

**Mechanism:** what a fixed wait did threaten was meaning. The interrupt check slept 0.5 s before signalling, and `falsify` times the unbroken suite before it edits anything, so the signal landed during the baseline: at the kill, `impl.sh` was pristine and no defect was in flight, three runs out of three, and the two assertions about restoring the source were comparing an untouched file against its own copy. The marker `falsify` writes in `falsify.out/in-flight` arrives at 1.10 s, idle and under sixteen concurrent runs alike, so no sleep short enough to be tolerable was ever long enough to be right. Waiting on that marker was still wrong: `falsify` names the defect in flight and *then* writes the file, so between those two lines the marker exists while the source is still untouched. Invisible here and in a bash-3.2 container, wide enough for a macOS runner to land in — the CI run after that fix went red on exactly it

**Safe route:** before widening a deadline for "load", reproduce the flake. Wait for a state the program announces, not for a duration, and then for the state itself, not for the announcement of it. What the interrupt has to land on is a mutant on disk, so the wait is a `cmp` against the pristine copy and the marker is checked afterwards, as a claim about a state that already holds

---

## A local in a new subcommand collides with a global shellcheck already knows

**Where it bites:** a new function or subcommand in `t.sh`

**Reproduction:** adding `cmd_pollute` cost three renames on that alone: `set` shadows the builtin, `first` is a scalar in `falsify`, and `cmd` is the dispatcher's own variable at the bottom of the file

**Misleading result:** the warning points at the *other* use, not at the new local

**Mechanism:** shellcheck sees every function's locals in a file at once — the bash-best-practices skill's `references/pitfalls.md` has the rule

**Safe route:** pick a local name no other function in the file uses as a global or a builtin

---

## A re-raised signal still runs the EXIT trap

**Where it bites:** a planted copy that proves a signal handler restores a file

**Reproduction:** a copy planted to prove that the INT handler restores a file passes with the restore stripped from INT alone

**Misleading result:** the planted defect reads as caught while the INT handler no longer restores anything

**Mechanism:** `trap - INT; kill -INT $$` does not skip EXIT, so EXIT restores the file instead; the five-line proof is in the bash-best-practices skill's `references/pitfalls.md`

**Safe route:** take the cleanup off every trap, or prove nothing

---

## `nix flake check` proves only the system it runs on

**Where it bites:** the flake evaluation in `check.sh`

**Reproduction:** `x86_64-darwin` sat in `systems` after nixpkgs 26.11 dropped it, un-evaluatable, through every local run and every CI run

**Misleading result:** it prints "all checks passed" and says nothing about the other platforms in `systems`

**Mechanism:** `nix flake check` reads the current system only

**Safe route:** `--all-systems` is the flag that asks the question, and the gate now asks it as one offline eval over the list read out of the flake

---

## An undefined regex escape is a warning, not a difference

**Where it bites:** `flags_of` in `check.sh`

**Reproduction:** `flags_of` matched with `\ ` for a space, which POSIX leaves undefined; five awks were measured and all agree it is a space

**Misleading result:** twenty-nine warnings on stderr in a run that ended `check: everything holds`, which reads like a portability defect

**Mechanism:** the escape is undefined, not divergent; the rule — fix it for the noise, not for a portability story measurement does not support — is the bash-best-practices skill's, in its `references/pitfalls.md`

**Safe route:** fix the escape to silence the warnings, not because an awk reads it differently

---

## Read a probe's whole output, not its tail

**Where it bites:** comparing two implementations of the same probe, such as the awks above

**Reproduction:** the divergence above was first "found" by piping a comparison through `tail -12`, which cut the first lines and made one awk look as though it dropped a flag. Nothing was wrong

**Misleading result:** a truncated view of a disagreement is indistinguishable from a real one

**Mechanism:** a tail keeps only the last lines, so a flag printed before them looks missing from one side

**Safe route:** print both answers in full and diff them

---

## A restored file is a new file, and a new file has no `+x`

**Where it bites:** `falsify` in `t.sh`, which puts every file back from memory, and the `rm` form of a defect

**Reproduction:** the first run of the `rm` form: three entries `caught`, and the gate red on "left the working tree dirty"

**Misleading result:** the byte comparison stays green — it compares content — while `git diff` shows `100755 → 100644` and the next suite meets a source it cannot execute, failing for a reason no defect names. It reads like a restore that lost content

**Mechanism:** the restore is byte-for-byte for an edit that changed bytes. The `rm` form is not: the restore *creates* the file, and a created file is born under the umask without the executable bit

**Safe route:** the bit is recorded when the original is taken (`existed` holds `x` rather than `1`) and put back with the file; the whole mode is not, because `stat` spells its format differently on GNU and BSD and the executable bit is the only part of a mode a suite trips over. Anywhere a check restores by rewriting rather than by `git checkout`, ask what else the original carried besides its bytes
