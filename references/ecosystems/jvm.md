# JVM: JUnit 5 with Gradle or Maven

## Run it so it cannot lie quietly

```sh
t.sh run -- ./gradlew test --no-daemon --rerun-tasks
t.sh run -- ./mvnw -q test -DfailIfNoTests=true
```

- **The wrapper, not the global tool.** `./gradlew` and `./mvnw` pin the build tool's version in the repository; a `gradle` or `mvn` from PATH runs whatever the machine has, and the gate then changes behaviour with zero change in the repository
- `--rerun-tasks` (Gradle) — the test task is cached and up-to-date checking is good at its job: a green run may have executed nothing since the last one. Without it, read the log for `UP-TO-DATE` and `FROM-CACHE` beside `:test`
- `-Dmaven.test.skip=true` skips compiling the tests as well as running them, and `-DskipTests` only running them; either in a CI script is a decision that failures do not count, and reads that way in the log
- `--fail-fast` (Gradle) and `-Dsurefire.skipAfterFailureCount=1` are for iterating, never for the gate: the summary then describes a fraction of the suite

## Fail on nothing ran, natively

Every runner here has the switch, and two of three default it the wrong way. The JUnit Platform console launcher has `--fail-if-no-tests`, exit 2. Maven's surefire has `failIfNoTests`, default `false`, so a module whose tests were all renamed away prints `No tests to run.` and builds green; `failIfNoSpecifiedTests` is `true` by default, but only guards an explicit `-Dtest=` filter. Gradle 9 turned `failOnNoDiscoveredTests` on by default — a test task with sources present, no filters and no tests discovered now fails — and the rule for Gradle is not to turn it back off. Below 9, or with surefire's default, the run needs a marker: there is no `markers/jvm.txt` yet, and the recipe for one is at the end

## Green that lies

| Line | What happened |
|---|---|
| `No tests to run.` | surefire found nothing and, by default, did not mind |
| `Tests run: 0, Failures: 0` | same, per class, or a filter that matched nothing |
| `:test UP-TO-DATE` / `FROM-CACHE` | Gradle reused a result; nothing executed in this run |
| `@Disabled` accumulating | a to-do list that never turns red, like `@Ignore` before it |
| `@SpringBootTest` on a unit test | a full context boots, the test runs seconds late, and a failure in wiring reads as a failure in logic |
| `any()` on every argument | Mockito matched anything; the interaction was verified, its arguments were not |

The last two are test-shape lies rather than runner lies. A unit test boots no application context: `@WebMvcTest` for a controller, a plain constructor for a service, `@DataJpaTest` where the database is the subject. A verify that only says the method was called says nothing about what it was told; `ArgumentCaptor` or an explicit value does

## Determinism

- `@TempDir` for filesystem work, never a fixed path under `/tmp` or a file in `target/`
- Inject `java.time.Clock` and pass a fixed one; `Instant.now()` in the code under test is the usual midnight failure
- Method order is unspecified in JUnit 5 and stable enough to depend on by accident; `@TestMethodOrder(MethodOrderer.Random.class)` in CI makes the dependence fail on the day it is introduced. Parallel execution, `junit.jupiter.execution.parallel.enabled`, is where shared static state surfaces
- One JVM per module by default with surefire's `forkCount`; a static singleton initialised in one test class is visible to the next

## For `tests/defects.sh`

The compiler rejects most careless edits, so `-b` is mandatory: `-b './gradlew compileJava compileTestJava -q'` or `-b './mvnw -q compile test-compile'`, otherwise every edit the compiler rejects is credited to the suite. Edits that stay compilable: a `>=` widened to `>`, an `if (condition)` made `if (true)`, a `throw` replaced by a `return`, an `Optional.of(x)` by `Optional.empty()`, a stream `.filter(...)` dropped, a method body replaced by `return null` where the type allows it. Java's checked exceptions and unused-variable warnings under `-Werror` turn some edits `unusable`; that is a measurement of the edit, not of the suite

## Capturing a healthy run for a marker set

A marker set ships only with a real line from a real run behind it, so there is none for the JVM until somebody keeps one. The recipe: run `./gradlew test` on a module where every source set has at least one test and save the whole output as `tests/fixtures/clean/jvm.log`; collect the lying lines you have actually seen — `No tests to run.`, `Tests run: 0` — from real logs into `tests/fixtures/lying/jvm.log`; write `markers/jvm.txt` with one line per lie. The gate then requires every marker to match the lying fixture and to stay quiet on the healthy one, and `-m jvm` does the rest
