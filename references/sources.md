# Sources

Where the rules come from, one line per source, grouped by the reference that uses it. Only primary sources: papers, official documentation, the authors of the ideas. The references themselves cite this file rather than the web, so a rule never depends on somebody else's repository staying where it was

## The verdict, and the log

- [Bash manual, Pipelines](https://www.gnu.org/software/bash/manual/html_node/Pipelines.html) and [Bash Variables](https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html) — `pipefail` reports the last non-zero status; `PIPESTATUS` is reset after every simple command, which is why it is copied as an array in one command
- [Greg's Wiki, SignalTrap](https://mywiki.wooledge.org/SignalTrap) and [Cracauer, Proper handling of SIGINT/SIGQUIT](https://www.cons.org/cracauer/sigint.html) — a trap that returns lets the script carry on; the idiom is to clean up, reset the trap and re-raise the signal, because an `exit 130` is an exit and not a signal to the caller
- [pytest exit codes](https://docs.pytest.org/en/stable/reference/exit-codes.html) — 5 for nothing collected, unconditionally; [GNU make, Running](https://www.gnu.org/software/make/manual/html_node/Running.html) — 2 on any error; [cargo-nextest exit codes](https://docs.rs/crate/nextest-metadata/latest/source/src/exit_codes.rs) — 4 for no tests run, 100 for a failure, 101 for a build failure; [sysexits(3)](https://man.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3) — 64 for usage, 70 for software, the band the harness's own codes avoid
- [git-bisect(1)](https://git-scm.com/docs/git-bisect) — 0 good, 1 to 124 bad, 125 skip, 126 and 127 bad, anything from 128 aborts; `--first-parent`; `git bisect start` resets a bisect in progress; [git-worktree(1)](https://git-scm.com/docs/git-worktree) — `refs/bisect` is per worktree
- Native fail-on-nothing-ran switches: [ctest](https://cmake.org/cmake/help/latest/manual/ctest.1.html) `--no-tests=error`; [jest CLI](https://jestjs.io/docs/cli) `--passWithNoTests`; [vitest](https://vitest.dev/config/passwithnotests) `passWithNoTests`; [mocha CLI](https://mochajs.org/running/cli/) `--fail-zero` and `--posix-exit-codes`; [playwright CLI](https://playwright.dev/docs/test-cli) `--pass-with-no-tests`, `--fail-on-flaky-tests`; [bats usage](https://bats-core.readthedocs.io/en/stable/usage.html) `--allow-empty-suite` and `BATS_NO_FAIL_FOCUS_RUN`; [maven-surefire](https://maven.apache.org/surefire/maven-surefire-plugin/test-mojo.html) `failIfNoTests`; [Gradle 9 upgrade notes](https://docs.gradle.org/current/userguide/upgrading_major_version_9.html) `failOnNoDiscoveredTests`; [JUnit console launcher](https://docs.junit.org/6.0.3/running-tests/console-launcher.html) `--fail-if-no-tests`; [dotnet test, VSTest](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-test-vstest) `TreatNoTestsAsError`; [Microsoft.Testing.Platform exit codes](https://learn.microsoft.com/en-us/dotnet/core/testing/microsoft-testing-platform-troubleshooting) 8 and 9; [PHPUnit CLI](https://docs.phpunit.de/en/11.5/textui.html) `--fail-on-empty-test-suite`; [go test issue 64500](https://github.com/golang/go/issues/64500) — the proposal to fail on no tests, closed
- [nextest retries](https://nexte.st/docs/features/retries/) — a test that passes on retry is marked flaky and counted as a success by default; `--flaky-result fail`
- [xcpretty](https://github.com/xcpretty/xcpretty) — a formatter that always exits 0, the pipe problem in the wild

## Test first, and the red

- Kent Beck, [Test Desiderata](https://testdesiderata.com/) — twelve properties; *behavioral* is what falsification measures, *structure-insensitive* is what a stale find text violates
- [Software Engineering at Google, chapter 12, Unit Testing](https://abseil.io/resources/swe-book/html/ch12.html) — test behaviours not methods, no logic in tests, DAMP over DRY, unchanging tests, the Beyoncé rule
- [Testing on the Toilet: Change-Detector Tests Considered Harmful](https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html) — the test that fails for edits that change no behaviour, the mirror image of a surviving defect
- Michael Feathers, [Characterization Testing](https://michaelfeathers.silvrback.com/characterization-testing) — an assertion known to be wrong, so the failure reports what the code does
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices) — the failing test written and watched failing before the implementation, and the ladder from a prompt to a stop hook to a verifying subagent. The page also commits the failing test on its own, which this skill does not: a red commit is one bisect cannot judge, so the test lands with its fix, see [commits.md](commits.md)

## Falsification

- Niedermayr, Juergens, Wagner, [Will my tests tell me if I break this code?](https://arxiv.org/abs/1611.07163) — pseudo-tested methods: covered, and no test fails when the body is removed; six to fifty-three percent of methods across projects
- Vera-Pérez et al., [Descartes: extreme mutation](https://arxiv.org/abs/1811.03045) and [A comprehensive study of pseudo-tested methods](https://arxiv.org/abs/1807.05030) — whole-body replacement as the cheap, high-signal mutant
- Just et al., [Are mutants a valid substitute for real faults?](https://homes.cs.washington.edu/~rjust/publ/mutants_real_faults_fse_2014.pdf) — mutant detection correlates with real-fault detection independently of coverage, on 357 real faults
- Inozemtseva and Holmes, [Coverage is not strongly correlated with test suite effectiveness](https://www.semanticscholar.org/paper/abd840dbcfd986e6de9102ab809c2c46e5ce47aa) — once suite size is held constant
- Petrović, Ivanković, Fraser, Just, [Practical mutation testing at scale](https://arxiv.org/abs/2102.11378) and [Does mutation testing improve testing practices?](https://arxiv.org/abs/2103.07189) — arid code suppressed, one mutant per line, at most seven per file, productivity from fifteen to over eighty percent, and developers writing more tests when a survivor is shown in review
- Beller et al., [Mutation testing at Facebook](https://arxiv.org/abs/2010.13464) — mutants must be realistic, actionable and shown with the tests that visit the code
- Jia and Harman, [An analysis and survey of the development of mutation testing](https://web.eecs.umich.edu/~weimerw/2022-481F/readings/mutation-testing.pdf); Papadakis et al., [Mutation testing advances](https://mutationtesting.uni.lu/survey.pdf) — the competent programmer hypothesis, the coupling effect, equivalent mutants as the undecidable core
- [cargo-mutants](https://mutants.rs/) — `unviable` excluded from the score, a timeout of five times the baseline with a floor of twenty seconds, `mutants.out` with one file per verdict, `--in-diff`, `--in-place` and its warnings, exit codes that tell a weak suite from a bad baseline; [Stryker mutant states](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/) and [disabling mutants](https://stryker-mutator.io/docs/stryker-js/disable-mutants/) — compile errors out of the score, an exception declared on the line with a reason; [PIT](https://pitest.org/quickstart/basic_concepts/) — the loop-increment timeout, logging calls not mutated, a green suite required; [mutmut](https://mutmut.readthedocs.io/) — `break` no longer mutated to `continue` because of hangs
- Zhang and Mesbah, [Assertions are strongly correlated with test suite effectiveness](https://people.ece.ubc.ca/amesbah/resources/papers/fse15.pdf)
- [tsDetect](https://testsmells.org/assets/publications/FSE2020_TechnicalPaper.pdf) — the test smells: assertion roulette, eager test, mystery guest, conditional test logic, sleepy test, resource optimism
- [Principles of Chaos Engineering](https://principlesofchaos.org/) — the steady-state hypothesis and injected failure, falsification at system scale; [Hypothesis](https://hypothesis.readthedocs.io/) — a falsifying example, shrunk

## Flaky tests

- [Software Engineering at Google, chapter 11, Testing Overview](https://abseil.io/resources/swe-book/html/ch11.html) — a flaky rate around 0.15 percent, and tests losing their value near one percent; [Flaky Tests at Google and How We Mitigate Them](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html); [Where do our flaky tests come from?](https://testing.googleblog.com/2017/04/where-do-our-flaky-tests-come-from.html)
- Martin Fowler, [Eradicating Non-Determinism in Tests](https://martinfowler.com/articles/nonDeterminism.html) — quarantine with a hard cap, the five causes, never a bare sleep
- [Kubernetes flaky test policy](https://github.com/kubernetes/community/blob/main/contributors/devel/sig-testing/flaky-tests.md) — zero automatic retries, `[Flaky]` in the name, an issue in the milestone; [Fuchsia test flake policy](https://fuchsia.dev/fuchsia-src/development/testing/test_flake_policy) — a flake is a failure that passed on retry of the same patch set, removed from the queue immediately
- [Datadog flaky test management](https://docs.datadoghq.com/tests/flaky_test_management/) and [Trunk flaky test detection](https://docs.trunk.io/flaky-tests/detection) — both outcomes on one commit as the signal; a quarantine that expires
- [pytest-randomly](https://github.com/pytest-dev/pytest-randomly), [pytest-repeat](https://pypi.org/project/pytest-repeat/), [pytest-rerunfailures](https://pypi.org/project/pytest-rerunfailures/) — the first two prove instability, the third hides it; [go test flags](https://pkg.go.dev/cmd/go#hdr-Testing_flags) — `-count`, `-shuffle`, `-race`; [Playwright retries](https://playwright.dev/docs/test-retries) — the flaky outcome

## Commits and bisect

- [git-bisect(1)](https://git-scm.com/docs/git-bisect), as above; [Linux kernel bisect guide](https://docs.kernel.org/admin-guide/bug-bisect.html) — a commit that will not build is skipped, and getting that wrong once sends the rest of the bisection off course

## Layers, fakes, coverage

- Martin Fowler, [Test Pyramid](https://martinfowler.com/bliki/TestPyramid.html) and [Self-Testing Code](https://martinfowler.com/bliki/SelfTestingCode.html); Kent C. Dodds, [Write tests](https://kentcdodds.com/blog/write-tests) — the more a test resembles the way the software is used, the more confidence it gives
- [Testing on the Toilet: Don't Put Logic in Tests](https://testing.googleblog.com/2014/07/testing-on-toilet-dont-put-logic-in.html) and [Tests Too DRY? Make Them DAMP](https://testing.googleblog.com/2019/12/testing-on-toilet-tests-too-dry-make-them-damp.html)
- [Hypothesis](https://hypothesis.readthedocs.io/), [QuickCheck](https://hackage.haskell.org/package/QuickCheck/docs/Test-QuickCheck.html), [fast-check](https://github.com/dubzzz/fast-check) — property-based testing and shrinking; [libFuzzer](https://llvm.org/docs/LibFuzzer.html) and [cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz) — fuzzing; [Pact](https://docs.pact.io/) — consumer-driven contracts and `can-i-deploy`

## Bash 3.2 and BSD userland

- [Bash CHANGES](https://tiswww.case.edu/php/chet/bash/NEWS) — what each version added; the macOS man pages for [sed](https://man.freebsd.org/cgi/man.cgi?query=sed&sektion=1&manpath=macOS+14.3.1), [grep](https://man.freebsd.org/cgi/man.cgi?query=grep&sektion=1&manpath=macOS+14.3.1), [readlink](https://man.freebsd.org/cgi/man.cgi?query=readlink&sektion=1&manpath=macOS+14.3.1) and [date](https://man.freebsd.org/cgi/man.cgi?query=date&sektion=1&manpath=macOS+14.3.1) — `sed -i` needs an argument, no `grep -P`, `readlink -f` from 12.3, no `date -d`, no `timeout`

## Adjacent skills, read and not depended on

While this skill was being written, the testing, debugging and verification skills published for coding agents by several authors were read for ideas — among them the superpowers, qa-skills, augmentedcode-skills, agent-skills and trailofbits collections. What was borrowed is stated as a rule in the references above, in this skill's own words; nothing here links to or loads any of them, because a rule that depends on somebody else's repository staying where it was is a rule that can vanish
