import XCTest

final class PersistenceAndEntitlementTests: XCTestCase {
    func testOldJSONMissingFieldsDecodes() throws {
        let raw = Data(#"{"goals":[{"name":"old","records":[{"day":"2026-11-01","amountCents":10}]}]}"#.utf8)
        let data = try JSONDecoder().decode(AppData.self, from: raw)
        XCTAssertEqual(data.goals[0].wheel, WheelConfig())
        XCTAssertEqual(data.goals[0].records[0].spunCents, 10)
        XCTAssertFalse(data.goals[0].records[0].isSaved)
        XCTAssertFalse(data.goals[0].records[0].isMakeup)
        XCTAssertEqual(data.reminderMinute, 1200)
        XCTAssertTrue(data.makeupUsage.isEmpty)
        XCTAssertFalse(data.entitlement.purchasedPro)
        XCTAssertTrue(data.widgetPrivacy)
        XCTAssertTrue(data.goals[0].wheel.lowPressure)
    }
    func testEmptyGoalsMigrateToDefault() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data(#"{"goals":[]}"#.utf8))
        XCTAssertEqual(data.goals.count, 1)
    }
    func testStoreRoundTripAndCorruptionNeverOverwrites() throws {
        let suite = "spinsave.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var data = AppData()
        data.goals[0].records = [DayRecord(day: "2026-11-01", amountCents: 23650, isSaved: true)]
        data.makeupUsage = ["2026-11": 2]
        try Store.save(data, to: defaults)
        let decoded = try Store.load(from: defaults)
        XCTAssertEqual(decoded.goals, data.goals)
        XCTAssertEqual(decoded.makeupUsage, data.makeupUsage)
        let corrupt = Data("bad-json".utf8)
        defaults.set(corrupt, forKey: Store.key)
        XCTAssertThrowsError(try Store.load(from: defaults))
        XCTAssertEqual(defaults.data(forKey: Store.key), corrupt)
    }
    func testUnknownSchemaAndDuplicateDaysAreRejected() throws {
        let suite = "spinsave.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var data = AppData(); data.version = 2
        try Store.save(data, to: defaults)
        XCTAssertThrowsError(try Store.load(from: defaults))
        data.version = 1
        data.goals[0].records = Array(repeating: DayRecord(day: "2026-11-01", amountCents: 100), count: 2)
        try Store.save(data, to: defaults)
        XCTAssertThrowsError(try Store.load(from: defaults))
    }
    func testTrialExactThirtyDayBoundary() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let e = Entitlement(firstOpen: start)
        XCTAssertTrue(e.isPremium(at: start))
        XCTAssertEqual(e.remainingDays(at: start), 30)
        XCTAssertTrue(e.isPremium(at: e.trialEnd.addingTimeInterval(-1)))
        XCTAssertEqual(e.remainingDays(at: e.trialEnd.addingTimeInterval(-1)), 1)
        XCTAssertFalse(e.isPremium(at: e.trialEnd))
        XCTAssertEqual(e.remainingDays(at: e.trialEnd), 0)
        XCTAssertTrue(e.isPremium(at: start.addingTimeInterval(-1)))
        XCTAssertFalse(e.isPremium(at: start.addingTimeInterval(-601)))
    }
    func testRestoreNeverRestartsTrialAndProRevokes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var e = Entitlement(firstOpen: start, trialClaimedAt: start.addingTimeInterval(10 * 86400))
        XCTAssertEqual(e.trialStart, start)
        e.trialClaimedAt = start.addingTimeInterval(-20 * 86400)
        XCTAssertEqual(e.remainingDays(at: start), 10)
        e.purchasedPro = true
        XCTAssertTrue(e.isPremium(at: start.addingTimeInterval(100 * 86400)))
        e.purchasedPro = false
        XCTAssertFalse(e.isPremium(at: start.addingTimeInterval(100 * 86400)))
    }
    func testPaidEraRestartsTrialForFreePeriodUsers() {
        let installed = Date(timeIntervalSince1970: 1_800_000_000)
        let paidStart = installed.addingTimeInterval(60 * 86400)
        var e = Entitlement(firstOpen: installed)
        XCTAssertFalse(e.isPremium(at: paidStart))
        e.proStartedAt = paidStart
        XCTAssertEqual(e.trialStart, paidStart)
        XCTAssertTrue(e.isPremium(at: paidStart))
        XCTAssertEqual(e.remainingDays(at: paidStart), 30)
        XCTAssertFalse(e.isPremium(at: paidStart.addingTimeInterval(30 * 86400)))
        let fresh = Entitlement(firstOpen: paidStart, proStartedAt: paidStart.addingTimeInterval(1))
        XCTAssertEqual(fresh.remainingDays(at: paidStart.addingTimeInterval(1)), 30)
        let old = try! JSONDecoder().decode(Entitlement.self, from: Data(#"{"firstOpen":0,"purchasedPro":false}"#.utf8))
        XCTAssertNil(old.proStartedAt)
    }
}
