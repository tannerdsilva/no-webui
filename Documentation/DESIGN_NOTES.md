# Design notes

Decisions that were made on the strength of a measurement, with the measurement
written down. An undocumented trade is the thing these notes exist to remove.

---

## Typed view trees: `TupleView` vs `[any View]` erasure

**Status:** adopted (W2.5, measured 2026-10-09). Migrate containers one per task,
each behind the byte gate.

### The question

Every container in the framework took `@ViewBuilder content: () -> [any View]`:
each child was boxed into an existential and appended to an array before anyone
could render it. `Sources/` carried 110 sites spelling `[any View]`. The claim in
the architecture notes was "a typed view tree" — and the erasure made that claim
false. Either the typing was worth paying for, or the claim had to go.

### The method

A throwaway branch added a second result builder (`TypedViewBuilder`) and used it
for **one** container, `VStack`. Every other container kept the erasure builder,
which is what makes the migration incremental: two builders never contend in one
overload set, so a container can switch on its own.

- children became a pack: `buildBlock<each C: View>(_ component: repeat each C) -> TupleView<repeat each C>`
- the one erasure left is `buildArray` — a `for` loop's element type is a value,
  not a position — and `[any View]` is made a `View` so a loop's output can sit
  beside typed siblings
- `if`/`else` arms of different types held as `ConditionalContent<T, F>`, and
  `Optional: View where Wrapped: View` for `if` without `else`

Two findings came out of writing it, both recorded because both are the kind of
thing that costs a day to rediscover:

1. **Declaring any `buildExpression` suppresses the identity path.** A builder
   with only `buildExpression([any View])` turns every plain `Heading(…)` into
   `cannot convert value of type 'Heading' to expected argument type '[any View]'`.
   The fix is one generic rule: `buildExpression<V: View>(_ expression: V) -> V`.
2. **SwiftUI's ten-child ladder is a wall, not boilerplate.** The first attempt
   capped at ten and this tree has a 28-child block in the showcase. Variadic
   generics (`repeat each`) remove the cap in a single overload, so the prototype
   carries no ladder at all.

### The numbers

Measured on an Apple Silicon Mac, 2026-10-09. Baseline is the committed tree;
prototype is the same tree plus the typed `VStack`. Both release builds used a
fresh build path (`.build/rb-base`, `.build/rb-proto`) so the build time is a
clean full build.

| metric | erasure (baseline) | typed (prototype) | delta | criterion | met |
|---|---|---|---|---|---|
| clean `swift build -c release` | 162.802 s | 161.679 s | −0.69 % | ≤ +25 % | yes |
| `WebUIShowcase` binary | 12 543 104 B | 12 745 472 B | +1.61 % | ≤ +5 % | yes |
| render p50, 200 iterations | 2.227 ms | 2.216 ms | −0.49 % | ≤ +2 % | yes |
| emitted page bytes | 167 300 | 167 300 | identical | identical | yes |

Render time is the median of three runs each (baseline 2.182 / 2.227 / 2.239 ms;
prototype 2.216 / 2.213 / 2.274 ms). The difference is inside run-to-run noise:
**the typed tree is not faster.** What it buys is the compile-time guarantee the
architecture notes already claim, at a 1.6 % binary cost and no measurable runtime
cost. That is the trade, stated rather than assumed.

The 167 300-byte page was also diffed pre/post: identical once the framework's own
volatile fields are masked (the CSRF token, and a `data-optimistic` key-order
non-determinism that two runs of one binary also exhibit).

### Reproducing it

The harness is a `--bench-render N` mode added to `Sources/WebUIShowcase/main.swift`
on the throwaway branch: warm once, then time N renders of `renderShowcase()` and
print p50/p95/min plus the byte count. Twelve lines; re-add if a container
migration needs a render-cost gate of its own.

### What follows

`ARCHITECTURE.md` may keep the "typed view tree" claim. Containers migrate one per
task — each carrying the byte gate and the four criteria above — rather than in one
all-or-nothing pass.