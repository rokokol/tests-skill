# A test that disagrees with itself

An unstable test is one that passes and fails on the same code. It is worse than a missing
test, because it teaches everyone that red means "press the button again" — and once that
habit exists, a genuine failure gets rerun too.

## Prove it before you chase it

One red run is not evidence of instability; it may be a real bug that only your machine's
timing exposes. `t.sh flaky 20 -- <cmd>` runs the same command twenty times and reports how
many runs disagreed with the first, pointing at the first divergent log. It keeps no
history and computes no statistics — it exists to turn "it failed once, probably nothing"
into a fact, so the cause can be found.

If twenty runs agree, the instability is elsewhere: in the CI machine's load, in the order
the suite happens to run in, in a neighbouring test's leftovers. Reproduce it there —
`--random-order`, `-p no:randomly`, a single worker, the same container — rather than
concluding the test is fine.

## The causes, roughly in order of frequency

- **A sleep standing in for a condition.** `sleep 0.5` then assert. It passes until the
  machine is loaded. Wait for the condition — poll for the file, the port, the log line,
  the state — with a timeout that fails loudly.
- **Shared state between tests.** The same temporary directory, the same database row, the
  same fixed port, the same environment variable, a module-level cache. It passes alone
  and fails in parallel, or passes in one order and fails in another. Give each test its
  own, and let the framework allocate ports rather than hardcoding them.
- **Order dependence.** One test leaves state another test happens to need. Randomise the
  order in CI so this fails immediately rather than on the day someone adds a test.
- **Real time and real dates.** `datetime.now()`, timezones, a test that breaks at
  midnight or in the last week of a month, a timeout tuned to one machine. Inject the
  clock.
- **Unordered things compared as ordered.** Dictionary iteration, set serialisation,
  filesystem listing order, concurrent log lines. Sort before comparing, or compare as
  sets.
- **The network.** Any test that resolves a name or fetches a URL will fail on someone's
  train. That is not instability to be fixed in the test; it is a test that belongs
  outside the gate.
- **Genuine concurrency bugs in the code under test.** The most valuable finding here: the
  test is right and the code has a race. An automatic retry hides exactly this one.

## The policy

**Never auto-retry inside the gate.** `--reruns`, `retries: 2`, `nextest --retries`, a
`for` loop around the suite: each converts a real race into a green run. A gate whose green
is produced by repetition answers a question nobody asked.

When a test is unstable and cannot be fixed today:

1. **Take it out of the gate explicitly** — skip it, mark it, move it to a suite that does
   not block — so the gate goes back to meaning something.
2. **Record the debt where it is visible**: a dated entry naming the test, what is
   suspected, and who is on the hook. A quarantine with no name and no date is a deletion
   that still costs CI minutes.
3. **Give it a deadline.** Quarantine is a loan. A test quarantined for a year should be
   deleted, and the deletion noted — an honest gap is better than a comforting one.

Deleting an unstable test is a legitimate outcome, provided it is deliberate. What is not
legitimate is leaving it in the gate while everyone silently reruns.

## The one place a retry is defensible

A check whose subject is genuinely outside the repository — a package mirror, a CDN, a
live site — may retry, because its failures are about someone else's afternoon. But such a
check should not have been gating a pull request in the first place; it belongs to the
weekly drift detector. That split is the [ci](https://github.com/rokokol/ci-skill) skill's
gate-versus-detector rule, and it is the real fix for most "flaky CI".
