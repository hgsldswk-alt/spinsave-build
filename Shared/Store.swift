import Foundation

struct AppData: Codable {
    var version: Int = 1
    var goals: [Goal] = [Goal()]
    var selectedGoalID: UUID?
    var makeupUsage: [String: Int] = [:]
    var entitlement = Entitlement()
    var reminderEnabled = false
    var widgetPrivacy = true
    var reminderMinute = 20 * 60
    var expiryNoticeShown = false
    var launchCount = 0
    var reviewedVersion: String?
    var onboarded = false
    init() {}
    enum CodingKeys: String, CodingKey {
        case version, goals, selectedGoalID, makeupUsage, entitlement, reminderEnabled, reminderMinute
        case expiryNoticeShown, launchCount, reviewedVersion, widgetPrivacy, onboarded
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? [Goal()]
        if goals.isEmpty { goals = [Goal()] }
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? goals.contains { !$0.records.isEmpty }
        selectedGoalID = try c.decodeIfPresent(UUID.self, forKey: .selectedGoalID)
        makeupUsage = try c.decodeIfPresent([String: Int].self, forKey: .makeupUsage) ?? [:]
        entitlement = try c.decodeIfPresent(Entitlement.self, forKey: .entitlement) ?? Entitlement()
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        widgetPrivacy = try c.decodeIfPresent(Bool.self, forKey: .widgetPrivacy) ?? true
        reminderMinute = min(1439, max(0, try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 1200))
        expiryNoticeShown = try c.decodeIfPresent(Bool.self, forKey: .expiryNoticeShown) ?? false
        launchCount = try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        reviewedVersion = try c.decodeIfPresent(String.self, forKey: .reviewedVersion)
    }
    var selectedGoal: Goal { goals.first { $0.id == selectedGoalID } ?? goals[0] }

    @discardableResult
    mutating func startGoalPlan(targetCents: Int, days: Int, today: Date,
                                calendar: Calendar = DayKey.calendar) -> Bool {
        guard (1...36500).contains(days),
              let wheel = SaveCore.centeredRange(remainingCents: targetCents, days: days,
                                                 theme: selectedGoal.wheel.theme),
              let deadline = calendar.date(byAdding: .day, value: days - 1, to: calendar.startOfDay(for: today)),
              (1...9999).contains(calendar.component(.year, from: deadline)) else { return false }
        let index = goals.firstIndex { $0.id == selectedGoal.id } ?? 0
        goals[index].targetCents = targetCents
        goals[index].deadline = deadline
        goals[index].wheel = wheel
        onboarded = true
        return true
    }

    mutating func startCasualSaving() {
        let index = goals.firstIndex { $0.id == selectedGoal.id } ?? 0
        goals[index].targetCents = 0
        goals[index].deadline = nil
        goals[index].wheel = WheelConfig(minimumCents: 100, maximumCents: 2000,
                                         integersOnly: true, lowPressure: selectedGoal.wheel.lowPressure,
                                         theme: selectedGoal.wheel.theme)
        onboarded = true
    }
}

enum Store {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "JinTianAppGroup") as? String ?? "group.com.hgsldswk.spinsave"
    }
    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }
    static let key = "spinsave.data.v1"
    static func load(from defaults: UserDefaults = defaults) throws -> AppData {
        guard let raw = defaults.data(forKey: key) else { return AppData() }
        let data = try JSONDecoder().decode(AppData.self, from: raw)
        guard data.version == 1, Set(data.goals.map(\.id)).count == data.goals.count,
              data.goals.allSatisfy({ goal in
                  goal.wheel.isValid && (0...Money.limit).contains(goal.targetCents) &&
                  Set(goal.records.map(\.day)).count == goal.records.count &&
                  goal.records.allSatisfy { DayKey.date($0.day) != nil && (0...Money.limit).contains($0.amountCents) && (0...Money.limit).contains($0.spunCents) }
              }) else { throw CocoaError(.coderReadCorrupt) }
        return data
    }
    static func save(_ data: AppData, to defaults: UserDefaults = defaults) throws {
        defaults.set(try JSONEncoder().encode(data), forKey: key)
    }
}
