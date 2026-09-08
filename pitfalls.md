# Pitfalls

Traps found while working on this repository, kept so the next person editing it does not pay for them twice. Nothing in `SKILL.md` or `references/` links here on purpose: this is a maintainer's note about the gate and the harness themselves, not part of the standard they describe

## Backgrounding the gate needs `set -m`, or its signal probes report nothing

Running copies in parallel is fine; running them off the foreground without job control is not. POSIX has a non-interactive shell start background jobs with `SIGINT` and `SIGQUIT` set to ignore, an ignored disposition is inherited by everything the job spawns, and `check_behaviour` asserts what `bisect-probe` makes of a command killed by a signal — `probe 130 "is interrupted by the user" -- sh -c 'kill -INT $$'` among them. The signal then does nothing and the probe reports 0. Sixteen copies started with a plain `&` failed identically on that line; the same sixteen under `set -m` were all clean, because job control gives each its own process group and the default dispositions back

The gate now runs its copies in parallel and does exactly that: `run_rows` brackets the batch in `set -m`. The fix is that one line rather than any supervision by hand, and it only bites a suite that tests signal handling, which this one does because `bisect-probe` has to tell a crash from a person pressing Ctrl-C

The failure at least announces itself. The danger is reading it as a load problem and relaxing the check

## The behaviour half survives heavy concurrency, and its deadlines are not the fragile part

Sixteen behaviour halves run at once finished in 11 s against 9.7 s for one alone, all sixteen green, with the `--timeout 1` deadline of the hang check untouched. Before widening a deadline for "load", reproduce the flake: on this evidence load is not what threatens them

What a fixed wait did threaten was meaning. The interrupt check slept 0.5 s before signalling, and `falsify` times the unbroken suite before it edits anything, so the signal landed during the baseline: at the kill, `impl.sh` was pristine and no defect was in flight, three runs out of three, and the two assertions about restoring the source were comparing an untouched file against its own copy. The marker `falsify` writes in `falsify.out/in-flight` arrives at 1.10 s, idle and under sixteen concurrent runs alike, so no sleep short enough to be tolerable was ever long enough to be right. Wait for a state the program announces, not for a duration

And then wait for the state itself, not for the announcement of it. Waiting on that marker was the fix, and it was still wrong: `falsify` names the defect in flight and *then* writes the file, so between those two lines the marker exists while the source is still untouched. Invisible here and in a bash-3.2 container, wide enough for a macOS runner to land in — the CI run after that fix went red on exactly it. What the interrupt has to land on is a mutant on disk, so the wait is a `cmp` against the pristine copy and the marker is checked afterwards, as a claim about a state that already holds

## A local in a new subcommand collides with a global shellcheck already knows

`t.sh` is one file, so shellcheck sees every function's locals at once and takes a name used as an array in one and as a scalar in another for a mistake. Adding `cmd_pollute` cost three renames on that alone: `set` shadows the builtin, `first` is a scalar in `falsify`, and `cmd` is the dispatcher's own variable at the bottom of the file. The warnings point at the *other* use, which is why they read as unrelated. Pick names nothing else in the file uses, and run `shellcheck` before running anything else

## A re-raised signal still runs the EXIT trap

The idiom for a signal handler is to clean up, reset the trap and re-raise — `trap - INT; kill -INT $$` — and it is easy to assume the script then dies without its EXIT trap. It does not: bash runs EXIT anyway, verified on a five-line script. So a copy planted to prove that the INT handler restores a file will pass with the restore stripped from INT alone, because EXIT restores it instead. Take the cleanup off every trap, or prove nothing

## `nix flake check` proves only the system it runs on

It reads the current system, prints "all checks passed" and says nothing about the other platforms in `systems`. That is how `x86_64-darwin` sat in the list after nixpkgs 26.11 dropped it, un-evaluatable, through every local run and every CI run. `--all-systems` is the flag that asks the question, and the gate now asks it as one offline eval over the list read out of the flake

## An undefined regex escape is a warning, not a difference

`flags_of` matched with `\ ` for a space, which POSIX leaves undefined. gawk, mawk, busybox awk, goawk and the one-true-awk macOS ships were each run over the four shapes the pattern has to read, and all five agree it is a space. The defect was never a wrong answer; it was twenty-nine warnings on stderr in a run that ended `check: everything holds`. Fix such a thing for the noise, not for a portability story that measurement does not support

## Read a probe's whole output, not its tail

The divergence above was first "found" by piping a comparison through `tail -12`, which cut the first lines and made one awk look as though it dropped a flag. Nothing was wrong. When two implementations are being compared, print both answers in full and diff them, because a truncated view of a disagreement is indistinguishable from a real one

## A planted row's half decides which half proves it

`plant HALF NAME ...` used to be a filter only: the copy was run with the mode of the outer run, so under `all` a row labelled `lint` was equally proven by the behaviour half. The copy now runs the half the row names, which is where most of the gate's time went, and a row carrying the wrong half fails with "the copy did not fail at all" instead of passing on the other half's work

## Shared fixtures were measured and rejected

Rebuilding the same throwaway git repositories in every copy looks like the obvious saving, and it is not one: a timing shim over `git` counted 246 calls totalling 1010 ms in a 9.7 s copy, under 10 percent, and most of those calls are the checks themselves rather than fixture construction

The isolation it would cost is worth more than that. The repository has one `t.sh`, but every planted copy carries its own deliberately broken one, and the table includes "a falsify that does not put the source back" and "bisect refuses to start on a working tree it would trample". A fixture directory shared between copies is a fixture those copies are written to abuse
