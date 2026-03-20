import Testing

@testable import SlothyTerminalLib

@Suite("GhosttySurfaceMetricsCache")
struct GhosttySurfaceMetricsCacheTests {
  @Test("First size update is applied and duplicate is skipped")
  func sizeDeduplication() {
    var cache = GhosttySurfaceMetricsCache()
    let first = cache.shouldApplySurfaceSize(width: 800, height: 600)
    let duplicate = cache.shouldApplySurfaceSize(width: 800, height: 600)
    let changed = cache.shouldApplySurfaceSize(width: 801, height: 600)

    #expect(first)
    #expect(duplicate == false)
    #expect(changed)
  }

  @Test("Zero sizes are always ignored")
  func zeroSizesIgnored() {
    var cache = GhosttySurfaceMetricsCache()

    #expect(cache.shouldApplySurfaceSize(width: 0, height: 600) == false)
    #expect(cache.shouldApplySurfaceSize(width: 600, height: 0) == false)
  }

  @Test("Content scale is deduplicated with tolerance")
  func contentScaleDeduplication() {
    var cache = GhosttySurfaceMetricsCache()
    let first = cache.shouldApplyContentScale(x: 2.0, y: 2.0)
    let duplicate = cache.shouldApplyContentScale(x: 2.0, y: 2.0)
    let withinTolerance = cache.shouldApplyContentScale(x: 2.00001, y: 2.0)
    let changed = cache.shouldApplyContentScale(x: 2.1, y: 2.0)

    #expect(first)
    #expect(duplicate == false)
    #expect(withinTolerance == false)
    #expect(changed)
  }

  @Test("Reset clears cached size and scale state")
  func resetClearsCachedState() {
    var cache = GhosttySurfaceMetricsCache()
    _ = cache.shouldApplySurfaceSize(width: 800, height: 600)
    _ = cache.shouldApplyContentScale(x: 2.0, y: 2.0)

    cache.reset()

    let sizeAfterReset = cache.shouldApplySurfaceSize(width: 800, height: 600)
    let scaleAfterReset = cache.shouldApplyContentScale(x: 2.0, y: 2.0)

    #expect(sizeAfterReset)
    #expect(scaleAfterReset)
  }
}
