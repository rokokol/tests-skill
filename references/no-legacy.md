# No compatibility with a shape that was never released

A compatibility shim is a promise to a user who exists. Written for a shape nobody has ever received, it is a promise to nobody — and it costs the same as a real one: a second code path, a second set of tests, a second thing to reason about, and a name that outlives everyone's memory of why it is there.

## The boundary is the release, and only the release

- **Published contract, already shipped under a tag.** Someone is depending on it. Change it the slow way: deprecate, document, keep both paths for a stated period, remove on a version boundary. That is ordinary versioning and outside this skill's scope.
- **Published contract, not yet released.** The tag has not been cut, so nothing depends on it. A rename is a rename: the old name, every caller and every test of it go in the same commit. No alias, no forwarding wrapper, no "deprecated but still works".
- **Internal to the repository — never part of a published contract.** No shim, ever, at any point in the cycle. The callers are in the same tree; change them.

The question to ask is not "might something use the old name?" but "**has anyone ever been able to depend on it?**". If the answer is no, there is nothing to be compatible with.

## What it looks like in the tests

The rule bites hardest here, because test code is where dead shapes hide longest.

- **Rename the test with the thing.** A test still named after the old function keeps the old vocabulary alive in the one place people search.
- **Delete the old test, do not keep both.** Two tests asserting the same behaviour through two spellings do not double the confidence; they double the maintenance and disagree eventually.
- **Delete the fixture the old shape needed.** An unused fixture reads as a supported input to the next person, who will write a test using it.
- **Do not keep a helper "in case we go back".** Git already keeps it, with the reason attached. A helper nothing calls is a decoration with a maintenance bill.

## Why the shim is the expensive option

- **Two paths, one tested.** The shim's path is exercised only by whoever remembers to write a test for it, and nobody does. It rots into an untested public entry point.
- **It never comes out.** Removal needs someone to prove nothing uses it. That proof is expensive, so it is not attempted, so the shim ships forever — the deprecation notice outliving both the deprecator and the replacement.
- **It teaches the wrong thing.** A codebase full of aliases tells a reader that names are negotiable, and the next change adds another one instead of doing the rename.
- **It hides the size of a change.** Twelve call sites updated in one commit is a visible, reviewable fact. An alias makes the same change look like two lines and defers the other ten to nobody.

## Doing the removal

1. Find every use — `grep` for the name, then again for its string form, its serialised spelling, and its appearance in docs, completions, config examples and CI.
2. Change them all in the same commit as the rename, so no commit in the history is half-renamed. Bisect depends on it — see [commits.md](commits.md).
3. Update the tests in that commit; do not leave a "test the old name still works".
4. Note it in the changelog if a reader could have seen the old shape, and say nothing if they could not — a changelog entry for a name that never shipped is noise.

The one honest exception: a shape that was never tagged but *was* handed to someone — a pre-release branch a colleague is building against, an artefact from CI that a user installed. Then somebody does depend on it, and the first rule applies. The test is whether a real person would break, not whether a version number was printed.
