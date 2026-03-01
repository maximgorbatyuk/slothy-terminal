import XCTest
@testable import SlothyTerminalLib

@MainActor
final class TerminalSurfaceRegistryTests: XCTestCase {
  private var registry: TerminalSurfaceRegistry!

  override func setUp() {
    super.setUp()
    registry = TerminalSurfaceRegistry()
  }

  override func tearDown() {
    registry = nil
    super.tearDown()
  }

  func testRegisterAndLookup() {
    let tabId = UUID()
    let surface = MockInjectionSurface()

    registry.register(tabId: tabId, surface: surface)

    XCTAssertNotNil(registry.surface(for: tabId))
  }

  func testUnregisterReturnsNil() {
    let tabId = UUID()
    let surface = MockInjectionSurface()

    registry.register(tabId: tabId, surface: surface)
    registry.unregister(tabId: tabId)

    XCTAssertNil(registry.surface(for: tabId))
  }

  func testWeakReferenceCleanup() {
    let tabId = UUID()

    /// Register a surface that will be deallocated.
    autoreleasepool {
      let surface = MockInjectionSurface()
      registry.register(tabId: tabId, surface: surface)
      XCTAssertNotNil(registry.surface(for: tabId))
    }

    /// Surface should be deallocated, lookup returns nil.
    XCTAssertNil(registry.surface(for: tabId))
  }

  func testRegisteredTabIdsReturnsOnlyLiveEntries() {
    let liveId = UUID()
    let deadId = UUID()
    let liveSurface = MockInjectionSurface()

    registry.register(tabId: liveId, surface: liveSurface)

    autoreleasepool {
      let deadSurface = MockInjectionSurface()
      registry.register(tabId: deadId, surface: deadSurface)
    }

    let ids = registry.registeredTabIds()
    XCTAssertTrue(ids.contains(liveId))
    XCTAssertFalse(ids.contains(deadId))
  }

  func testRegisterSameIdOverwrites() {
    let tabId = UUID()
    let surface1 = MockInjectionSurface()
    let surface2 = MockInjectionSurface()

    registry.register(tabId: tabId, surface: surface1)
    registry.register(tabId: tabId, surface: surface2)

    let retrieved = registry.surface(for: tabId) as? MockInjectionSurface
    XCTAssertTrue(retrieved === surface2)
  }

  func testRemoveAllClears() {
    let id1 = UUID()
    let id2 = UUID()
    registry.register(tabId: id1, surface: MockInjectionSurface())
    registry.register(tabId: id2, surface: MockInjectionSurface())

    registry.removeAll()

    XCTAssertTrue(registry.registeredTabIds().isEmpty)
    XCTAssertNil(registry.surface(for: id1))
    XCTAssertNil(registry.surface(for: id2))
  }

  func testLookupUnregisteredReturnsNil() {
    XCTAssertNil(registry.surface(for: UUID()))
  }
}
