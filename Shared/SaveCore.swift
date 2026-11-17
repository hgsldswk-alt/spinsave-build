import Foundation

enum Money {
    static let limit = 100_000_000
    static func parse(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^\d{1,7}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let cents = NSDecimalNumber(decimal: decimal * 100).intValue
        return (0...limit).contains(cents) ? cents : nil
    }
    static func text(_ cents: Int) -> String {
        String(cents / 100) + String(format: ".%02d", abs(cents % 100))
    }
    static func yuan(_ cents: Int) -> String { "¥" + text(cents) }
    static func display(_ cents: Int, integersOnly: Bool) -> String {
        integersOnly && cents % 100 == 0 ? String(cents / 100) : text(cents)
    }
}

struct WheelConfig: Codable, Equatable {
    var minimumCents: Int = 100
    var maximumCents: Int = 3000
    var integersOnly: Bool = true
    var lowPressure: Bool = true
    var theme: String = "mint"
    init(minimumCents: Int = 100, maximumCents: Int = 3000, integersOnly: Bool = true,
         lowPressure: Bool = true, theme: String = "mint") {
        self.minimumCents = minimumCents; self.maximumCents = maximumCents
        self.integersOnly = integersOnly; self.lowPressure = lowPressure; self.theme = theme
    }
    enum CodingKeys: String, CodingKey { case minimumCents, maximumCents, integersOnly, lowPressure, theme }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minimumCents = try c.decodeIfPresent(Int.self, forKey: .minimumCents) ?? 100
        maximumCents = try c.decodeIfPresent(Int.self, forKey: .maximumCents) ?? 3000
        integersOnly = try c.decodeIfPresent(Bool.self, forKey: .integersOnly) ?? true
        lowPressure = try c.decodeIfPresent(Bool.self, forKey: .lowPressure) ?? true
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "mint"
    }
    var isValid: Bool {
        minimumCents >= 0 && maximumCents <= Money.limit && minimumCents <= maximumCents &&
        (!integersOnly || (minimumCents % 100 == 0 && maximumCents % 100 == 0))
    }
    var step: Int { integersOnly ? 100 : 1 }
    func spin<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        guard isValid else { return 100 }
        let last = (maximumCents - minimumCents) / step
        let a = Int.random(in: 0...last, using: &rng)
        let index = lowPressure ? min(a, Int.random(in: 0...last, using: &rng)) : a
        return minimumCents + index * step
    }
    func sector(for cents: Int, count: Int = 10) -> Int {
        let n = max(1, (maximumCents - minimumCents) / step + 1)
        return min(count - 1, max(0, ((cents - minimumCents) / step) * count / n))
    }
    func bounds(_ sector: Int, count: Int = 10) -> (low: Int, high: Int)? {
        guard isValid else { return nil }
        let n = max(1, (maximumCents - minimumCents) / step + 1)
        let first = (sector * n + count - 1) / count
        let last = sector == count - 1 ? n - 1 : ((sector + 1) * n + count - 1) / count - 1
        guard first <= last, first < n else { return nil }
        return (minimumCents + first * step, minimumCents + min(last, n - 1) * step)
    }
    func label(_ sector: Int, count: Int = 10) -> String {
        guard let b = bounds(sector, count: count) else { return "" }
        let text = { (c: Int) in integersOnly ? String(c / 100) : Money.text(c) }
        return b.low == b.high ? "+" + text(b.low) : "+" + text(b.low) + "~" + text(b.high)
    }
    func representative(_ sector: Int, count: Int = 10) -> Int {
        let n = max(1, (maximumCents - minimumCents) / step + 1)
        return minimumCents + min(n - 1, (2 * sector + 1) * n / (2 * count)) * step
    }
}

struct DayRecord: Codable, Equatable, Identifiable {
    var day: String
    var amountCents: Int
    var spunCents: Int
    var isSaved: Bool
    var isMakeup: Bool
    var isDeleted: Bool
    var id: String { day }
    init(day: String, amountCents: Int, isSaved: Bool = false, isMakeup: Bool = false,
         spunCents: Int? = nil, isDeleted: Bool = false) {
        self.day = day; self.amountCents = amountCents; self.spunCents = spunCents ?? amountCents
        self.isSaved = isSaved; self.isMakeup = isMakeup; self.isDeleted = isDeleted
    }
    enum CodingKeys: String, CodingKey { case day, amountCents, spunCents, isSaved, isMakeup, isDeleted }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        spunCents = try c.decodeIfPresent(Int.self, forKey: .spunCents) ?? amountCents
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        isMakeup = try c.decodeIfPresent(Bool.self, forKey: .isMakeup) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}

struct Goal: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var targetCents: Int = 200_000
    var deadline: Date?
    var wheel: WheelConfig = WheelConfig()
    var records: [DayRecord] = []
    var announcedAchievements: [String] = []
    var hasTarget: Bool { targetCents > 0 }

    mutating func recordSpin<R: RandomNumberGenerator>(on day: String, using rng: inout R) -> Int? {
        guard !records.contains(where: { $0.day == day }) else { return nil }
        let amount = wheel.spin(using: &rng)
        records.append(DayRecord(day: day, amountCents: amount, isSaved: true))
        return amount
    }

    @discardableResult
    mutating func setSaved(on day: String, to saved: Bool) -> Bool {
        guard let index = records.firstIndex(where: { $0.day == day && !$0.isDeleted }),
              records[index].isSaved != saved else { return false }
        records[index].isSaved = saved
        return true
    }
    init(id: UUID = UUID(), name: String = "", targetCents: Int = 200_000, deadline: Date? = nil,
         wheel: WheelConfig = WheelConfig(), records: [DayRecord] = [], announcedAchievements: [String] = []) {
        self.id = id; self.name = name; self.targetCents = targetCents; self.deadline = deadline
        self.wheel = wheel; self.records = records; self.announcedAchievements = announcedAchievements
    }
    enum CodingKeys: String, CodingKey { case id, name, targetCents, deadline, wheel, records, announcedAchievements }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        targetCents = try c.decodeIfPresent(Int.self, forKey: .targetCents) ?? 200_000
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        wheel = try c.decodeIfPresent(WheelConfig.self, forKey: .wheel) ?? WheelConfig()
        records = try c.decodeIfPresent([DayRecord].self, forKey: .records) ?? []
        announcedAchievements = try c.decodeIfPresent([String].self, forKey: .announcedAchievements) ?? []
    }
}

enum DayKey {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }
    static func key(_ date: Date, calendar: Calendar = calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }
    static func date(_ key: String, calendar: Calendar = calendar) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)),
              self.key(d, calendar: calendar) == key else { return nil }
        return d
    }
    static func adding(_ days: Int, to date: Date, calendar: Calendar = calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

struct CalendarDay: Identifiable {
    var date: Date
    var key: String
    var record: DayRecord?
    var id: String { key }
}

enum SaveCore {
    static func saved(_ records: [DayRecord]) -> [DayRecord] { records.filter { $0.isSaved && !$0.isDeleted } }
    static func total(_ records: [DayRecord]) -> Int { saved(records).reduce(0) { $0 + $1.amountCents } }
    static func streak(_ records: [DayRecord], today: Date, calendar: Calendar = DayKey.calendar) -> Int {
        let keys = Set(saved(records).map(\.day))
        var cursor = calendar.startOfDay(for: today)
        if !keys.contains(DayKey.key(cursor, calendar: calendar)) { cursor = DayKey.adding(-1, to: cursor, calendar: calendar) }
        var count = 0
        while keys.contains(DayKey.key(cursor, calendar: calendar)) {
            count += 1; cursor = DayKey.adding(-1, to: cursor, calendar: calendar)
        }
        return count
    }
    static func month(_ date: Date, records: [DayRecord], calendar: Calendar = DayKey.calendar) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return days.compactMap { day in
            guard let d = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return nil }
            let key = DayKey.key(d, calendar: calendar)
            return CalendarDay(date: d, key: key, record: records.first { $0.day == key && !$0.isDeleted })
        }
    }
    static func makeupRemaining(usage: [String: Int], today: Date, calendar: Calendar = DayKey.calendar) -> Int {
        max(0, 3 - (usage[String(DayKey.key(today, calendar: calendar).prefix(7))] ?? 0))
    }
    static func achievements(_ records: [DayRecord], today: Date, calendar: Calendar = DayKey.calendar) -> [String] {
        let days = streak(records, today: today, calendar: calendar), cents = total(records)
        return [7, 30, 100, 365].filter { days >= $0 }.map { "streak-\($0)" } +
            [100_000, 500_000].filter { cents >= $0 }.map { "total-\($0)" }
    }
    static func special(_ cents: Int, config: WheelConfig) -> Bool {
        [6600, 8800, 16800, 52000].contains(cents) || (cents > 0 && cents % 1000 == 0) || cents == config.maximumCents
    }
    static func progress(_ goal: Goal) -> Double {
        guard goal.targetCents > 0 else { return 0 }
        return min(1, Double(total(goal.records)) / Double(goal.targetCents))
    }

    static func expectedDailyCents(_ config: WheelConfig) -> Double {
        guard config.isValid else { return 0 }
        let last = Double((config.maximumCents - config.minimumCents) / config.step)
        let expectedIndex = config.lowPressure ? last * (2 * last + 1) / (6 * (last + 1)) : last / 2
        return Double(config.minimumCents) + Double(config.step) * expectedIndex
    }

    static func centeredRange(remainingCents: Int, days: Int, theme: String = "mint") -> WheelConfig? {
        guard (1...Money.limit).contains(remainingCents), days > 0 else { return nil }
        let dailyYuan = Double(remainingCents) / Double(days) / 100
        let unit = dailyYuan >= 10 ? 5.0 : 1.0
        var low = max(1, (dailyYuan * 0.4 / unit).rounded(.down) * unit)
        var high = ((2 * dailyYuan - low) / unit).rounded(.up) * unit
        if high <= low { high = low + unit }
        let limitYuan = Double(Money.limit / 100)
        if high > limitYuan {
            high = limitYuan
            low = min(high, max(low, ((2 * dailyYuan - high) / unit).rounded(.up) * unit))
        }
        let config = WheelConfig(minimumCents: Int(low) * 100, maximumCents: Int(high) * 100,
                                 integersOnly: true, lowPressure: false, theme: theme)
        return config.isValid ? config : nil
    }

    static func suggestedRange(remainingCents: Int, days: Int, integersOnly: Bool,
                               lowPressure: Bool, theme: String = "mint") -> WheelConfig? {
        guard (1...Money.limit).contains(remainingCents), days > 0 else { return nil }
        let daily = Double(remainingCents) / Double(days)
        let step = integersOnly ? 100 : 1
        let limit = Money.limit / step
        var lower = Int((daily * 0.1 / Double(step)).rounded(.down))
        var result = WheelConfig(minimumCents: lower * step, maximumCents: Money.limit,
                                 integersOnly: integersOnly, lowPressure: lowPressure, theme: theme)
        if expectedDailyCents(result) < daily {
            var upper = limit
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                result.minimumCents = middle * step
                if expectedDailyCents(result) >= daily { upper = middle }
                else { lower = middle + 1 }
            }
        }
        result.minimumCents = lower * step
        var upper = limit
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            result.maximumCents = middle * step
            if expectedDailyCents(result) >= daily { upper = middle }
            else { lower = middle + 1 }
        }
        result.maximumCents = lower * step
        return result
    }

    static func estimatedDays(remainingCents: Int, dailyCents: Double) -> Int? {
        if remainingCents <= 0 { return 0 }
        guard dailyCents.isFinite, dailyCents > 0 else { return nil }
        let days = ceil(Double(remainingCents) / dailyCents)
        guard days < Double(Int.max) else { return nil }
        return Int(days)
    }

    static func remainingDays(until deadline: Date, today: Date, savedToday: Bool,
                              calendar: Calendar = DayKey.calendar) -> Int {
        let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                                to: calendar.startOfDay(for: deadline)).day ?? 0
        return max(0, difference + (savedToday ? 0 : 1))
    }

    static func projectedCompletion(_ goal: Goal, today: Date,
                                    calendar: Calendar = DayKey.calendar) -> Date? {
        guard goal.hasTarget else { return nil }
        let key = DayKey.key(today, calendar: calendar)
        let records = saved(goal.records).filter { $0.day <= key }
        let remaining = max(0, goal.targetCents - total(records))
        guard remaining > 0 else { return today }
        let savedToday = records.contains { $0.day == key }
        var daily = expectedDailyCents(goal.wheel)
        if let first = records.map(\.day).min(), let start = DayKey.date(first, calendar: calendar) {
            let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                 to: calendar.startOfDay(for: today)).day ?? 0
            daily = Double(total(records)) / Double(max(1, elapsed + (savedToday ? 1 : 0)))
        }
        guard let days = estimatedDays(remainingCents: remaining, dailyCents: daily) else { return nil }
        return calendar.date(byAdding: .day, value: max(0, days - (savedToday ? 0 : 1)), to: today)
    }
}

struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
