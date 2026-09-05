# Test first, and watch the red

Writing the test first is not a moral position; it buys two specific things that are hard
to get any other way.

- **A test written after the code describes the code.** It is written by someone who has
  just read the implementation, so it asserts what the implementation does — including the
  bug. Written first, it asserts what the caller needs, which is a different sentence.
- **A test that has never been red proves nothing.** Until you have seen it fail, "it
  passes" is equally consistent with "it asserts nothing", "it was never collected", and
  "the assertion is inside an `if` that is false". Watching the red is what separates those.

## The loop

1. **Red.** Write one test for one behaviour. Run it. It must fail, and the failure
   message must be the one you expected — `AssertionError: expected 3, got 2`, not
   `ImportError` or `fixture 'client' not found`. A test failing for a boring reason has
   not tested anything yet.
2. **Green.** Write the smallest code that makes it pass. Resist writing the next three
   things you know are coming; they get their own cycles and their own red.
3. **Refactor.** Now that the behaviour is pinned, clean up. The suite stays green
   throughout, and nothing in it changes — a test edited to keep passing is not a test.
4. **Repeat**, one behaviour at a time, keeping a todo item per cycle so the loop survives
   an interruption.

Then, separately: **falsify**. The loop proves each test could fail on the day it was
written. It does not prove the suite still notices after six months of refactoring, and it
says nothing about the guards nobody wrote a test for. That is a different pass with a
different tool — see [falsifiability.md](falsifiability.md).

## What a good test looks like here

- **One behavioural claim per test**, named as the claim:
  `silence_before_the_first_word_is_trimmed`, not `test_trim_2`.
- **The failure message identifies the fault** without opening the test. If it says
  `assert False`, the assertion is written wrong.
- **Real code by default.** Every fake is a claim that the real thing behaves the way your
  fake does, and that claim is not tested anywhere. Fake at the edges you do not own —
  network, clock, hardware, the filesystem when it matters — and think twice everywhere
  else. See [layers.md](layers.md) for what each choice stops proving.
- **Deterministic by construction.** Fixed clock, fixed seed, fixed ordering, its own
  temporary directory and its own port. See [flaky.md](flaky.md).
- **Failure paths get tests too.** The error branch is where the untested code lives,
  because it is the branch nobody exercises by hand.

## Where test-first legitimately does not pay

Stating this plainly is what keeps the rest of the rule credible.

- **Exploration you intend to throw away.** Spiking to learn an API is not development;
  when you know the shape, delete the spike and start the loop for real. Keeping the spike
  "as a base" is how untested code enters a repository wearing a hat.
- **Pure refactoring**, where behaviour must not change. The existing tests are the
  harness; if they are too thin to make the refactor safe, that gap is itself a red test
  to write first.
- **Code whose behaviour you cannot yet name.** If you cannot write the assertion, you do
  not know what you are building, and the honest first step is to find out — not to write
  an implementation and label whatever it does as correct.

None of these excuses skipping the red. They only move when it happens.

## The rationalisations

Each of these has been said before shipping something that did not work: "the test would
just repeat the implementation", "this is too simple to break", "I will add tests after",
"the type system already guarantees it", "it is only a config change", "I already ran it
by hand once". They are worth reading as a prompt to spend the extra two minutes.
