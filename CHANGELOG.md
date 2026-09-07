# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), dated rather
than numbered, and with no `Unreleased` section — a skill is read at whatever revision you
have checked out, so whatever is on the default branch is what everyone already has, and a
section for work that has landed but not shipped would never close

## 2026-09-07

### Fixed

- **an `allow` regex grep could not compile turned every run into a pass.** The excuse list is applied with `grep -Ev` before the scan; a regex grep rejects left the filtered log empty, an empty log has no markers, and `run` reported `pass — log clean` for a run that said `collected 0 items`. The worst shape a guard can take, because a typo in the excuse list switched the whole check off without a word. `run` now refuses such a regex before the command starts, with exit 64, and the scan itself reports a filter that did not run as a finding rather than as silence
- **a symlink to `t.sh` refused every run.** `ln -s .../t.sh ~/.local/bin/t.sh` is how the harness gets onto a PATH, and it looked for `markers/` beside the link rather than beside the file, so every run through the link exited with "holds no markers". The path is resolved through symlinks now, absolute and relative, without `readlink -f`, which macOS only gained in 12.3
- **`bisect` skipped every commit where `make test` failed.** The probe took the command's exit 2 and 3 for the harness's own "could not run it" and "did not really run", and GNU make exits 2 on any error, so a bisect over a Makefile-driven suite stepped over every bad commit and named nobody. The probe reads the kind of verdict from `run`'s sidecar now and leaves the numbers to the command. Two more corrections on the way: a runner that is not executable (126) is skipped like one that is missing (127), and a run stopped by a person, Ctrl-C or a TERM, is passed through so git aborts the session instead of recording the interrupted commit as bad. A crash is still bad
- **every `falsify` mutant was `unusable` under the bash macOS ships.** bash 3.2 keeps the quotes around the replacement in `${content//"$find"/"$replace"}` as literal text, so the edit written was `"if false"` and nothing built. Found by running the gate under a real 3.2, which is what replaced the grep for bash-4 syntax. The edit is made by cutting around the one occurrence now, which also keeps a `&` in a replacement literal on bash 5.2, where an unquoted one would have meant the match itself
- **Ctrl-C did not stop `falsify`.** Its interrupt handler restored the source and returned, and a handler that returns lets the script carry on: the loop ran the next defect, the interrupted one vanished from the report, and the summary still counted it. The handler now restores and then dies of the same signal, so the caller sees an interrupt and not a shorter report
- **`falsify` reported a mutant it could not write as a survivor.** The edit was written without checking the write. On a read-only source file it failed silently, the suite ran against the pristine code and passed, and a guard the suite does cover was reported as one nobody checks. A write that fails is fatal now, exit 70, with the tree untouched
- **`flaky` could refuse without a word.** It muted each run's output, and `run`'s own refusals went with it, so `flaky 3 -x -- cmd` exited with a usage status and an empty terminal. Flags and marker sets are now checked before the first run, and a refusal `run` can only make once the loop has started is shown rather than swallowed
- `run -t abc` silently meant no tail, because bash arithmetic reads a word as zero; it refuses now. A marker set named twice, on the line or once in the config and once on the line, printed every finding twice; it is loaded once

### Changed

- **the harness's own exit codes moved out of the range test runners use.** `run` reported a lying log as 3, `flaky` reported disagreement as 4, and every usage or harness error was 2. GNU make exits 2 on any error, pytest uses 2 to 5, `mix test` fails with 2, and cargo-nextest exits 4 for "no tests ran", so a probe that skipped on 2 skipped every commit where `make test` failed, and a `flaky` verdict was indistinguishable from nextest's own empty run. The verdicts now sit in a band nothing else claims: 64 for a usage error, 70 for a failure of the harness itself, 79 for a run that exited 0 while its log said otherwise, 86 for runs that disagreed. Anything checking the old numbers must be updated
- **the bash-3.2 guard is a bash 3.2.** The gate grepped the scripts for constructs newer than the bash macOS ships, and a grep matches the constructs somebody thought to list: on its first audit it let nine through, `local -n`, `|&`, `;;&`, `${x@Q}`, `exec {fd}<`, `read -t 0.5`, `wait -n`, `${s:0:-1}`, `globstar`. The guard and its fixture are gone. In their place CI runs the behaviour half of the gate on a macOS runner under `/bin/bash`, with a `declare -A` and a `mapfile` planted in copies of `t.sh` that must fail there, so the proof is about the interpreter and not about a list
- **`falsify` tells a weak suite from a rotten list.** A `stale` entry and an `unusable` one were counted among the survivors, so the report blamed the tests for a defect list nobody had maintained, and CI saw one exit code for three different problems. The summary counts `caught`, `SURVIVED`, `stale` and `unusable` separately, and the exit code says which one ended the run: 83 for a survivor, 87 for a stale list, 88 for an edit that only broke the build; a suite that was red or never ran before any edit is 85 rather than a usage error. The verdict of each run comes from `run`'s sidecar, so a suite whose own exit code is 79 is no longer mistaken for a harness verdict
- `flaky`, `bisect` and `bisect-probe` name the flags they forward to `run`, `-m`, `-p`, `-t`, and `-l` where the logs may go, and refuse anything else before the first run, where they used to sweep any word up and hand it on. The gate reads accepted flags out of each parser, and a documented `t.sh flaky 20 -m rust` was being flagged as impossible

### Added

- `.github/dependabot.yml` watches the action pins weekly, grouped into one pull request, as the [ci](https://github.com/rokokol/ci-skill) skill's pinning rule has always said and no repository in the family did. The gate requires the file
- the gate now runs the [ci](https://github.com/rokokol/ci-skill) skill's two travelling checkers, copied verbatim: `check-skill.sh`, which proves SKILL.md loadable, walks the links from it to require every reference reachable, and resolves every link and anchor with GitHub's own slug rules; and `check-pins.sh`, which greps the workflows for fourteen shapes of unpinned registry lookup and proves on every run that it catches each of them. Both falsify themselves on copies of the repository. Adopters get the same two files from the ci skill
- `bisect` reads what git said instead of passing git's status through. A culprit is named on its own line and exits 0; a history where only commits that could not answer are left between good and bad is reported `INCONCLUSIVE` with exit 89, where before git's own nonzero came back looking like a usage error. git's session log is saved beside the run's logs as `bisect.log`, so a wrong answer can be corrected with `git bisect replay`. `--first-parent` and `--no-checkout` are passed through to `git bisect start`, and a bisect already in progress is refused rather than silently reset, which is what `git bisect start` does on its own
- `run` writes the kind of verdict it reached, `pass`, `fail` or `lied`, beside the log as `LOG.verdict`. A number cannot carry it: the command's own 79 would read as the harness's. The other subcommands read the sidecar instead of guessing from the status, and a wrapper of your own can do the same

## 2026-09-05

### Fixed

- **the harness needed a bash newer than the one macOS ships.** `[[ -v VAR ]]` is bash
  4.2+ and broke `run` outright on a macOS runner; `declare -A` in `falsify` is 4.0+ and
  would have broken it next. Both are gone — the first was a redundant clause, the second
  became two parallel arrays, which for a handful of paths costs nothing. Reported from a
  CI run on a machine none of this was written on, which is the only place it could have
  been found. A guard now greps every shipped script for constructs a bash 3.2 or a BSD
  userland does not have, with each literal split so the pattern cannot match its own
  source, and the planted constructs kept in a fixture for the same reason

- **a marker file checked out with CRLF reported every healthy run as a lie.** A blank
  line became a marker of one carriage return, `grep -F` found that on every line of a
  CRLF log, and a passing `cargo test` was reported as `LIED` with a build line offered as
  the evidence. The trailing CR is stripped when reading marker files and `tests/t.conf`
  now, and a CRLF fixture holds it. Found on a Windows runner by somebody using the skill,
  where git's autocrlf converts on checkout — the worst shape a marker bug can take, since
  a check that reddens good runs is a check that gets switched off

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
