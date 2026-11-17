import XCTest

final class SaveCoreTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    private func date(_ key: String) -> Date { DayKey.date(key, calendar: calendar)! }
    private func saved(_ day: String, _ cents: Int = 100, makeup: Bool = false) -> DayRecord {
        DayRecord(day: day, amountCents: cents, isSaved: true, isMakeup: makeup)
    }
    func testStreakCrossesMonthAndLeapDay() {
        let records = [saved("2024-02-28"), saved("2024-02-29"), saved("2024-03-01")]
        XCTAssertEqual(SaveCore.streak(records, today: date("2024-03-01"), calendar: calendar), 3)
        XCTAssertEqual(SaveCore.streak(records, today: date("2024-03-02"), calendar: calendar), 3)
    }
    func testUnfinishedTodayDoesNotBreakYesterday() {
        let records = [saved("2026-10-30"), saved("2026-10-31"), DayRecord(day: "2026-11-01", amountCents: 100)]
        XCTAssertEqual(SaveCore.streak(records, today: date("2026-11-01"), calendar: calendar), 2)
        XCTAssertEqual(SaveCore.total(records), 200)
    }
    func testMissedYesterdayBreaksStreak() {
        XCTAssertEqual(SaveCore.streak([saved("2026-10-30")], today: date("2026-11-01"), calendar: calendar), 0)
        XCTAssertEqual(SaveCore.streak([saved("2026-10-30"), saved("2026-11-01")], today: date("2026-11-01"), calendar: calendar), 1)
    }
    func testMakeupReconnectsStreak() {
        let records = [saved("2026-10-30"), saved("2026-10-31", makeup: true), saved("2026-11-01")]
        XCTAssertEqual(SaveCore.streak(records, today: date("2026-11-01"), calendar: calendar), 3)
    }
    func testDeletedRecordCountsNeitherMoneyNorStreak() {
        var deleted = saved("2026-10-31", 1000); deleted.isDeleted = true
        let records = [saved("2026-10-30", 100), deleted, saved("2026-11-01", 200)]
        XCTAssertEqual(SaveCore.total(records), 300)
        XCTAssertEqual(SaveCore.streak(records, today: date("2026-11-01"), calendar: calendar), 1)
    }
    func testCentsAccumulateExactly() {
        let records = (1...1000).map { DayRecord(day: String($0), amountCents: 1, isSaved: true) }
        XCTAssertEqual(SaveCore.total(records), 1000)
        XCTAssertEqual(Money.text(SaveCore.total(records)), "10.00")
        XCTAssertEqual(Money.parse("236.50"), 23650)
        XCTAssertEqual(Money.parse("0,01"), 1)
        XCTAssertNil(Money.parse("0.001")); XCTAssertNil(Money.parse("-1"))
        XCTAssertNil(Money.parse("1e5")); XCTAssertNil(Money.parse("1000001"))
        XCTAssertEqual(Money.parse("1000000"), Money.limit)
        XCTAssertEqual(Money.text(300_000_000_001), "3000000000.01")
    }
    func testCalendarHasEveryDayAndKeepsUnsavedResult() {
        let days = SaveCore.month(date("2024-02-14"), records: [DayRecord(day: "2024-02-29", amountCents: 19)], calendar: calendar)
        XCTAssertEqual(days.count, 29)
        XCTAssertEqual(days.first?.key, "2024-02-01")
        XCTAssertEqual(days.last?.record?.amountCents, 19)
        XCTAssertFalse(days.last!.record!.isSaved)
    }
    func testDayKeysAreStrictAndCrossYear() {
        XCTAssertNil(DayKey.date("2026-02-30", calendar: calendar))
        XCTAssertNil(DayKey.date("2026-2-01", calendar: calendar))
        XCTAssertEqual(DayKey.key(DayKey.adding(1, to: date("2026-12-31"), calendar: calendar), calendar: calendar), "2027-01-01")
    }
    func testStreakAcrossDaylightSavingTime() {
        var c = calendar; c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let today = DayKey.date("2026-03-09", calendar: c)!
        XCTAssertEqual(SaveCore.streak([saved("2026-03-07"), saved("2026-03-08"), saved("2026-03-09")], today: today, calendar: c), 3)
    }
    func testMakeupAllowanceResetsByUseMonth() {
        let usage = ["2026-10": 3, "2026-11": 1]
        XCTAssertEqual(SaveCore.makeupRemaining(usage: usage, today: date("2026-10-31"), calendar: calendar), 0)
        XCTAssertEqual(SaveCore.makeupRemaining(usage: usage, today: date("2026-11-01"), calendar: calendar), 2)
        XCTAssertEqual(SaveCore.makeupRemaining(usage: usage, today: date("2026-12-01"), calendar: calendar), 3)
        XCTAssertEqual(SaveCore.makeupRemaining(usage: ["2026-11": 99], today: date("2026-11-01"), calendar: calendar), 0)
    }
    func testSpecialNumbers() {
        let config = WheelConfig(maximumCents: 77700)
        for cents in [6600, 8800, 16800, 52000, 1000, 77700] { XCTAssertTrue(SaveCore.special(cents, config: config)) }
        for cents in [0, 123, 6601, 16801, 999] { XCTAssertFalse(SaveCore.special(cents, config: config)) }
    }
    func testEveryStreakAchievementAndTotals() {
        let today = date("2026-11-01")
        for threshold in [7, 30, 100, 365] {
            let records = (0..<threshold).map { saved(DayKey.key(DayKey.adding(-$0, to: today, calendar: calendar), calendar: calendar)) }
            XCTAssertTrue(SaveCore.achievements(records, today: today, calendar: calendar).contains("streak-\(threshold)"))
            XCTAssertFalse(SaveCore.achievements(Array(records.dropLast()), today: today, calendar: calendar).contains("streak-\(threshold)"))
        }
        XCTAssertEqual(SaveCore.achievements([saved("2026-11-01", 500_000)], today: today, calendar: calendar), ["total-100000", "total-500000"])
        XCTAssertFalse(SaveCore.achievements([saved("2026-11-01", 99999)], today: today, calendar: calendar).contains("total-100000"))
    }
    func testProgressClampsAtTarget() {
        let goal = Goal(targetCents: 100, records: [saved("2026-11-01", 200)])
        XCTAssertEqual(SaveCore.progress(goal), 1)
    }
}
