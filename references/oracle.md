# What a test compares against

The expected side of an assertion is an oracle: it says what correct looks like. When the oracle is a copy of the code's output, or of a value the code already holds, the repository keeps the same fact twice, and the copies drift apart on the first harmless edit. The test then fails for a reason nobody cares about, gets updated by pasting the new output, and from that moment checks nothing, because whatever the code prints becomes the new expectation

## The rule

- **Assert what the behaviour promises.** Name the facts a caller depends on — which unit started, which value moved, what is present and what is absent — and check those. The rest of the output is the code's to change
- **Do not restate a tuning constant.** A threshold, a delay, a step or a size lives in one place in the code. A test that repeats it is a second copy, and a test built around the exact boundary fails on every retune. Test on each side of the boundary with inputs well clear of it, or read the constant from the code under test
- **Derive the expected value from the input, not from the output.** A fixture states the input; the expected value follows from it by the rule under test. `expected = input_total - input_free` checks the arithmetic; `expected = "6.0"` pasted from a run only checks that nothing changed
- **Compare exactly where the exact form is the contract.** An exit code, a line another program parses, a file format read back from disk, a protocol message: there the bytes are the behaviour, and a whole-line or byte comparison is the right check, as [falsifiability.md](falsifiability.md) says for generated text
- **Prove it in both directions.** Break the behaviour and the test goes red; reword or reorder the output without changing the behaviour and it stays green. The first direction is the usual falsification pass; the second is what separates a behaviour test from a snapshot of today's output

## Examples

A script that rotates a monitor through a compositor's command line, run against a stub that logs each call

```sh
# A copy of the output: fails when the call is respaced or its fields reordered
is "rotates" 'hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1.0, transform = 1 })' "$(cat log)"

# The behaviour: the monitor turned, and its own mode and position were kept from the stub's input
is "rotates" "1" "$(transforms DP-1)"
logged "keeps the monitor's mode and position" '"DP-1"' "$STUB_MODE" "$STUB_POSITION"
```

A status line for a bar, fed a copy of `/proc/meminfo` with 8 GiB total and 2 GiB available

```sh
# A copy: fails when the icon, the unit or the spacing changes
is "memory" '{"text":"6.0/0.8Gb 🧠"}' "$(memory-status)"

# The behaviour: used memory is shown, free memory is not
text=$(memory-status | jq -r .text)
grep -q '6\.0' <<<"$text" && ! grep -q '2\.0' <<<"$text"
```

A touch handler with a tap slop of 8 px

```python
# A restated constant and a test at the exact edge: both break on a retune to 10 px
assert TAP_SLOP == 8
assert handle(move_by=9) == "scroll"

# Each side of the boundary, well clear of it
assert handle(move_by=0) == "click"
assert handle(move_by=TAP_SLOP * 10) == "scroll"
```

A command whose output another tool parses

```sh
# Here the exact form is the contract, so the exact comparison is right
[ "$(tool status --json | jq -c .)" = '{"state":"on"}' ]
[ "$(tool bad-args; echo $?)" = 2 ]
```

## When the copy is the point

A golden file is a deliberate copy, kept for output whose whole shape matters and cannot be reduced to facts — a rendered document, a generated config, a formatter's result. It earns its place only with a reviewed diff on every update and a regeneration command beside it; without those it is the snapshot this page warns about. [layers.md](layers.md) weighs when one is worth keeping
