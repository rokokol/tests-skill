# Layers: what each kind of test can and cannot answer

This is the periphery, and the honest answer is that the right mix depends on what breaking would cost you. What is *not* a matter of taste is knowing which question each layer answers and which it silently leaves open — a suite is dangerous exactly where everyone believes it covers something it does not.

Read this as a menu with prices, not a checklist.

## The layers

**Unit — one function, no I/O.** Answers: does this logic do what it claims for the inputs I thought of, including the ugly ones. Cheap, fast, precise about *where* the fault is. Cannot answer: whether the pieces fit together, or whether the assumption baked into the function matches reality. A suite that is only units passes while the program is broken.

**Seam — the code under test, with what it talks to replaced by something you control.** The dependency becomes a stub that records calls or replays a canned answer. Answers: does the code ask for the right thing, in the right order, and behave correctly when the answer is an error, a timeout, or empty. Cannot answer: whether the real dependency behaves like your stub. That gap is where the production bug lives. Keep the stub honest — assert that it is actually the thing being reached, because a stub the code never resolves gives you a green run against nothing.

**Golden — the output compared against a stored expected file.** Answers: has the shape of the output changed, in full, including whitespace and ordering that assertions never bother to cover. Excellent for renderers, formatters, serialisers, generated config and CLI help. Cannot answer: whether the output was ever *right*. A golden file records what the code did on the day it was written. Two rules keep it useful: regenerating must be one command (`--update`, `UPDATE_GOLDEN=1`), and a regenerated file must be read in the diff like code — an unreviewed regeneration turns the bug into the expectation.

**Contract — the boundary between two components, asserted from both sides.** The consumer writes down what it sends and what it needs back; the provider replays that against itself; a broker holds the current agreement and `can-i-deploy` refuses a release that breaks one. Answers: do these two still agree about the shape they exchange, without running both. Cannot answer: anything about behaviour beyond the shape. Keep contracts thin — status, presence, types, formats — because a contract that pins values is a golden file of somebody else's data.

**Property — one claim, checked against inputs you did not write.** A generator produces inputs, a property states what must hold for all of them — a roundtrip through encode and decode returns the input, a sort is idempotent, a parser rejects what a printer never emits, a fast path agrees with a slow one — and the framework shrinks the first counterexample to the smallest one it can find. Answers: does the claim hold beyond the cases somebody thought of. Cannot answer: anything the property does not state. Two shapes of property assert nothing — a tautology, where the property is computed by the code under test, and a vacuity, where the generator's filter discards almost every input so the few that pass are trivial; embed the constraint in the generator instead of filtering. Assert the strongest property the code supports: "does not crash" is the weakest, a roundtrip or an oracle the strongest.

**Fuzz — the same, for a parser, with a machine choosing the inputs by coverage.** libFuzzer, AFL, `cargo-fuzz`, Atheris drive an input past every branch they can reach and keep the ones that found a new one, with a sanitizer underneath. Answers: is there an input that crashes, corrupts memory or hangs. Cannot answer: whether the output is right. It runs for hours, not in the gate; the crash it finds becomes a regression test that does.

**Environment — the real thing, running.** The program started for real, the installer run in a container, the service driven end to end, the compositor actually wearing the shader. Answers: the only question that matters to a user — does it work where it is used. Cannot answer: cheaply or often. It is slow, it needs hardware, a display, a network or root, and it fails for reasons unrelated to your change. So it typically runs by hand before a release, or on a schedule, rather than gating every change. Two properties make it bearable: it must restore whatever it touched, and it must say plainly what it could not check.

## Choosing

- **Put the weight where a failure would be expensive**, not where tests are easy to write. Counting tests optimises for the easy layer.
- **Each layer earns its place by answering a question the layer below cannot.** Three layers asserting the same thing cost three times as much and fail together.
- **Anything that reaches outside the repository does not gate a change.** Mirrors, CDNs, live sites: their failures are about someone else's uptime. They belong to a scheduled drift detector — the [ci](https://github.com/rokokol/ci-skill) skill's gate-versus- detector rule.
- **A layer nobody runs is worse than none.** It costs maintenance, and its existence is used as an argument that the area is covered.

## Fakes: what each one costs

Every fake is an untested claim that the real thing behaves as you have written it. That is sometimes an excellent trade and sometimes the entire bug.

- **Worth faking:** the clock, randomness, the network, paid APIs, hardware you do not have in CI, anything slow enough to change how often the suite is run, and anything whose failure modes you need to produce on demand.
- **Think twice:** your own modules. A fake of your own code freezes today's behaviour into another file, and the two drift.
- **Prefer a seam you own.** A narrow interface with a real implementation and a fake one is testable without patching internals; heavy monkey-patching couples the test to the implementation's shape, so refactoring breaks tests that should not have noticed.
- **Whatever you fake, test the real thing somewhere.** One environment-layer test that exercises the real dependency is what stops the whole faked stack from being fiction.
- **Real first, then the smallest fake that works.** Run the test against the real dependency once, see what it actually needs, and fake at that level; a fake designed from the imagined need is a fake of a different program. The ranking, by how much a green run then proves: the real thing, a fake with the real one's behaviour, a stub with canned answers, a mock that records calls.
- **A fake that lets reality through is a lie of a special kind.** A network stub that forwards an unstubbed request, a filesystem fake with a real directory underneath: the test is green against the world, and nobody configured the world. Unhandled requests are errors.

## The tests that lie by shape

Falsification catches the test that cannot fail. These are the shapes that fail for the wrong reasons or pass for none, and only reading the test catches them:

- **The change-detector test** asserts the implementation's shape — this method was called with these arguments, in this order — rather than its result, so it fails on every refactor and passes on every bug. Test state, not interactions; test through the public surface, not the private one; a test that has to change when the requirements did not is asserting structure.
- **Logic in the test.** A loop, a branch, a computed expected value: the test now has its own bugs, and its own bug can agree with the code's. Straight-line code, literal expected values, obvious to a reader.
- **The mock that is the subject.** An assertion on the mock's own behaviour — that the fake returned what it was told to return — tests the test framework. And a mock whose setup is longer than the test is the integration test you were avoiding, written badly; the same for a fake that omits the fields downstream code reads, which is green until the real object arrives.
- **Methods that exist only for tests.** A `reset()` or a `setInternalState()` on a production class is a test reaching into the implementation, and it stays in the shipped code.
- **Too dry.** A test is read on its own when it fails, so the values it uses are written in it, even when three tests then share a line; the shared fixture that hides the value is the one nobody can debug at two in the morning.
- **The vacuous assertion.** `assert result` on an object that is always truthy, `expect(x).toBeDefined()` on an `any`, a snapshot that was regenerated instead of read. A snapshot is a golden file: `--ci` so an unknown one fails rather than being written, inline where it is small, and the regenerated diff read like code.

Kent Beck's twelve properties of a test are the vocabulary for a review of this kind — *behavioral*, which falsification measures; *structure-insensitive*, which the change-detector violates; *specific*, which the failure message decides; *isolated*, *deterministic*, *fast* — and the honest observation that some of them pull against each other, so a suite chooses. The sources are in [sources.md](sources.md).

## Coverage

A percentage measures which lines were executed, not which behaviours were checked. It is easy to reach a high number with tests that assert nothing, and the last stretch is usually bought with tests written to move the number.

Use it as a map: uncovered error branches and uncovered new code are worth looking at. Do not use it as a gate — the question "would the suite notice if this broke?" is answered by [falsifiability.md](falsifiability.md), and that answer is the one worth having.
