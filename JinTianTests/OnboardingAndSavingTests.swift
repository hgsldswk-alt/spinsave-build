import XCTest

final class OnboardingAndSavingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testOnboardingMigrationLooksAtAnyGoalAndAnyRecord() throws {
        for record in [#"{"day":"2026-11-01","amountCents":100}"#,
                       #"{"day":"2026-11-01","amountCents":100,"isDeleted":true}"#] {
            let json = "{\"goals\":[{\"records\":[]},{\"records\":[" + record + "]}]}"
            let data = try JSONDecoder().decode(AppData.self, from: Data(json.utf8))
            XCTAssertTrue(data.onboarded)
        }
        for json in ["{}", #"{"goals":[]}"#, #"{"goals":[{"records":[]}]}"#] {
            XCTAssertFalse(try JSONDecoder().decode(AppData.self, from: Data(json.utf8)).onboarded)
        }
        XCTAssertFalse(AppData().onboarded)
    }

    func testExplicitOnboardingFlagSurvivesRoundTrip() throws {
        let raw = Data(#"{"onboarded":false,"goals":[{"records":[{"day":"2026-11-01","amountCents":100}]}]}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(AppData.self, from: raw).onboarded)
        var data = AppData()
        data.onboarded = true
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertTrue(decoded.onboarded)
        XCTAssertTrue(decoded.selectedGoal.records.isEmpty)
    }

    func testGoalPlanWritesSelectedGoalDeadlineAndIntegerRecommendation() throws {
        var data = AppData()
        let first = data.selectedGoal
        let selected = Goal(name: "Trip", wheel: WheelConfig(lowPressure: false, theme: "violet"))
        data.goals.append(selected)
        data.selectedGoalID = selected.id
        let today = try XCTUnwrap(DayKey.date("2026-03-07", calendar: calendar))
        XCTAssertTrue(data.startGoalPlan(targetCents: 500_000, days: 100, today: today, calendar: calendar))
        XCTAssertTrue(data.onboarded)
        XCTAssertEqual(data.selectedGoal.targetCents, 500_000)
        XCTAssertEqual(data.selectedGoal.deadline, calendar.date(byAdding: .day, value: 99, to: calendar.startOfDay(for: today)))
        XCTAssertEqual(data.selectedGoal.wheel.minimumCents, 2_000)
        XCTAssertEqual(data.selectedGoal.wheel.maximumCents, 8_000)
        XCTAssertGreaterThanOrEqual(SaveCore.expectedDailyCents(data.selectedGoal.wheel), 5_000)
        XCTAssertEqual(data.goals[0], first)
        XCTAssertEqual(data.selectedGoal.id, selected.id)
    }

    func testInvalidOnboardingPlanDoesNotPartiallyWrite() {
        var data = AppData()
        let original = data.selectedGoal
        for (amount, days) in [(0, 100), (-1, 30), (Money.limit + 1, 100), (1000, 0), (1000, -1), (1000, Int.max)] {
            XCTAssertFalse(data.startGoalPlan(targetCents: amount, days: days, today: Date()))
            XCTAssertEqual(data.selectedGoal, original)
            XCTAssertFalse(data.onboarded)
        }
    }

    func testCasualSavingHasNoTargetAndPersistsAndShares() throws {
        let suite = "spinsave.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var data = AppData()
        data.goals[0].deadline = Date()
        data.startCasualSaving()
        XCTAssertTrue(data.onboarded)
        XCTAssertFalse(data.selectedGoal.hasTarget)
        XCTAssertNil(data.selectedGoal.deadline)
        XCTAssertEqual(data.selectedGoal.wheel.minimumCents, 100)
        XCTAssertEqual(data.selectedGoal.wheel.maximumCents, 2000)
        XCTAssertTrue(data.selectedGoal.wheel.integersOnly)
        try Store.save(data, to: defaults)
        let decoded = try Store.load(from: defaults)
        XCTAssertEqual(decoded.selectedGoal, data.selectedGoal)
        XCTAssertTrue(decoded.onboarded)
        let code = try XCTUnwrap(ShareCode.encode(decoded.selectedGoal))
        let imported = try XCTUnwrap(ShareCode.decode(code))
        XCTAssertFalse(imported.hasTarget)
        XCTAssertEqual(imported.wheel, decoded.selectedGoal.wheel)
    }

    func testDrawIsSavedBeforeAnimationAndUndoCannotRerollAcrossReload() throws {
        let suite = "spinsave.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var data = AppData()
        data.startCasualSaving()
        var rng = SeededRandom(state: 11)
        let day = "2026-11-17"
        let amount = try XCTUnwrap(data.goals[0].recordSpin(on: day, using: &rng))
        XCTAssertTrue(data.selectedGoal.records[0].isSaved)
        XCTAssertEqual(SaveCore.total(data.selectedGoal.records), amount)
        try Store.save(data, to: defaults)
        data = try Store.load(from: defaults)
        XCTAssertNil(data.goals[0].recordSpin(on: day, using: &rng))
        XCTAssertTrue(data.goals[0].setSaved(on: day, to: false))
        XCTAssertEqual(SaveCore.total(data.selectedGoal.records), 0)
        XCTAssertEqual(data.selectedGoal.records[0].amountCents, amount)
        XCTAssertEqual(data.selectedGoal.records[0].spunCents, amount)
        try Store.save(data, to: defaults)
        data = try Store.load(from: defaults)
        XCTAssertNil(data.goals[0].recordSpin(on: day, using: &rng))
        XCTAssertTrue(data.goals[0].setSaved(on: day, to: true))
        XCTAssertEqual(data.selectedGoal.records.count, 1)
        XCTAssertEqual(SaveCore.total(data.selectedGoal.records), amount)
        XCTAssertTrue(data.makeupUsage.isEmpty)
    }

    func testDeletedOrMissingRecordCannotBeResavedOrRerolled() {
        var goal = Goal(records: [DayRecord(day: "2026-11-17", amountCents: 100, isDeleted: true)])
        var rng = SeededRandom(state: 1)
        XCTAssertFalse(goal.setSaved(on: "2026-11-16", to: true))
        XCTAssertFalse(goal.setSaved(on: "2026-11-17", to: true))
        XCTAssertNil(goal.recordSpin(on: "2026-11-17", using: &rng))
        XCTAssertNotNil(goal.recordSpin(on: "2026-11-18", using: &rng))
    }

    func testNoTargetProgressAndProjectionAreSafeWithSavings() {
        let goal = Goal(targetCents: 0, records: [DayRecord(day: "2026-11-17", amountCents: 500, isSaved: true)])
        XCTAssertEqual(SaveCore.progress(goal), 0)
        XCTAssertTrue(SaveCore.progress(goal).isFinite)
        XCTAssertNil(SaveCore.projectedCompletion(goal, today: Date()))
        XCTAssertEqual(SaveCore.total(goal.records), 500)
    }
}
