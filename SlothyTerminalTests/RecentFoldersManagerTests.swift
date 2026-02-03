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
  }

  // MARK: - Add Folder Tests

  func testAddSingleFolder() {
    let url = URL(fileURLWithPath: "/tmp")
    manager.addRecentFolder(url)

    XCTAssertEqual(manager.recentFolders.count, 1)
    XCTAssertEqual(manager.recentFolders.first?.path, "/tmp")
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

  func testAddFolderTrimsToMaxSize() {
    /// Add more than max (10) folders
    for i in 1...15 {
      let url = URL(fileURLWithPath: "/folder\(i)")
      manager.addRecentFolder(url)
    }

    XCTAssertEqual(manager.recentFolders.count, 10)
    /// Most recent should be folder15
    XCTAssertEqual(manager.recentFolders.first?.path, "/folder15")
    /// Oldest kept should be folder6
    XCTAssertEqual(manager.recentFolders.last?.path, "/folder6")
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
  }

  // MARK: - Order Tests

  func testMostRecentFirst() {
    let urls = [
      URL(fileURLWithPath: "/first"),
      URL(fileURLWithPath: "/second"),
      URL(fileURLWithPath: "/third")
    ]

    for url in urls {
      manager.addRecentFolder(url)
    }

    XCTAssertEqual(manager.recentFolders[0].path, "/third")
    XCTAssertEqual(manager.recentFolders[1].path, "/second")
    XCTAssertEqual(manager.recentFolders[2].path, "/first")
  }
}
