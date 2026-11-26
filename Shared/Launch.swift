import Foundation

enum Launch {
    static let freePeriod = false
    static var isFree: Bool {
        guard freePeriod else { return false }
        let args = ProcessInfo.processInfo.arguments
        return !(args.contains("-paid-mode") || args.contains("-paywall") || args.contains("-expired"))
    }
}

extension Entitlement {
    func hasPro(at now: Date) -> Bool { Launch.isFree || (!Launch.freePeriod && proStartedAt == nil) || isPremium(at: now) }
}
