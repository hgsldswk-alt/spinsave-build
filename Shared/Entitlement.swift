import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen: Date
    var trialClaimedAt: Date?
    var purchasedPro: Bool
    var proStartedAt: Date?
    init(firstOpen: Date = Date(), trialClaimedAt: Date? = nil, purchasedPro: Bool = false, proStartedAt: Date? = nil) {
        self.firstOpen = firstOpen; self.trialClaimedAt = trialClaimedAt; self.purchasedPro = purchasedPro; self.proStartedAt = proStartedAt
    }
    enum CodingKeys: String, CodingKey { case firstOpen, trialClaimedAt, purchasedPro, proStartedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstOpen = try c.decodeIfPresent(Date.self, forKey: .firstOpen) ?? Date()
        trialClaimedAt = try c.decodeIfPresent(Date.self, forKey: .trialClaimedAt)
        purchasedPro = try c.decodeIfPresent(Bool.self, forKey: .purchasedPro) ?? false
        proStartedAt = try c.decodeIfPresent(Date.self, forKey: .proStartedAt)
    }
    var trialStart: Date {
        if let claimed = trialClaimedAt { return min(firstOpen, claimed) }
        return max(firstOpen, proStartedAt ?? .distantPast)
    }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86400) }
    func isPremium(at now: Date) -> Bool { purchasedPro || (now.addingTimeInterval(600) >= trialStart && now < trialEnd) }
    func remainingDays(at now: Date) -> Int { max(0, min(30, Int(ceil(trialEnd.timeIntervalSince(now) / 86400)))) }
}
