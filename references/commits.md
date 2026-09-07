# Commits granular enough to answer

`git bisect` turns "when did this break?" from an argument into fifteen minutes of mechanical work. It only works if the history is made of commits that can each be judged on their own — and that property has to be built while committing, because it cannot be added afterwards.

## The rule

**One logical change per commit, and every commit builds and passes on its own.**

A logical change is one answer to one question: this rename, this bug fix, this new behaviour. Not "the morning's work". Not "fix tests" three commits after the change that broke them — that commit is an admission that the earlier one did not stand on its own.

Two consequences worth stating separately:

- **The test and the code it pins are one commit.** The red is watched before the commit, not stored in the history: a commit whose suite is red is a commit that does not stand on its own, and the rule above forbids it. The commit carries both, passes, and demonstrates itself afterwards — `t.sh prove HEAD -- CMD` takes the code back out, keeps the test, and requires the suite to go red. Bisect lands on that commit, and its diff is exactly the change that mattered, test included.
- **Refactoring and behaviour change never share a commit.** A diff that both moves code and alters it cannot be reviewed: the reviewer cannot see which of the two hundred moved lines is the one that also changed. Move in one commit, change in the next.

## Why this is not tidiness

- **Bisect gives a wrong answer on a broken commit.** `git bisect run` reads a non-zero status as "bad", so a commit that merely fails to build gets blamed for the regression. `t.sh bisect` turns that case into a skip instead — but a history where half the commits must be skipped narrows to "somewhere in these eleven commits", which is where you started.
- **Revert is only as precise as the commit.** Reverting one clean commit is a decision; reverting a commit that also contains four unrelated fixes is a negotiation.
- **Review reads diffs, not intentions.** A reviewer who can hold one change in their head finds real bugs. Faced with a thousand-line commit, they approve it.
- **The message can be true.** A commit doing one thing can be described in one sentence. If the subject needs an "and", the commit needed splitting.

## In practice

- Commit when a cycle closes: the test with its code in one commit, the refactor in the next — two commits, not one and not three.
- Use `git add -p` when a working tree has grown two changes; splitting at commit time is cheap, splitting after a push is not.
- Before committing, read what is actually staged with `git diff --cached` rather than trusting the file list — that is also when a stray credential or a local-only file gets caught.
- Run the suite before each commit, not before the push. A commit that "will be fixed by the next one" is the one bisect will land on six months from now.
- When a change genuinely cannot be split — a rename that touches every caller — say so in the message and keep it mechanical, so a reader can skim it as one operation.

## Finding the commit later

```sh
t.sh bisect v1.4.0 -b 'cargo build --workspace' -- cargo test --workspace
```

`GOOD` is the last revision known to work; HEAD is assumed bad. Each commit is judged with `t.sh run`, so the same verdict rules apply — a run that exits 0 while its log says nothing ran is *not* counted as good. A commit that will not build, or has no test runner yet, is skipped rather than blamed. The working tree must be clean, and it is put back afterwards even if the run is interrupted.

The contract underneath is `git bisect run`'s, and it is worth knowing because a wrapper that gets it wrong accuses the wrong commit with confidence: the probe exits 0 for good, 1 to 124 for bad, **125 for a commit that cannot answer**, and anything from 128 aborts the whole session. A build failure returned as 1 marks a clean commit bad; a test runner missing at an old commit exits 127, which git reads as bad too. `t.sh bisect-probe` reads the kind of verdict from `run`'s sidecar rather than from the number, turns 79, 126, 127 and its own refusals into a skip, and passes a person's Ctrl-C through so git aborts. What git prints is read as well: a culprit is named on its own line, and a history where only commits that could not answer are left between good and bad is reported `INCONCLUSIVE`, exit 89, rather than as git's own nonzero. The session log is kept beside the run's logs as `bisect.log`, because it is the one artifact a wrong answer can be corrected from — edit it, `git bisect replay` — and a bisect already in progress is refused, since `git bisect start` would reset it without a word. `--first-parent` follows only the first parent of a merge, which is the bisect to run when a merged branch held commits that never built on their own.

What a bisect needs from the person running it: a reliable reproducer, and a narrow one. Bisect one targeted test, `-- pytest tests/test_sync.py::test_retry`, never the whole suite: an unrelated failure in another file at an older commit reads as "bad" and sends the search off course. If the check is itself unstable, bisect will confidently return a random commit — see [flaky.md](flaky.md), and run `t.sh flaky` on the reproducer first if there is any doubt.

Commit *messages* — what may be written in them, and what may not — are the [ai-commit-trailers](https://github.com/rokokol/ai-commit-trailers-skill) skill's subject, not this one's.
