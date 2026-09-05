# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), dated rather
than numbered — a skill is read at whatever revision you have checked out, so there is no
version to bump

## Unreleased

### Fixed

- **the "able to fail" proofs had stopped proving anything.** Adding the `actionlint` step
  made every throwaway copy die there, before it ever reached its planted defect — so each
  `! nested` assertion held for the wrong reason, and the gate stayed green while sixteen
  falsifications were vacuous. Two guards now make that unrepeatable: an untouched copy
  must pass before any defect is planted, and each planted defect must produce **its own**
  failure message rather than merely some failure. The second guard immediately found the
  duplicate-marker rule unproven as well — its copy was failing on the dead-entry rule
  first, so the rule it was written for had never run
- `flaky` ignored the `logdir` its repository names in `tests/t.conf`, writing where `run`
  would not. It reads the same policy now

### Changed

- the markers of a lying run moved out of `t.sh` into `markers/*.txt`, so the list grows as
  data without touching the harness. `markers/default.txt` always applies; `-m NAME` adds a
  set shipped beside the script and `-m path/to/file` one of your own. `check.sh` reads the
  same files `run` reads, and requires every entry to catch a line in its set's fixture, so
  a dead marker cannot sit there looking like a guard. A set that resolves to nothing —
  missing, empty, misspelled — refuses to run rather than passing quietly
- `tests/t.conf`, a repository's own testing policy: which marker sets apply, one-off
  patterns, the excused-lines regex, the log directory ([template](templates/t.conf)). Read
  from the current directory only — no search up the tree, because a config found three
  directories away is a config nobody knew was in effect — and it **never carries the
  command**, which stays after `--` so a green run's subject is visible where its verdict
  is. An unknown key, a key with no value or a marker set that does not exist stops the run
  and names the line: a typo that is skipped leaves a repository believing in markers that
  were never loaded, which is worse than having no config at all
- six per-ecosystem marker sets ship beside the default one — `pytest`, `shell`, `go`,
  `rust`, `node`, `cpp` — each opted into with `-m NAME` and each with its own fixture, so
  the knowledge in `references/ecosystems/` is now executable rather than only readable. No
  ecosystem set may repeat a default entry, which the gate enforces: the default applies to
  every run already, so the copy would be dead weight reading as extra coverage
- the refusal above had to be moved out of `scan_log`, which runs inside a `$(...)`: `die`
  there exits the subshell and the caller carries on with an empty result, so a guard
  written that way does not guard. Written as it was, an empty marker list would have made
  every run a pass while the check still looked like it was working

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
