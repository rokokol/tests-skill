# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), dated rather
than numbered — a skill is read at whatever revision you have checked out, so there is no
version to bump

## Unreleased

### Added

- the skill itself: a core of rules that hold in any language — the command's own status
  rather than a pipe's, the log read even at exit 0, nothing claimed until it has been run
  and watched, test-first with a falsification pass behind it, one logical change per
  commit, unstable tests fixed or quarantined but never retried, no shim for a shape that
  was never released, and a running todo list — plus the two modes (`tdd`, `falsify`) those
  rules are applied in
- `t.sh`, the harness: `run` (honest status out of `PIPESTATUS`, the whole log kept, the log
  scanned for markers of a run that did not happen, the tail printed only after the verdict
  is already decided), `flaky` (N runs, how many disagreed), `bisect` (`git bisect run` with
  a status mapping that skips what cannot answer and clamps a crash so it cannot abort the
  session) and `falsify`
- `falsify` applies hand-written edits from the repository's own `tests/defects.sh` and
  reports `caught` / `SURVIVED` / `stale` / `unusable`. Build and test are separate phases,
  so an edit that stops the code compiling is `unusable` rather than credited to the suite —
  without that distinction every syntax-breaking edit in a compiled language would read as
  coverage that does not exist
- references: verdict, tdd, falsifiability, flaky, commits, no-legacy, layers, and one per
  ecosystem for pytest, shell/bats, go, rust, node, typescript and c++
- `check.sh`, the self-testing gate: the marker table is read out of `t.sh` instead of being
  spelled twice, every marker must catch its fixture and stay silent on a healthy one, and
  every check is proven able to fail against a deliberately broken copy — a dead marker, a
  marker that cries on a good run, a harness reading `tee`'s status, a subcommand missing
  from the help, a bisect passing statuses through raw, a restore losing the trailing
  newline, a `SKILL.md` with no frontmatter, an unreachable reference, a dead link and a
  dead anchor

### Notes

Three of the checks above found real bugs while being written, which is the point of the
rule they enforce: a `PIPESTATUS` guard that `pipefail` had made untestable, a falsify
restore that lost the trailing newline through command substitution — with a check that
missed it by making the same mistake on both sides of the comparison — and a bisect fixture
whose answer was genuinely ambiguous.
