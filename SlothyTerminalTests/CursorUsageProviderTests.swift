import XCTest
@testable import SlothyTerminalLib

final class CursorUsageProviderTests: XCTestCase {

  // MARK: - parseCurrentPeriod (planUsage shape)

  func testParseCurrentPeriodReadsPlanUsageFields() throws {
    let data = Data(planUsageJSON.utf8)

    let totals = try XCTUnwrap(CursorUsageProvider.parseCurrentPeriod(data: data))

    /// API reports cents — fixture has totalSpend=2726 (cents) ⇒ $27.26,
    /// limit=40000 (cents) ⇒ $400 (Ultra plan).
    XCTAssertEqual(totals.apiPercentUsed ?? 0, 5.318, accuracy: 0.0001)
    XCTAssertEqual(totals.autoPercentUsed ?? 0, 0.0957142857, accuracy: 0.0001)
    XCTAssertEqual(totals.totalSpendDollars, 27.26)
    XCTAssertEqual(totals.limitDollars, 400.0)
    XCTAssertEqual(totals.spent, 27.26)
    XCTAssertEqual(totals.includedDollars, 27.26)
  }

  func testParseCurrentPeriodReadsBillingCycleEnd() throws {
    let data = Data(planUsageJSON.utf8)

    let totals = try XCTUnwrap(CursorUsageProvider.parseCurrentPeriod(data: data))
    let cycleEnd = try XCTUnwrap(totals.billingCycleEnd)

    XCTAssertEqual(cycleEnd.timeIntervalSince1970, 1779467822, accuracy: 0.001)
  }

  func testParseCurrentPeriodReturnsNilFieldsForLegacyShape() throws {
    let data = Data(#"{"unknown": "value"}"#.utf8)

    let totals = try XCTUnwrap(CursorUsageProvider.parseCurrentPeriod(data: data))

    XCTAssertNil(totals.apiPercentUsed)
    XCTAssertNil(totals.autoPercentUsed)
    XCTAssertNil(totals.totalSpendDollars)
    XCTAssertNil(totals.limitDollars)
    XCTAssertNil(totals.billingCycleEnd)
  }

  func testParseCurrentPeriodFallsBackToFlatKeys() throws {
    let json = #"{"totalCents": 1234, "includedCreditCents": 4000, "hardLimitCents": 10000}"#
    let data = Data(json.utf8)

    let totals = try XCTUnwrap(CursorUsageProvider.parseCurrentPeriod(data: data))

    XCTAssertEqual(totals.spent, 12.34)
    XCTAssertEqual(totals.includedDollars, 40.0)
    XCTAssertEqual(totals.hardLimitDollars, 100.0)
  }

  // MARK: - parseEventsPage

  func testParseEventsPageExtractsChargedDollarsAndTimestamp() {
    let data = Data(eventsJSON.utf8)

    let events = CursorUsageProvider.parseEventsPage(data: data)

    XCTAssertEqual(events.count, 9)

    let first = events[0]
    XCTAssertEqual(first.model, "Premium (Codex 5.3)")
    XCTAssertEqual(first.chargedDollars, 0.7082691192626953, accuracy: 0.0001)
    XCTAssertEqual(first.timestamp.timeIntervalSince1970, 1777618458.168, accuracy: 0.01)

    let zeroCharged = events[2]
    XCTAssertEqual(zeroCharged.chargedDollars, 0)
    XCTAssertEqual(zeroCharged.model, "claude-opus-4-7-thinking-high")
  }

  func testParseEventsPageHandlesMissingFields() {
    let json = #"{"usageEventsDisplay": [{"model": "X"}]}"#
    let data = Data(json.utf8)

    let events = CursorUsageProvider.parseEventsPage(data: data)

    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].model, "X")
    XCTAssertEqual(events[0].chargedDollars, 0)
    XCTAssertEqual(events[0].timestamp, .distantPast)
  }

  // MARK: - groupEventsByModel

  func testGroupEventsByModelSumsChargedDollars() {
    let events = CursorUsageProvider.parseEventsPage(data: Data(eventsJSON.utf8))

    let grouped = CursorUsageProvider.groupEventsByModel(events, limit: 5)

    XCTAssertEqual(grouped.count, 3)

    /// Premium (Codex 5.3): 70.83 + 8.73 + 78.66 + 26.67 + 37.36 + 37.55 = 259.79 cents
    XCTAssertEqual(grouped[0].model, "Premium (Codex 5.3)")
    XCTAssertEqual(grouped[0].dollars, 2.5979146957397462, accuracy: 0.0001)

    /// claude-opus-4-7-thinking-high: 162.41 + 0 = 162.41 cents
    XCTAssertEqual(grouped[1].model, "claude-opus-4-7-thinking-high")
    XCTAssertEqual(grouped[1].dollars, 1.6240863037109375, accuracy: 0.0001)

    /// claude-4.6-opus-high-thinking: 0 cents
    XCTAssertEqual(grouped[2].model, "claude-4.6-opus-high-thinking")
    XCTAssertEqual(grouped[2].dollars, 0, accuracy: 0.0001)
  }

  func testGroupEventsByModelKeepsMostRecentTimestampPerGroup() throws {
    let events = CursorUsageProvider.parseEventsPage(data: Data(eventsJSON.utf8))

    let grouped = CursorUsageProvider.groupEventsByModel(events, limit: 5)

    /// Premium (Codex 5.3) latest timestamp = 1777618458168 ms.
    let premium = try XCTUnwrap(grouped.first { $0.model == "Premium (Codex 5.3)" })
    XCTAssertEqual(premium.timestamp.timeIntervalSince1970, 1777618458.168, accuracy: 0.01)
  }

  func testGroupEventsByModelRespectsLimit() {
    let events = CursorUsageProvider.parseEventsPage(data: Data(eventsJSON.utf8))

    let grouped = CursorUsageProvider.groupEventsByModel(events, limit: 1)

    XCTAssertEqual(grouped.count, 1)
    XCTAssertEqual(grouped[0].model, "Premium (Codex 5.3)")
  }

  // MARK: - buildSnapshot percentUsed scale

  /// Regression test: `UsageSnapshot.percentUsed` is a 0-1 fraction (the view
  /// layer multiplies by 100). Earlier, Cursor's snapshot stored 0-100 here,
  /// which the status-bar bars then multiplied again — rendering "681%"
  /// instead of "6.81%" for a $27.26 / $400 Ultra account.
  func testBuildSnapshotPercentUsedIsZeroToOneFraction() {
    let totals = CursorUsageProvider.CurrentPeriodTotals(
      spent: 27.26,
      includedDollars: 27.26,
      hardLimitDollars: nil,
      apiPercentUsed: 5.318,
      autoPercentUsed: 0.0957,
      totalSpendDollars: 27.26,
      limitDollars: 400.0,
      billingCycleEnd: Date(timeIntervalSince1970: 1779467822)
    )

    let snapshot = CursorUsageProvider.buildSnapshot(
      events: [],
      periodTotals: totals,
      periodStart: Date(timeIntervalSince1970: 1776875822),
      sourceKind: .apiKey,
      sourceLabel: "Test"
    )

    let percent = try? XCTUnwrap(snapshot.percentUsed)
    XCTAssertEqual(percent ?? 0, 0.06815, accuracy: 0.0001)
    XCTAssertLessThanOrEqual(snapshot.percentUsed ?? 0, 1.0)
  }

  func testBuildSnapshotSpendMetricFormatsPercentForDisplay() {
    let totals = CursorUsageProvider.CurrentPeriodTotals(
      spent: 27.26,
      includedDollars: 27.26,
      hardLimitDollars: nil,
      apiPercentUsed: nil,
      autoPercentUsed: nil,
      totalSpendDollars: 27.26,
      limitDollars: 400.0,
      billingCycleEnd: nil
    )

    let snapshot = CursorUsageProvider.buildSnapshot(
      events: [],
      periodTotals: totals,
      periodStart: Date(timeIntervalSince1970: 1776875822),
      sourceKind: .apiKey,
      sourceLabel: "Test"
    )

    let spend = snapshot.metrics.first { $0.label == "Spend" }
    XCTAssertNotNil(spend)
    /// 27.26 / 400 = 0.06815 → "%.2f" rounds 6.815% up to 6.82%.
    XCTAssertEqual(spend?.value, "$27.26 / $400.00 (6.82%)")
  }

  func testBuildSnapshotPercentUsedClampsAtOne() {
    let totals = CursorUsageProvider.CurrentPeriodTotals(
      spent: 800.0,
      includedDollars: nil,
      hardLimitDollars: nil,
      apiPercentUsed: nil,
      autoPercentUsed: nil,
      totalSpendDollars: 800.0,
      limitDollars: 400.0,
      billingCycleEnd: nil
    )

    let snapshot = CursorUsageProvider.buildSnapshot(
      events: [],
      periodTotals: totals,
      periodStart: Date(timeIntervalSince1970: 1776875822),
      sourceKind: .apiKey,
      sourceLabel: "Test"
    )

    XCTAssertEqual(snapshot.percentUsed, 1.0)
  }
}

// MARK: - Fixtures

private let planUsageJSON = """
{
  "autoBucketModels": ["default", "composer-1.5"],
  "autoModelSelectedDisplayMessage": "You've used 2% of your included total usage",
  "billingCycleEnd": "1779467822000",
  "billingCycleStart": "1776875822000",
  "displayMessage": "You've used 5% of your included usage",
  "displayThreshold": 200,
  "enabled": true,
  "namedModelSelectedDisplayMessage": "You've used 5% of your included API usage",
  "planUsage": {
    "apiPercentUsed": 5.318,
    "autoPercentUsed": 0.09571428571428571,
    "bonusTooltip": "We work with model providers to give you free usage beyond what you've purchased.",
    "includedSpend": 2726,
    "limit": 40000,
    "remaining": 37274,
    "remainingBonus": false,
    "totalPercentUsed": 2.2716666666666665,
    "totalSpend": 2726
  },
  "spendLimitUsage": {
    "individualLimit": 10000,
    "individualRemaining": 10000,
    "limitType": "user"
  }
}
"""

private let eventsJSON = """
{
  "totalUsageEventsCount": 9,
  "usageEventsDisplay": [
    {
      "chargedCents": 70.82691192626953,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "Premium (Codex 5.3)",
      "requestsCosts": 17.700000762939453,
      "timestamp": "1777618458168",
      "tokenUsage": {
        "cacheReadTokens": 1359872,
        "inputTokens": 222994,
        "outputTokens": 5718,
        "totalCents": 70.82691192626953
      },
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 162.40863037109375,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "claude-opus-4-7-thinking-high",
      "timestamp": "1777617670788",
      "tokenUsage": {"inputTokens": 1342, "outputTokens": 10699},
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 0,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "claude-opus-4-7-thinking-high",
      "timestamp": "1777617668511",
      "tokenUsage": {},
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 0,
      "isChargeable": false,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "claude-4.6-opus-high-thinking",
      "timestamp": "1777615815293",
      "tokenUsage": {"outputTokens": 18671},
      "usageBasedCosts": "$0.00"
    },
    {
      "chargedCents": 8.727424621582031,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "Premium (Codex 5.3)",
      "timestamp": "1777615376088",
      "tokenUsage": {"inputTokens": 33279, "outputTokens": 834},
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 78.6600112915039,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "Premium (Codex 5.3)",
      "timestamp": "1777614611252",
      "tokenUsage": {"inputTokens": 123233, "outputTokens": 7772},
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 26.671855926513672,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "Premium (Codex 5.3)",
      "timestamp": "1777605206832",
      "tokenUsage": {},
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 37.358055114746094,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "Premium (Codex 5.3)",
      "timestamp": "1777605123892",
      "tokenUsage": {},
      "usageBasedCosts": "-"
    },
    {
      "chargedCents": 37.54586410522461,
      "isChargeable": true,
      "kind": "USAGE_EVENT_KIND_INCLUDED_IN_ULTRA",
      "model": "Premium (Codex 5.3)",
      "timestamp": "1777604699776",
      "tokenUsage": {},
      "usageBasedCosts": "-"
    }
  ]
}
"""
