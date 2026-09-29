# Deviations

Permanent choices the gate makes against the obvious, cheaper route, with the trade behind each. Like `PITFALLS.md`, this is a maintainer's note about the gate and the harness themselves, not part of the standard they describe

---

## A planted row's half decides which half proves it

**Where:** `plant HALF NAME ...` in `check.sh`, and the copy each planted row runs

**Why it differs from the obvious route:** the obvious form is a filter only: the copy runs with the mode of the outer run. Here the copy runs the half the row names, which is where most of the gate's time goes

**What returning to the obvious route breaks:** under `all`, a row labelled `lint` is equally proven by the behaviour half, so a row carrying the wrong half passes on the other half's work instead of failing with "the copy did not fail at all"

---

## Every copy builds its own fixtures

**Where:** the throwaway git repositories each planted copy builds for itself

**Why it differs from the obvious route:** rebuilding the same fixtures in every copy looks like the obvious saving to cut, and it is not one: a timing shim over `git` counted 246 calls totalling 1010 ms in a 9.7 s copy, under 10 percent, and most of those calls are the checks themselves rather than fixture construction

**What returning to the obvious route breaks:** the isolation. The repository has one `t.sh`, but every planted copy carries its own deliberately broken one, and the table includes "a falsify that does not put the source back" and "bisect refuses to start on a working tree it would trample". A fixture directory shared between copies is a fixture those copies are written to abuse
