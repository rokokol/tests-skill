# Playwright and end-to-end tests

## Run it so it cannot lie quietly

```sh
t.sh run -- npx --no-install playwright test --forbid-only --fail-on-flaky-tests --retries 0
```

- **`--retries 0` in the gate.** Playwright's retries produce a third outcome, `flaky`, for a test that failed and then passed, and a run with flaky tests is green. This skill's rule is that a test which passes and fails on the same code is fixed or quarantined, never retried, so the gate runs without retries and `--fail-on-flaky-tests` makes a flaky outcome a failure wherever a retry is configured anyway
- `--forbid-only` — a committed `test.only` silently reduces the run to one test while every status line still says it passed
- `--reporter=list,html` with `trace: 'on-first-retry'` or `'retain-on-failure'`, `screenshot: 'only-on-failure'`, `video: 'retain-on-failure'`: a failed end-to-end test without a trace is a failure nobody can read
- Install with `npm ci` and `npx playwright install --with-deps` pinned by the lock file; a browser version that moved is a run whose behaviour changed with zero change in the repository

## Fail on nothing ran, natively

Playwright fails when it finds no tests unless `--pass-with-no-tests` says otherwise, so the rule is not to pass that flag. A `testDir` or `testMatch` that points beside the tests is the usual way to get there, and the count in the summary line is worth reading once on the day the config is written

## Green that lies

| Line | What happened |
|---|---|
| `N flaky` in the summary | a test failed and then passed; the run is green |
| `expect(await locator.isVisible()).toBe(true)` | a one-shot check with no retry, which passes or fails on timing |
| `page.waitForTimeout(500)` | a sleep standing in for a condition; passes until the machine is loaded |
| a raw CSS or XPath locator | tied to the DOM's shape, so a refactor of the page fails a test about a behaviour that did not change |
| `test.fixme` and `test.skip` accumulating | a to-do list that never turns red |
| the app started in the test itself | the test passes against a server nobody configured the way production is |

Two rules make most of that table go away. **Web-first assertions**: `await expect(locator).toBeVisible()` retries until the condition holds or the timeout expires, where `expect(await locator.isVisible())` asks once; every assertion on the page goes through `expect(locator)`. **Locators by role**: `getByRole('button', { name: 'Save' })`, then `getByLabel`, `getByPlaceholder`, `getByText`, then `getByTestId` — in that order, because the first asserts what a user can perceive and the last asserts what the developer named; a CSS selector only for a third-party widget that offers nothing else

## Determinism

- `page.clock.install()` before `page.goto()` for anything that shows a time or runs a timer; installing it after navigation misses the timers the page already set
- Every network call the test does not own is a route: `page.route()` with a recorded or synthetic response, and a `page.on('request')` assertion that nothing reached the real world. A stub that lets a request through silently gives a green run against nothing
- A fixed viewport, locale and timezone in `use`: a date rendered in the runner's timezone is a test that breaks when the runner moves
- `test.describe.configure({ mode: 'serial' })` makes tests depend on each other on purpose, and a failure in the first fails all; it is a declaration of shared state, not a fix for it. Fully parallel by default, and a test that only passes serially has found a shared resource
- One `webServer` in the config, with `reuseExistingServer: !process.env.CI`, so the tests run against a server started the way the config says, every time

## For `tests/defects.sh`

The tests here are the slow layer, so a defect list for them is short and aimed at the behaviours only a browser can prove: a guard in the front end that hides an action, a redirect after a submit, a field's validation. The edits go in the application's source, never in the page objects or fixtures, which `falsify` refuses as test files. `-b 'npx tsc --noEmit'` for a TypeScript application, so an edit the type checker rejects is `unusable` rather than credited. A defect that survives here usually means the assertion was `toBeVisible()` on something that was visible either way; the fix is an assertion on the outcome, not on the presence of a widget

## There is no marker set, and that is the finding

No `markers/playwright.txt` ships, and not for want of looking. Playwright 1.61 was run through every shape that exits 0 while answering about less than it appears to, and none of them leaves a line a marker could match:

- **`--pass-with-no-tests`, with nothing to run.** Output is empty. Not a warning, not a summary — nothing at all, and exit 0. There is no text to match, because there is no text
- **A `test.only` left in a file.** The run prints `Running 1 test` and `1 passed`, exits 0, and says nothing whatever about the tests it dropped. Both lines are what a genuinely one-test run prints
- **Every test skipped.** `2 skipped`, exit 0. The only line that names it is the skip count, and a healthy suite skips tests for a browser it does not have on this runner — a marker there would cry wolf

What does go red on its own is worth knowing: a `--grep` that matches nothing is `Error: No tests found` and exit 1, without any flag being set

So the guards here are the config and not the log. `forbidOnly: true` turns a stray `test.only` into a failure, and it is the single most valuable line in a Playwright config. Never pass `--pass-with-no-tests` in CI: it exists to make a pipeline green and does exactly that. This is the shape of ecosystem the marker idea does not reach, and saying so is more use than an invented set
