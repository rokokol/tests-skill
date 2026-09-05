# Commits granular enough to answer

`git bisect` turns "when did this break?" from an argument into fifteen minutes of
mechanical work. It only works if the history is made of commits that can each be judged
on their own — and that property has to be built while committing, because it cannot be
added afterwards.

## The rule

**One logical change per commit, and every commit builds and passes on its own.**

A logical change is one answer to one question: this rename, this bug fix, this new
behaviour. Not "the morning's work". Not "fix tests" three commits after the change that
broke them — that commit is an admission that the earlier one did not stand on its own.

Two consequences worth stating separately:

- **The failing test is its own commit, and the fix is the next one.** The history then
  contains a commit where the bug is demonstrated and one where it is gone, which is the
  clearest possible record of what was wrong. Bisect lands on the fix, and its diff is
  exactly the change that mattered.
- **Refactoring and behaviour change never share a commit.** A diff that both moves code
  and alters it cannot be reviewed: the reviewer cannot see which of the two hundred moved
  lines is the one that also changed. Move in one commit, change in the next.

## Why this is not tidiness

- **Bisect gives a wrong answer on a broken commit.** `git bisect run` reads a non-zero
  status as "bad", so a commit that merely fails to build gets blamed for the regression.
  `t.sh bisect` turns that case into a skip instead — but a history where half the commits
  must be skipped narrows to "somewhere in these eleven commits", which is where you
  started.
- **Revert is only as precise as the commit.** Reverting one clean commit is a decision;
  reverting a commit that also contains four unrelated fixes is a negotiation.
- **Review reads diffs, not intentions.** A reviewer who can hold one change in their head
  finds real bugs. Faced with a thousand-line commit, they approve it.
- **The message can be true.** A commit doing one thing can be described in one sentence.
  If the subject needs an "and", the commit needed splitting.

## In practice

- Commit when a cycle closes: red test in, fix in, refactor in — three commits, not one.
- Use `git add -p` when a working tree has grown two changes; splitting at commit time is
  cheap, splitting after a push is not.
- Before committing, read what is actually staged with `git diff --cached` rather than
  trusting the file list — that is also when a stray credential or a local-only file gets
  caught.
- Run the suite before each commit, not before the push. A commit that "will be fixed by
  the next one" is the one bisect will land on six months from now.
- When a change genuinely cannot be split — a rename that touches every caller — say so in
  the message and keep it mechanical, so a reader can skim it as one operation.

## Finding the commit later

```sh
t.sh bisect v1.4.0 -b 'cargo build --workspace' -- cargo test --workspace
```

`GOOD` is the last revision known to work; HEAD is assumed bad. Each commit is judged with
`t.sh run`, so the same verdict rules apply — a run that exits 0 while its log says nothing
ran is *not* counted as good. A commit that will not build, or has no test runner yet, is
skipped rather than blamed. The working tree must be clean, and it is put back afterwards
even if the run is interrupted.

What a bisect needs from the person running it: a reliable reproducer. If the check is
itself unstable, bisect will confidently return a random commit — see
[flaky.md](flaky.md), and run `t.sh flaky` on the reproducer first if there is any doubt.

Commit *messages* — what may be written in them, and what may not — are the
[ai-commit-trailers](https://github.com/rokokol/ai-commit-trailers-skill) skill's subject,
not this one's.
