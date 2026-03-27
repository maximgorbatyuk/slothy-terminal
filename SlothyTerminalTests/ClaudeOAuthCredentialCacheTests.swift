import XCTest
@testable import SlothyTerminalLib

final class ClaudeOAuthCredentialCacheTests: XCTestCase {
  func testCredentialsLoadsOnlyOnceUntilInvalidated() {
    var loadCount = 0
    var cache = ClaudeOAuthCredentialCache {
      loadCount += 1
      return ClaudeOAuthCredentials(
        token: "token-123",
        subscriptionType: "pro",
        rateLimitTier: "tier-1"
      )
    }

    let first = cache.credentials()
    let second = cache.credentials()

    XCTAssertEqual(first, second)
    XCTAssertEqual(loadCount, 1)

    cache.invalidate()

    let third = cache.credentials()

    XCTAssertEqual(third, first)
    XCTAssertEqual(loadCount, 2)
  }
}
