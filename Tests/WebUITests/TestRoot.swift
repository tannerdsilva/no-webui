import Testing

// the root of this target's serialized tree: a suite nests here through an
// `extension` block in its own file, so the trait serializes that subtree.
//
// `.serialized` covers a suite's entire subtree — nested suites included — but
// has no effect on *sibling* suites, so nesting under one root is the only
// code-level way to serialize a target. (the `--no-parallel` flag is the only
// other way, and it is not expressible in source.)
//
// this is a structure rule, not a workaround: a suite that renders is easiest to
// reason about when nothing else is rendering beside it. do not re-derive a bug
// from it — a stale build tree has twice presented here as a "concurrency"
// symptom (a signal exit, and a corrupted attribute value no source emits), and
// both vanished after `swift package clean`.
@Suite("WebUI tests", .serialized)
struct WebUITestRoot {}
