# The repository's own gate

A suite answers "does the code work". A gate answers "is this repository still what it claims to be": that its scripts parse and lint, that its documents do not point at files nobody has, that its own checks can still fail. It is one committed script, and CI runs exactly it rather than a list of commands in a workflow — a list nobody can run by hand drifts from what anyone actually runs

## One name

`check.sh` at the root, run as `./check.sh`. A gate that answers to one name is found by a newcomer, by CI and by any tool that wants to know whether this repository is healthy, without asking anybody

Names beginning with `check-` are a different thing: a checker that travels. It arrives as a verbatim copy locked to the revision it was taken from, is never edited in place, and the gate calls it. A repository with no gate of its own calls such checkers from CI directly — that is a repository with checkers and no gate, not a gate under another name. A checker that belongs here and checks one thing takes the same shape, `check-<subject>.sh`, beside the gate that runs it

## Two halves, and why

```sh
./check.sh lint        # what the repository ships: scripts, workflows, docs, data
./check.sh behaviour   # what its code does, against throwaway fixtures
./check.sh             # both, and the default
```

The split is two sets of requirements rather than tidiness. The lint half needs linters, pinned in the repository's own lockfile, and runs where they can be installed. The behaviour half must run where the code has to work, which for anything that travels means the oldest shell it claims — `/bin/bash` 3.2 on a macOS runner — with git and nothing else. Folded together, either the linters are shipped to a runner that does not need them, or the one environment that tests portability is lost

A gate that proves itself needs a switch that runs it without its own proof pass, or every copy it makes recurses into making copies. Name it in the environment, document it in the gate's help, and pass it wherever the gate runs inside itself — a copy, a worktree, a falsification run

## The gate proves itself

A checker that has never been red is a decoration ([falsifiability.md](falsifiability.md)). For a gate that means a copy of the repository per planted defect, one thing broken in each, and **each copy has to fail for its own defect's reason**: asserting only that the copy failed lets one broken check take credit for another's proof. Before any of it, an untouched copy must pass — if it does not, every "able to fail" below it is vacuous while the gate stays green

Most planted defects belong in the repository's defect list instead, where a falsification run applies them after a merge rather than on every push. What stays in the gate is what a list cannot hold:

- a defect in the gate itself, because a defect in the suite is "caught" by the suite falling over, which proves nothing about what it checks
- a defect in a fixture, which falsification refuses — and the flag that allows one allows them all, for the whole run
- a defect that exists only under a particular interpreter, such as a construct that is no defect at all under a newer shell

## Leave a vendored copy alone

A vendored file arrives whole and locked, and its logic is maintained at its source. Do not write a check here against that logic: such a check tests somebody else's code from the outside, goes stale the next time the copy advances, and has to be written again in every repository holding a copy — while the one place that can maintain it is the source

The exception is a seam rather than a copy: where the vendored file's behaviour depends on this repository's own files — the list it is pointed at, the layout it expects, the data it reads — then what is being checked is that seam, and it belongs here, because nowhere else knows about it

## The policy has to know about the gate

A repository's test policy must name the gate as one of its own test files:

```text
tests     check.sh
```

Without it, `t.sh prove` reads the gate as code, takes it away together with the fix it is proving, and reports `VACUOUS` for a commit whose tests were removed along with the change they pin
