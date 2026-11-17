import Foundation

enum ReviewGate {
    @MainActor static func shouldAsk(_ model: AppModel) -> Bool {
        guard !model.isolated, model.data.launchCount >= 5,
              model.now.timeIntervalSince(model.data.entitlement.firstOpen) >= 3 * 86400 else { return false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        guard model.data.reviewedVersion != version else { return false }
        model.data.reviewedVersion = version; model.persist(); return true
    }
}
