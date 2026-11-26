import XCTest

final class GoalPlanningTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ key: String) -> Date { DayKey.date(key, calendar: calendar)! }

    func testExpectationMatchesExactDiscreteProbabilities() {
        for integers in [true, false] {
            let step = integers ? 100 : 1
            for lowPressure in [true, false] {
                for last in 0...20 {
                    let wheel = WheelConfig(minimumCents: 2 * step, maximumCents: (last + 2) * step,
                                            integersOnly: integers, lowPressure: lowPressure)
                    let count = Double(last + 1)
                    let exact = (0...last).reduce(0.0) { sum, index in
                        let probability = lowPressure ? Double(2 * (last + 1 - index) - 1) / (count * count) : 1 / count
                        return sum + Double((index + 2) * step) * probability
                    }
                    XCTAssertEqual(SaveCore.expectedDailyCents(wheel), exact, accuracy: 0.000001)
                }
            }
        }
    }

    func testRecommendationsMeetBudgetForBothPrecisionsAndModes() throws {
        for integers in [true, false] {
            for pressure in [true, false] {
                for target in [1, 99, 100, 12345, 200000, Money.limit - 1, Money.limit] {
                    for days in [1, 2, 30, 365, 1000000] {
                        let wheel = try XCTUnwrap(SaveCore.suggestedRange(remainingCents: target, days: days,
                                                                         integersOnly: integers, lowPressure: pressure, theme: "violet"))
                        XCTAssertTrue(wheel.isValid)
                        XCTAssertEqual(wheel.theme, "violet")
                        XCTAssertEqual(wheel.lowPressure, pressure)
                        XCTAssertEqual(wheel.minimumCents % wheel.step, 0)
                        XCTAssertEqual(wheel.maximumCents % wheel.step, 0)
                        let expectation = SaveCore.expectedDailyCents(wheel)
                        XCTAssertGreaterThanOrEqual(expectation, Double(target) / Double(days))
                        XCTAssertLessThanOrEqual(try XCTUnwrap(SaveCore.estimatedDays(remainingCents: target, dailyCents: expectation)), days)
                        if wheel.maximumCents > wheel.minimumCents {
                            var smaller = wheel
                            smaller.maximumCents -= smaller.step
                            XCTAssertLessThan(SaveCore.expectedDailyCents(smaller), Double(target) / Double(days))
                        }
                    }
                }
            }
        }
    }

    func testTinyTargetsAndLongPlansAllowZeroMinimum() throws {
        for integers in [true, false] {
            for pressure in [true, false] {
                for (target, days) in [(1, 1), (100, 365), (200000, 1000000)] {
                    let wheel = try XCTUnwrap(SaveCore.suggestedRange(remainingCents: target, days: days,
                                                                     integersOnly: integers, lowPressure: pressure))
                    XCTAssertEqual(wheel.minimumCents, 0)
                    XCTAssertGreaterThan(wheel.maximumCents, 0)
                }
            }
        }
    }

    func testOrdinaryAndLowPressurePlans() throws {
        let uniform = try XCTUnwrap(SaveCore.suggestedRange(remainingCents: 30000, days: 30, integersOnly: true, lowPressure: false))
        let pressure = try XCTUnwrap(SaveCore.suggestedRange(remainingCents: 30000, days: 30, integersOnly: true, lowPressure: true))
        XCTAssertEqual(uniform.minimumCents, 100)
        XCTAssertEqual(uniform.maximumCents, 1900)
        XCTAssertGreaterThan(pressure.maximumCents, uniform.maximumCents)
        let decimal = try XCTUnwrap(SaveCore.suggestedRange(remainingCents: 12345, days: 30, integersOnly: false, lowPressure: false))
        XCTAssertEqual(decimal.minimumCents, 41)
        XCTAssertEqual(decimal.maximumCents, 782)
    }

    func testInvalidPlansAndZeroDailyExpectation() {
        for target in [0, -1, Money.limit + 1] {
            XCTAssertNil(SaveCore.suggestedRange(remainingCents: target, days: 30, integersOnly: true, lowPressure: true))
        }
        for days in [0, -1] {
            XCTAssertNil(SaveCore.suggestedRange(remainingCents: 10000, days: days, integersOnly: true, lowPressure: false))
        }
        XCTAssertEqual(SaveCore.expectedDailyCents(WheelConfig(minimumCents: 200, maximumCents: 100)), 0)
        XCTAssertNil(SaveCore.estimatedDays(remainingCents: 100, dailyCents: 0))
        XCTAssertNil(SaveCore.estimatedDays(remainingCents: 100, dailyCents: .nan))
        XCTAssertNil(SaveCore.estimatedDays(remainingCents: 100, dailyCents: .infinity))
        XCTAssertEqual(SaveCore.estimatedDays(remainingCents: 0, dailyCents: 0), 0)
        XCTAssertEqual(SaveCore.estimatedDays(remainingCents: 1001, dailyCents: 100), 11)
    }

    func testDeadlineIncludesTodayOnlyBeforeSaving() {
        let today = date("2026-11-14")
        XCTAssertEqual(SaveCore.remainingDays(until: today, today: today, savedToday: false, calendar: calendar), 1)
        XCTAssertEqual(SaveCore.remainingDays(until: today, today: today, savedToday: true, calendar: calendar), 0)
        XCTAssertEqual(SaveCore.remainingDays(until: date("2026-11-16"), today: today, savedToday: false, calendar: calendar), 3)
        XCTAssertEqual(SaveCore.remainingDays(until: date("2026-11-13"), today: today, savedToday: false, calendar: calendar), 0)
        var local = calendar
        local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = DayKey.date("2026-03-07", calendar: local)!
        let end = DayKey.date("2026-03-09", calendar: local)!
        XCTAssertEqual(SaveCore.remainingDays(until: end, today: start, savedToday: false, calendar: local), 3)
    }

    func testProjectionUsesMissedDaysAndExcludesUnsavedDeletedAndFuture() {
        let today = date("2026-11-14")
        var goal = Goal(targetCents: 10000, wheel: WheelConfig(minimumCents: 1000, maximumCents: 1000))
        XCTAssertEqual(DayKey.key(SaveCore.projectedCompletion(goal, today: today, calendar: calendar)!, calendar: calendar), "2026-11-23")
        goal.records = [DayRecord(day: "2026-11-10", amountCents: 1000, isSaved: true),
                        DayRecord(day: "2026-11-14", amountCents: 9000),
                        DayRecord(day: "2026-11-11", amountCents: 1000, isSaved: true, isDeleted: true),
                        DayRecord(day: "2026-11-20", amountCents: 10000, isSaved: true)]
        XCTAssertEqual(DayKey.key(SaveCore.projectedCompletion(goal, today: today, calendar: calendar)!, calendar: calendar), "2026-12-19")
        goal.records = [DayRecord(day: "2026-11-14", amountCents: 1000, isSaved: true)]
        XCTAssertEqual(DayKey.key(SaveCore.projectedCompletion(goal, today: today, calendar: calendar)!, calendar: calendar), "2026-11-23")
        goal.targetCents = 1000
        XCTAssertEqual(SaveCore.projectedCompletion(goal, today: today, calendar: calendar), today)
        goal.targetCents = 10000
        goal.records = [DayRecord(day: "2026-11-14", amountCents: 0, isSaved: true)]
        XCTAssertNil(SaveCore.projectedCompletion(goal, today: today, calendar: calendar))
    }

    func testCalendarAmountsPreservePreviouslySavedFractions() {
        XCTAssertEqual(Money.display(1200, integersOnly: true), "12")
        XCTAssertEqual(Money.display(1234, integersOnly: true), "12.34")
        XCTAssertEqual(Money.display(1200, integersOnly: false), "12.00")
        XCTAssertEqual(Money.yuan(100), "¥1.00")
    }
}
