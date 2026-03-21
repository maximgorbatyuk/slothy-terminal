import XCTest
@testable import SlothyTerminalLib

final class RecentFoldersManagerTests: XCTestCase {
  private var manager: RecentFoldersManager!
  private var testDefaults: UserDefaults!
  private let testSuiteName = "RecentFoldersManagerTests"

  override func setUp() {
    super.setUp()
    /// Use a separate UserDefaults suite for testing
    testDefaults = UserDefaults(suiteName: testSuiteName)
    testDefaults?.removePersistentDomain(forName: testSuiteName)

    /// Note: In a real scenario, we'd inject the UserDefaults into the manager
    /// For now, we test the shared instance behavior
    manager = RecentFoldersManager.shared
    manager.clearRecentFolders()
  }

  override func tearDown() {
    manager.clearRecentFolders()
    testDefaults?.removePersistentDomain(forName: testSuiteName)
    testDefaults = nil
    manager = nil
    super.tearDown()
  }

  // MARK: - Initial State Tests

  func testInitialStateIsEmpty() {
    XCTAssertTrue(manager.recentFolders.isEmpty)
    XCTAssertTrue(manager.entries.isEmpty)
  }

  // MARK: - Add Folder Tests

  func testAddSingleFolder() {
    let url = URL(fileURLWithPath: "/tmp")
    manager.addRecentFolder(url)

    XCTAssertEqual(manager.recentFolders.count, 1)
    XCTAssertEqual(manager.recentFolders.first?.path, "/tmp")
    XCTAssertEqual(manager.entries.count, 1)
  }

  func testAddMultipleFolders() {
    let url1 = URL(fileURLWithPath: "/tmp")
    let url2 = URL(fileURLWithPath: "/var")

    manager.addRecentFolder(url1)
    manager.addRecentFolder(url2)

    XCTAssertEqual(manager.recentFolders.count, 2)
    /// Most recent should be first
    XCTAssertEqual(manager.recentFolders.first?.path, "/var")
  }

  func testAddDuplicateFolderMovesToTop() {
    let url1 = URL(fileURLWithPath: "/tmp")
    let url2 = URL(fileURLWithPath: "/var")
    let url3 = URL(fileURLWithPath: "/usr")

    manager.addRecentFolder(url1)
    manager.addRecentFolder(url2)
    manager.addRecentFolder(url3)

    /// Now add url1 again - should move to top
    manager.addRecentFolder(url1)

    XCTAssertEqual(manager.recentFolders.count, 3)
    XCTAssertEqual(manager.recentFolders.first?.path, "/tmp")
  }

  func testAddDuplicateUpdatesTimestamp() {
    let url = URL(fileURLWithPath: "/tmp")
    manager.addRecentFolder(url)

    let firstDate = manager.entries.first?.lastUsedDate

    /// Small delay to ensure different timestamp.
    Thread.sleep(forTimeInterval: 0.01)
    manager.addRecentFolder(url)

    let secondDate = manager.entries.first?.lastUsedDate

    XCTAssertEqual(manager.entries.count, 1)
    XCTAssertNotNil(firstDate)
    XCTAssertNotNil(secondDate)

    if let first = firstDate,
       let second = secondDate
    {
      XCTAssertGreaterThanOrEqual(second, first)
    }
  }

  func testNoHardCapOnFolderCount() {
    /// Add more than the old limit of 10; all existing folders should be kept.
    for i in 1...15 {
      let url = URL(fileURLWithPath: "/folder\(i)")
      manager.addRecentFolder(url)
    }

    /// All 15 entries are stored (filtered to those that exist on disk).
    /// /folder1../folder15 likely don't exist, so after a reload they'd be pruned.
    /// But in-memory they're all present until the next load.
    XCTAssertEqual(manager.entries.count, 15)
    XCTAssertEqual(manager.recentFolders.first?.path, "/folder15")
  }

  // MARK: - Remove Folder Tests

  func testRemoveFolder() {
    let url1 = URL(fileURLWithPath: "/tmp")
    let url2 = URL(fileURLWithPath: "/var")

    manager.addRecentFolder(url1)
    manager.addRecentFolder(url2)
    manager.removeRecentFolder(url1)

    XCTAssertEqual(manager.recentFolders.count, 1)
    XCTAssertEqual(manager.recentFolders.first?.path, "/var")
  }

  func testRemoveNonExistentFolder() {
    let url1 = URL(fileURLWithPath: "/tmp")
    let url2 = URL(fileURLWithPath: "/var")

    manager.addRecentFolder(url1)
    manager.removeRecentFolder(url2)

    XCTAssertEqual(manager.recentFolders.count, 1)
  }

  func testRemoveFromEmptyList() {
    let url = URL(fileURLWithPath: "/tmp")
    manager.removeRecentFolder(url)

    XCTAssertTrue(manager.recentFolders.isEmpty)
  }

  // MARK: - Clear Tests

  func testClearRecentFolders() {
    let url1 = URL(fileURLWithPath: "/tmp")
    let url2 = URL(fileURLWithPath: "/var")

    manager.addRecentFolder(url1)
    manager.addRecentFolder(url2)
    manager.clearRecentFolders()

    XCTAssertTrue(manager.recentFolders.isEmpty)
    XCTAssertTrue(manager.entries.isEmpty)
  }

  // MARK: - Order Tests

  func testMostRecentFirst() {
    let urls = [
      URL(fileURLWithPath: "/first"),
      URL(fileURLWithPath: "/second"),
      URL(fileURLWithPath: "/third"),
    ]

    for url in urls {
      manager.addRecentFolder(url)
    }

    XCTAssertEqual(manager.recentFolders[0].path, "/third")
    XCTAssertEqual(manager.recentFolders[1].path, "/second")
    XCTAssertEqual(manager.recentFolders[2].path, "/first")
  }

  // MARK: - Time-Based Filtering Tests

  func testFoldersUsedWithinDaysReturnsRecentEntries() {
    let url = URL(fileURLWithPath: "/tmp")
    manager.addRecentFolder(url)

    let result = manager.foldersUsedWithin(days: 10)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.path, "/tmp")
  }

  func testFoldersUsedWithinDaysExcludesOldEntries() {
    let url1 = URL(fileURLWithPath: "/tmp")
    let url2 = URL(fileURLWithPath: "/var")
    manager.addRecentFolder(url1)
    manager.addRecentFolder(url2)

    /// Both were just added, so they should appear within 10 days.
    XCTAssertEqual(manager.foldersUsedWithin(days: 10).count, 2)

    /// Backdate /tmp to 15 days ago — it should be excluded from a 10-day filter.
    let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
    manager.replaceEntry(at: 1, with: RecentFolderEntry(path: "/tmp", lastUsedDate: oldDate))

    let result = manager.foldersUsedWithin(days: 10)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.path, "/var")
  }

  // MARK: - Entry Timestamp Tests

  func testAddFolderSetsTimestamp() {
    let url = URL(fileURLWithPath: "/tmp")
    let before = Date()
    manager.addRecentFolder(url)
    let after = Date()

    guard let entry = manager.entries.first else {
      XCTFail("Expected entry")
      return
    }

    XCTAssertGreaterThanOrEqual(entry.lastUsedDate, before)
    XCTAssertLessThanOrEqual(entry.lastUsedDate, after)
  }
}
