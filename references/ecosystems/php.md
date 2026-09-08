# PHP: PHPUnit

## Run it so it cannot lie quietly

```sh
t.sh run -- vendor/bin/phpunit --fail-on-empty-test-suite --fail-on-risky --fail-on-warning --fail-on-incomplete --fail-on-skipped
```

- **`vendor/bin/phpunit`, never a global one**: `composer install` with the lock file decides the version, and a `phpunit` from PATH is whatever was installed last on that machine
- `--fail-on-risky` — a risky test is one that ran and asserted nothing, and PHPUnit reports it as passed unless told otherwise. `This test did not perform any assertions` in a green run is a test that cannot fail
- `--fail-on-warning`, `--fail-on-incomplete`, `--fail-on-skipped` — each is a category the runner counts and, by default, does not hold against you. Which of the last two belong in the gate is a choice; that they are counted silently is not
- `--stop-on-failure` is for iterating, never for the gate

## Fail on nothing ran, natively

`--fail-on-empty-test-suite` makes a run that found no tests fail; without it PHPUnit prints `No tests executed!` and exits 0, which is exactly the run that a moved directory or a misspelt `testsuite` in `phpunit.xml` produces. It belongs in `phpunit.xml` under `<phpunit failOnEmptyTestSuite="true">` rather than on every command line, so the policy is in the repository. With the flag in place the marker is a second line; there is no `markers/php.txt` yet, and the recipe for one is at the end

## Green that lies

| Line | What happened |
|---|---|
| `No tests executed!` | the suite was empty and the runner did not mind |
| `OK, but there were issues!` | risky, incomplete or skipped tests, counted and not held against the run |
| `This test did not perform any assertions` | a test that cannot fail, reported as passed |
| `markTestSkipped` accumulating | a condition became true everywhere, and the suite quietly shrank |
| `@covers` on a method nobody calls | coverage claimed for code the test never reached |

## Determinism

- `sys_get_temp_dir()` plus a unique subdirectory per test, removed in `tearDown`; never a fixed path
- `Carbon::setTestNow()` or an injected clock for anything touching `time()`; a test that breaks at midnight is `date()` in the code under test
- `mt_srand()` with a fixed seed where randomness is involved, and the seed in the failure message
- Database tests: a transaction rolled back per test, or a fresh schema per test; a test that passes alone and fails after another is a row the earlier one left
- Static state survives between tests in one process; `@runInSeparateProcess` hides it rather than fixing it

## For `tests/defects.sh`

PHP is forgiving enough that most useful edits stay valid: `if (...)` to `if (false)`, `>=` widened to `>`, a `return` replaced by `return null`, an `array_filter` dropped, a `throw` turned into a `return`. Pair it with `-b 'find src -name "*.php" -exec php -l {} +'` so an edit that breaks the syntax is reported `unusable` instead of being credited to the suite. Infection is the generated-mutant tool here; note that it counts a mutant that errors as killed, which is the opposite of what `falsify` does with `unusable`, and read its score accordingly

## The marker set

`markers/php.txt`, opted into with `-m php`, is deliberately short. PHPUnit 13 is honest with its exit status about most of what can go wrong — a missing bootstrap is 2, a path that does not exist is 2, a filter matching nothing is 1, a class with no test methods is 1 — and a marker for any of those would be a second opinion nobody needs. Two shapes exit 0, both captured from a real PHPUnit 13.3.2 run:

- `No tests executed!` — pointed at a directory holding no test file at all
- `Assertions: 0` — a run in which every test was skipped: it reports OK, exits 0 and verified nothing

The second is worth reading twice, because the obvious marker is the wrong one. `OK, but some tests were skipped!` is the line that names the situation, and a healthy suite prints it the moment one test is platform-specific. A marker on that would redden honest runs, and a marker that cries wolf gets the whole check switched off within a day, which protects nothing. The count is the part that only a run verifying nothing produces
