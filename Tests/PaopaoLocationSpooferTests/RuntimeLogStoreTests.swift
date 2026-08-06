import XCTest
@testable import PaopaoLocationSpoofer

final class RuntimeLogStoreTests: XCTestCase {
    func testRetentionCutoffIsExactlyThreeDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            RuntimeLogStore.retentionCutoff(now: now),
            now.addingTimeInterval(-3 * 24 * 60 * 60)
        )
    }

    func testRetentionKeepsCutoffAndNewerEntriesOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = RuntimeLogStore.retentionCutoff(now: now)
        let expired = RuntimeLogEntry(timestamp: cutoff.addingTimeInterval(-0.001), source: "APP", level: .info, category: "Test", message: "expired")
        let boundary = RuntimeLogEntry(timestamp: cutoff, source: "APP", level: .info, category: "Test", message: "boundary")
        let recent = RuntimeLogEntry(timestamp: now, source: "CORE", level: .warning, category: "Proxy", message: "recent")

        XCTAssertEqual(
            RuntimeLogStore.retainedEntries([expired, boundary, recent], now: now),
            [boundary, recent]
        )
    }
}
