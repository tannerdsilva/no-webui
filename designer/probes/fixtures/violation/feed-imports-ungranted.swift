// deliberate-violation fixture for the t2.6 capability lint probe.
// this file is NOT part of any SwiftPM target — it lives under
// designer/probes/fixtures/ and exists only to prove the lint's exact
// error message and non-zero exit.

@HotView("feed", imports: "surface_acquire")
struct Feed: HotView {
    typealias State = FeedState
    typealias Action = FeedAction
}
