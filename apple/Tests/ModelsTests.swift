import Foundation
import XCTest
@testable import VibeWatchCore

final class ModelsTests: XCTestCase {
    func testOptionalUsageIsBackwardCompatibleAndSupportsLargeCounters() throws {
        var snapshot = try example()
        XCTAssertNil(snapshot.usage)
        snapshot.usage = LocalUsage(periodStart: 100, periodEnd: 86500, utcOffsetMinutes: 480,
            inputTokens: 3_000_000_000, cachedInputTokens: 40, outputTokens: 20, totalTokens: 3_000_000_060,
            hours: [UsageHour(start: 100, tokens: 3_000_000_060)], source: "local", partial: false,
            model: "gpt-test", reasoningEffort: "high", lastActivityAt: 200)
        let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.usage?.peakHour?.tokens, 3_000_000_060)
        XCTAssertFalse(restored.usage!.isCurrent(at: Date(timeIntervalSince1970: 86500)))
        XCTAssertTrue(restored.usage!.isCurrent(at: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(LocalUsage.compact(18_300_000), "18.3M")
    }
    func example() throws -> QuotaSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(QuotaSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("contracts/snapshot.example.json")))
    }
    func testContractDecodesMultipleBucketsAndNulls() throws {
        let snapshot = try example()
        XCTAssertEqual(snapshot.buckets.count, 2)
        XCTAssertEqual(snapshot.buckets[0].primary?.remaining, 72)
        XCTAssertNil(snapshot.buckets[1].primary)
        XCTAssertNil(snapshot.ordinaryUsageAllowed)
    }
    func testMissingUsedPercentNeverBecomesFull() throws {
        let window = try JSONDecoder().decode(QuotaWindow.self, from: Data("{}".utf8))
        XCTAssertNil(window.remaining)
        XCTAssertNil(QuotaWindow(usedPercent: 101, windowDurationMins: nil, resetsAt: nil).remaining)
        XCTAssertEqual(QuotaWindow(usedPercent: 0, windowDurationMins: nil, resetsAt: nil).remaining, 100)
    }
    func testResetBoundaryDoesNotRefillAndStalenessUsesCollectionTime() throws {
        let window = QuotaWindow(usedPercent: 85, windowDurationMins: 300, resetsAt: 200)
        XCTAssertFalse(window.awaitingReset(at: Date(timeIntervalSince1970:199), collectedAt:100))
        XCTAssertTrue(window.awaitingReset(at: Date(timeIntervalSince1970:200), collectedAt:100))
        XCTAssertFalse(window.awaitingReset(at: Date(timeIntervalSince1970:201), collectedAt:201))
        XCTAssertEqual(window.remaining,15)
        let snapshot = try example()
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970:snapshot.collectedAt + 599)))
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970:snapshot.collectedAt + 600)))
    }
    func testBucketSelectionDoesNotSilentlySwitchMissingQuota() throws {
        let snapshot = try example()
        XCTAssertEqual(snapshot.bucket(preferred: "")?.limitId,"codex")
        XCTAssertEqual(snapshot.bucket(preferred: "review")?.limitId,"review")
        XCTAssertNil(snapshot.bucket(preferred: "removed"))
    }
    func testTimelineContainsStaleAndResetTransitions() throws {
        let snapshot = try example()
        let dates = snapshot.transitionDates(after:snapshot.collectedDate)
        XCTAssertTrue(dates.contains(Date(timeIntervalSince1970:snapshot.collectedAt + 600)))
        XCTAssertTrue(dates.contains(Date(timeIntervalSince1970:snapshot.buckets[0].primary!.resetsAt!)))
    }
    func testPairingURLValidation() throws {
        let code = String(repeating:"a",count:64)
        XCTAssertEqual(try PairingRequest(link:"vibewatch://pair?server=https%3A%2F%2Fexample.com&code=\(code)").server.host,"example.com")
        for server in ["http://example.com", "https://u:p@example.com", "https://example.com/path"] {
            var c = URLComponents(string:"vibewatch://pair")!
            c.queryItems = [.init(name:"server",value:server),.init(name:"code",value:code)]
            XCTAssertThrowsError(try PairingRequest(link:c.string!))
        }
    }
    func testSingleWeeklyWindowIsSelectedWithoutInventingFiveHourQuota() throws {
        let json = Data("{\"limitId\":\"codex\",\"primary\":null,\"secondary\":{\"usedPercent\":61,\"windowDurationMins\":10080,\"resetsAt\":1800000000}}".utf8)
        let bucket = try JSONDecoder().decode(QuotaBucket.self, from: json)
        XCTAssertNil(bucket.primary)
        XCTAssertEqual(bucket.displayWindow?.durationLabel, "7天")
        XCTAssertEqual(bucket.displayWindow?.remaining, 39)
    }
    func testUnknownWindowPercentageIsNotConfusedWithAnAbsentWindow() {
        let unknown = QuotaWindow(usedPercent: nil, windowDurationMins: 300, resetsAt: nil)
        let weekly = QuotaWindow(usedPercent: 61, windowDurationMins: 10080, resetsAt: nil)
        let bucket = QuotaBucket(limitId: "codex", limitName: nil, primary: unknown, secondary: weekly)
        XCTAssertEqual(bucket.displayWindow, unknown)
        XCTAssertNil(bucket.displayWindow?.remaining)
        XCTAssertNil(QuotaBucket(limitId: "codex", limitName: nil, primary: nil, secondary: nil).displayWindow)
    }
}
