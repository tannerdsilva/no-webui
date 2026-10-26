# Design notes

Decisions that were made on the strength of a measurement, with the measurement
written down. An undocumented trade is the thing these notes exist to remove.

---

## Typed view trees: `TupleView` vs `[any View]` erasure

**Status:** adopted (W2.5, measured 2026-10-09). Migrate containers one per task,
each behind the byte gate. **Completed 2026-10-25** — all 26 container primitives
and `ForEach` migrated in two slices; see the follow-up at the end of this note
for the measurement W2.5 was missing.

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

---

## Follow-up (2026-10-25): the erasure that actually cost

**Status:** shipped. 26 container primitives plus `ForEach`.

### What W2.5 missed

The prototype typed **one container** and measured **the showcase page**. On that
corpus the erasure is free, so the note concluded "the typed tree is not faster"
and proposed migrating containers one per task. That framing is what stalled the
arc: the cost was never at literal arity.

The cost is **per element**. Measured on a 2000-row render (release, the same
trees, byte-identical output):

| shape | before | after | gain |
|---|---:|---:|---:|
| 2000-row list, per row | 366 ns | **165 ns** | **2.21×** |
| 10000-row list | 3.674 ms | **1.639 ms** | **2.24×** |
| 12 heterogeneous literal children | 3.9 µs | 2.1 µs | 1.86× |
| showcase page (168 671 B) | — | — | unchanged |

Two things follow. `ForEach`'s per-element `[any View]` was the expensive site and
it is invisible on a literal-heavy page — the page measurement could not have
found it. And typing *containers* alone buys ~1.9× on a tree too small for the
page to notice, which is why W2.5 saw noise.

### The rule the split settles on

`[any View]` has exactly one capability the typed tuple lacks: it can answer
`count`, `isEmpty`, `enumerated`. So the array is granted only to the types that
inspect arity — the design-system components (20+ sites) — and withdrawn from
everything that only forwards children. Two builders, chosen by the parameter's
attribute; a call site never names one:

- `@ViewBuilder` → `[any View]` (components).
- `@ElementBuilder` → `TupleView` / `OptionalView` / `EitherView` /
  `RepeatedView` / `ErasedViews` (primitives, `ForEach`).

`Group` keeps its name and loses its array: it is now the typed no-wrapper
grouper, and `ElementGroup` is how a setup-time walk (the chart resolving marks)
sees through the combinators.

### The four criteria, re-run

| metric | before | after | delta | criterion | met |
|---|---|---|---|---|---|
| clean `swift build -c release` | 181.11 s | 183.42 s | +1.28 % | ≤ +25 % | yes |
| `WebUIShowcase` binary | 13 406 512 B | 13 728 448 B | +2.40 % | ≤ +5 % | yes |
| row render (2000) | 0.731 ms | 0.331 ms | −54.8 % | — | yes |
| emitted page bytes | 168 671 | 168 671 | identical | identical | yes |

Both builds were cold, in fresh copies (`.build` absent), same toolchain.

### What the migration actually cost

Not call-site churn: all 54 `ForEach` sites and all 442 container closures
compiled unchanged. Packs absorb any arity, so `Div { a; b }` never had to wrap.
The real work was four things the note did not anticipate:

1. **The builder must be a superset.** A block whose expression is an array
   (`Div { someArray }`) needs `buildExpression` overloads for `[C]` and
   `[any View]`, or every such site fails. `[any View]` becomes `ErasedViews`.
2. **`TupleView` is not free.** Wrapping a single child in a tuple cost ~30 ns/row
   (12 %) until a single-element `buildBlock<C: View>(_ c: C) -> C` overload
   skipped the wrapper for the dominant one-view body.
3. **A runtime type walk breaks.** `Chart.resolve` found marks with `as? Group`;
   once elements became tuples, every mark vanished. `ElementGroup` is the fix,
   and it is now the protocol a walk should use.
4. **`<li>` is per child.** `UnorderedList`/`OrderedList` genuinely need the
   child set, so they walk `ElementGroup` at render time — the one place the old
   array semantics had to be reproduced deliberately rather than inherited.

Naming: the prototype's `TypedViewBuilder` was never committed. The shipped name
is `ElementBuilder` — HTML's own word, and it keeps "views" for the erased
collection and "elements" for the typed tree.

### Reproducing it

`~/.hermes/profiles/swift-dev/cache/scratch/pack-probe` (a path-dependency probe,
not in this repo): `swift run -c release probe` renders the same six trees through
the framework, a hand-written generic `ForEach`, a hand-written generic `Div`, and
a pack-based `VStack`, asserting byte identity before timing.