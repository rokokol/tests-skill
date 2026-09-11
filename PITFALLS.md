# Pitfalls

Traps found while working on this repository, kept so the next person editing it does not pay for them twice. Nothing in `SKILL.md` or `references/` links here on purpose: this is a maintainer's note about the gate and the harness themselves, not part of the standard they describe

## Backgrounding the gate needs `set -m`, or its signal probes report nothing

A background job of a non-interactive shell starts with `SIGINT` and `SIGQUIT` ignored, and everything it spawns inherits that — the rule and its measurement are the [bash-best-practices](https://github.com/rokokol/bash-best-practices-skill) skill's, in its `references/pitfalls.md`. Here it bites because `check_behaviour` asserts what `bisect-probe` makes of a command killed by a signal, `probe 130 "is interrupted by the user" -- sh -c 'kill -INT $$'` among them: sixteen copies started with a plain `&` failed identically on that line, the same sixteen under `set -m` were all clean, and `run_rows` now brackets the batch in `set -m`. The failure at least announces itself; the danger is reading it as a load problem and relaxing the check

## The behaviour half survives heavy concurrency, and its deadlines are not the fragile part

Sixteen behaviour halves run at once finished in 11 s against 9.7 s for one alone, all sixteen green, with the `--timeout 1` deadline of the hang check untouched. Before widening a deadline for "load", reproduce the flake: on this evidence load is not what threatens them

What a fixed wait did threaten was meaning. The interrupt check slept 0.5 s before signalling, and `falsify` times the unbroken suite before it edits anything, so the signal landed during the baseline: at the kill, `impl.sh` was pristine and no defect was in flight, three runs out of three, and the two assertions about restoring the source were comparing an untouched file against its own copy. The marker `falsify` writes in `falsify.out/in-flight` arrives at 1.10 s, idle and under sixteen concurrent runs alike, so no sleep short enough to be tolerable was ever long enough to be right. Wait for a state the program announces, not for a duration

And then wait for the state itself, not for the announcement of it. Waiting on that marker was the fix, and it was still wrong: `falsify` names the defect in flight and *then* writes the file, so between those two lines the marker exists while the source is still untouched. Invisible here and in a bash-3.2 container, wide enough for a macOS runner to land in — the CI run after that fix went red on exactly it. What the interrupt has to land on is a mutant on disk, so the wait is a `cmp` against the pristine copy and the marker is checked afterwards, as a claim about a state that already holds

## A local in a new subcommand collides with a global shellcheck already knows

shellcheck sees every function's locals in a file at once, and the warning points at the *other* use — the bash-best-practices skill's `references/pitfalls.md` has the rule. In `t.sh` adding `cmd_pollute` cost three renames on that alone: `set` shadows the builtin, `first` is a scalar in `falsify`, and `cmd` is the dispatcher's own variable at the bottom of the file

## A re-raised signal still runs the EXIT trap

`trap - INT; kill -INT $$` does not skip EXIT; the five-line proof is in the bash-best-practices skill's `references/pitfalls.md`. Here it means a copy planted to prove that the INT handler restores a file passes with the restore stripped from INT alone, because EXIT restores it instead: take the cleanup off every trap, or prove nothing

## `nix flake check` proves only the system it runs on

It reads the current system, prints "all checks passed" and says nothing about the other platforms in `systems`. That is how `x86_64-darwin` sat in the list after nixpkgs 26.11 dropped it, un-evaluatable, through every local run and every CI run. `--all-systems` is the flag that asks the question, and the gate now asks it as one offline eval over the list read out of the flake

## An undefined regex escape is a warning, not a difference

`flags_of` matched with `\ ` for a space, which POSIX leaves undefined; five awks were measured and all agree it is a space, and the rule — fix it for the noise, not for a portability story measurement does not support — is the bash-best-practices skill's, in its `references/pitfalls.md`. Here the defect was twenty-nine warnings on stderr in a run that ended `check: everything holds`

## Read a probe's whole output, not its tail

The divergence above was first "found" by piping a comparison through `tail -12`, which cut the first lines and made one awk look as though it dropped a flag. Nothing was wrong. When two implementations are being compared, print both answers in full and diff them, because a truncated view of a disagreement is indistinguishable from a real one

## A planted row's half decides which half proves it

`plant HALF NAME ...` used to be a filter only: the copy was run with the mode of the outer run, so under `all` a row labelled `lint` was equally proven by the behaviour half. The copy now runs the half the row names, which is where most of the gate's time went, and a row carrying the wrong half fails with "the copy did not fail at all" instead of passing on the other half's work

## Shared fixtures were measured and rejected

Rebuilding the same throwaway git repositories in every copy looks like the obvious saving, and it is not one: a timing shim over `git` counted 246 calls totalling 1010 ms in a 9.7 s copy, under 10 percent, and most of those calls are the checks themselves rather than fixture construction

The isolation it would cost is worth more than that. The repository has one `t.sh`, but every planted copy carries its own deliberately broken one, and the table includes "a falsify that does not put the source back" and "bisect refuses to start on a working tree it would trample". A fixture directory shared between copies is a fixture those copies are written to abuse
