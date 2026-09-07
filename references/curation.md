# Curation: what to remove, quarantine and rank

A suite grows by addition and almost never by removal, and the tests that no longer earn their place cost the same minutes as the ones that do. Removing a test is a decision about coverage, and it needs the same evidence as adding one.

## Coverage is not redundancy

Two tests that execute the same lines are not the same test. Coverage says which statements ran; it says nothing about which assertions would fail. Two tests can only be called redundant when one of them catches every defect the other catches — and the only tool that measures that is falsification: run `t.sh falsify` against the defects those tests exist for, and if the candidate for removal catches a defect the survivor misses, keep both. See [falsifiability.md](falsifiability.md). A suite trimmed by coverage alone is a suite that lost the assertions nobody counted.

## Four dispositions

- **Redundant** — proven, as above, to catch nothing the rest does not. Remove it, in a commit that says which test now covers what it covered.
- **Obsolete** — it tests a shape that no longer exists: a removed feature, a renamed contract, a behaviour that was changed on purpose. Remove it with the change, in the same commit, the way [no-legacy.md](no-legacy.md) removes the old name.
- **Low-value** — it runs, it passes, and nobody can say what would have to break for it to fail. Before removing, run one falsification against what it claims to test; a test that catches nothing is a decoration, and a test that catches something has just told you its value.
- **Keep** — everything else, including the tests that have never failed. A test that has never gone red is either guarding something stable or asserting nothing, and history alone cannot tell which: investigate with a defect, do not delete.

Two temptations that are not dispositions: a test deleted because it is unstable — instability is a runtime bug in the test or the code, and the test may be the only thing that sees it; see [flaky.md](flaky.md) — and a test deleted because it is slow, which is a tiering question, below.

## Tiering: what runs where

Rank by what a failure would cost and by what the test has actually caught, and use runtime only to break ties. A smoke tier that runs on every push, a core tier that gates a merge, an extended tier that runs on the default branch and by hand: each earns its place by answering a question the tier below cannot, and a test moved down a tier is still run, only later. The one rule that survives every layout: anything that reaches outside the repository — a package mirror, a live site, a real device — does not gate a change. See [layers.md](layers.md).

## The removal ritual

1. Quarantine first, never delete first: mark it, move it out of the gate, keep it running where its result is visible and blocks nothing.
2. A named approver and a grace period, two release cycles or thirty days, during which an escaped defect in that area is attributed to the quarantine.
3. Then delete, in a small batch, with a commit message naming what was removed and why, and the one-line command that brings it back — `git show <sha>:tests/test_x.py`.

Git history is the floor for recovery, not the plan: a test that was deleted is a test nobody runs, and a defect it would have caught is found in production, not in `git log`.

## The quarantine file

Quarantine that lives only in a decorator is quarantine nobody reviews. A repository keeps `tests/quarantine.md`, one row per test taken out of the gate:

| test | since | category | suspected cause | owner | expires | restore |
|---|---|---|---|---|---|---|
| `tests/test_sync.py::test_retry` | 2026-09-07 | timing | a sleep standing in for the socket close | @name | 2026-09-21 | remove `@pytest.mark.quarantine` |

The categories are [flaky.md](flaky.md)'s; the expiry is a deadline, not a hope. A row past its expiry is a decision that was not made, and a gate can refuse it the way it refuses an unknown config key: loudly, naming the row. More than a few percent of the suite in this file is not a list of unstable tests; it is a suite whose infrastructure is unstable, and the fix is there.
