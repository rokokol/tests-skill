# TypeScript

Everything in [node.md](node.md) applies to running the tests. What is specific to TypeScript is that a whole class of failure lives in a step the test runner does not perform.

## The type check is a separate check

Most runners — vitest, jest with `esbuild`/`swc`, `tsx`, `ts-node --transpile-only` — **strip types without checking them**. That is deliberate and fast, and it means a suite can be entirely green while `tsc` has three errors. If your gate runs only the tests, type errors reach production.

```sh
t.sh run -- npx tsc --noEmit
t.sh run -- npx vitest run --passWithNoTests=false
```

Two commands, both gating. In `tsconfig.json`, the settings that decide whether the check is worth running:

- `"strict": true` — without it, `null` and `undefined` are assignable to everything and the checker agrees with almost anything.
- `"noUncheckedIndexedAccess": true` — makes `arr[i]` possibly-undefined, which is where runtime `TypeError`s come from.
- `"noImplicitOverride"`, `"exactOptionalPropertyTypes"` — cheap, and each closes a real gap.
- `"skipLibCheck": true` is a pragmatic exception, not a general licence to skip.

## Green that lies

| Line | What happened |
|---|---|
| tests green, `tsc` never run | the runner stripped types; nothing checked them |
| `@ts-ignore` / `@ts-expect-error` | a silenced error; `expect-error` at least fails when the error goes away |
| `as any`, `as unknown as T` | the check was opted out of at exactly the interesting point |
| `error TS2307: Cannot find module` | a path alias works in the runner's resolver and not in `tsc`'s |
| a `.d.ts` disagreeing with the runtime | nothing checks a hand-written declaration against reality |
| a test asserting `expect(x).toBeDefined()` on an `any` | the assertion is vacuous |

`any` deserves its own attention: once a value is `any`, every operation on it type-checks, so a test built on `any` fixtures asserts far less than it appears to. `@typescript-eslint` with `no-unsafe-*` reports where that is happening.

## Testing the types themselves

Where a type is the product — a public API, a generic helper — assert on it, with `expectTypeOf` (vitest), `tsd`, or `@ts-expect-error` on a call that must not compile. `@ts-expect-error` is the falsifiable one: it fails when the error stops occurring, so it cannot rot into a comment.

## For `tests/defects.sh`

Always run with `-b 'npx tsc --noEmit'`. Without the build phase, an edit the type checker rejects looks exactly like a defect the tests caught, and the report credits coverage that does not exist. Edits that stay type-correct: a narrowed union widened back, a guard returning a constant, an `??` replaced by `||`, a `filter` predicate replaced by `() => true`.
