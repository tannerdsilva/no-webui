// marker-form robustness fixture: every accepted imports: spelling.
@HotView("a1", imports: ["surface_acquire", "clock"])
struct A1: HotView {}

@HotView("a2", imports: [.surface_acquire, .clock])
struct A2: HotView {}

@HotView("a3", imports: [SurfaceAcquisition.self, ClockCapability.self])
struct A3: HotView {}

@HotView("a4", imports: "surface_acquire", budget: IslandBudget(maxBytes: 100))
struct A4: HotView {}
