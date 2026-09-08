# Pitfalls

Traps found while working on this repository, kept so the next person editing it does not pay for them twice. Nothing in `SKILL.md` or `references/` links here on purpose: this is a maintainer's note about the gate and the harness themselves, not part of the standard they describe

## Backgrounding the gate needs `set -m`, or its signal probes report nothing

Running copies in parallel is fine; running them off the foreground without job control is not. POSIX has a non-interactive shell start background jobs with `SIGINT` and `SIGQUIT` set to ignore, an ignored disposition is inherited by everything the job spawns, and `check_behaviour` asserts what `bisect-probe` makes of a command killed by a signal — `probe 130 "is interrupted by the user" -- sh -c 'kill -INT $$'` among them. The signal then does nothing and the probe reports 0. Sixteen copies started with a plain `&` failed identically on that line; the same sixteen under `set -m` were all clean, because job control gives each its own process group and the default dispositions back

Nothing in the gate is affected today: `catches` runs each copy in a command substitution, which is the foreground. This is for whoever adds parallelism, and the fix is the one line `set -m` rather than any supervision by hand. It also only bites a suite that tests signal handling, which this one does because `bisect-probe` has to tell a crash from a person pressing Ctrl-C

The failure at least announces itself. The danger is reading it as a load problem and relaxing the check

## The behaviour half survives heavy concurrency unchanged

Sixteen behaviour halves run at once finished in 11 s against 9.7 s for one alone, all sixteen green, with the `--timeout 1` deadline of the hang check and the `sleep 0.5` of the interrupt check untouched. Before widening either of those for "load", reproduce the flake: on this evidence the deadlines are not the fragile part

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
