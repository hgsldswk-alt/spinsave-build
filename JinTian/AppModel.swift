import Foundation
import SwiftUI
import StoreKit
import WidgetKit
import UIKit

enum SheetRoute: Identifiable {
    case settings, goals, statistics, share, quickShare, paywall, achievement, day(String)
    var id: String {
        switch self {
        case .settings: return "settings"
        case .goals: return "goals"
        case .statistics: return "statistics"
        case .share: return "share"
        case .quickShare: return "quickShare"
        case .paywall: return "paywall"
        case .achievement: return "achievement"
        case .day(let day): return day
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var data: AppData
    @Published var now = Date()
    @Published var sheet: SheetRoute?
    @Published var shareKind: ShareKind = .today
    @Published var shareYear: Int?
    @Published var sharedItems: [Any] = []
    @Published var message: String?
    @Published var achievementIDs: [String] = []
    @Published var products: [Product] = []
    @Published var purchasing = false
    @Published var productLoadFailed = false
    private var transactions: Task<Void, Never>?
    private var reminderTask: Task<Void, Never>?
    private var canWrite = true
    let isolated: Bool
    let demo: Bool
    private let storage: UserDefaults
    func shouldShowPasteHint(changeCount: Int) -> Bool {
        storage.object(forKey: "dismissedPasteChangeCount") == nil ||
            storage.integer(forKey: "dismissedPasteChangeCount") != changeCount
    }
    func dismissPasteHint(changeCount: Int) {
        storage.set(changeCount, forKey: "dismissedPasteChangeCount")
    }
    static var supportsFixtures: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    var goal: Goal { data.selectedGoal }
    var todayKey: String { DayKey.key(now) }
    var todayRecord: DayRecord? { goal.records.first { $0.day == todayKey } }
    var premium: Bool { data.entitlement.hasPro(at: now) }
    var streak: Int { SaveCore.streak(goal.records, today: now) }
    var total: Int { SaveCore.total(goal.records) }
    var freeGoal: Bool { premium || goal.id == data.goals.first?.id }
    var proID: String { Bundle.main.object(forInfoDictionaryKey: "JinTianProProductID") as? String ?? "com.hgsldswk.spinsave.pro" }
    var trialID: String { Bundle.main.object(forInfoDictionaryKey: "JinTianTrialProductID") as? String ?? "com.hgsldswk.spinsave.trial" }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        demo = Self.supportsFixtures && arguments.contains("-demo")
        isolated = Self.supportsFixtures && (demo || arguments.contains("-ui-testing"))
        storage = isolated ? UserDefaults(suiteName: "com.hgsldswk.spinsave.fixtures")! : Store.defaults
        if isolated && (demo || arguments.contains("-reset")) { storage.removePersistentDomain(forName: "com.hgsldswk.spinsave.fixtures") }
        do { data = try Store.load(from: storage) }
        catch {
            data = AppData(); canWrite = false
            message = L.t("记录暂时无法读取。原始数据已保留，请关闭 App 后重试，或从设备备份恢复。")
        }
        if demo { data = Self.demoData(now: now, spun: arguments.contains("-spun"), ordinary: arguments.contains("-ordinary")) }
        if isolated && arguments.contains("-onboarded") { data.onboarded = true }
        if isolated, let index = arguments.firstIndex(of: "-clipboard-code"), arguments.indices.contains(index + 1) {
            UIPasteboard.general.string = arguments[index + 1]
        }
        now = Date()
        if !Launch.isFree && data.entitlement.proStartedAt == nil && !(isolated && arguments.contains("-expired")) {
            data.entitlement.proStartedAt = now
        }
        if isolated && arguments.contains("-expired") {
            data.entitlement.firstOpen = now.addingTimeInterval(-31 * 86400); data.entitlement.proStartedAt = data.entitlement.firstOpen
        }
        data.launchCount += 1
        persist()
        if isolated {
            if arguments.contains("-settings") { sheet = .settings }
            else if arguments.contains("-share") { sheet = .share }
            else if arguments.contains("-paywall") || arguments.contains("-expired") { sheet = .paywall }
            if let i = arguments.firstIndex(of: "-import-code"), arguments.indices.contains(i + 1) { importCode(arguments[i + 1]) }
        }
    }
    deinit { transactions?.cancel(); reminderTask?.cancel() }

    func start() async {
        if isolated { return }
        if transactions == nil {
            transactions = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self, !Task.isCancelled else { return }
                    if case .verified(let transaction) = result,
                       [self.proID, self.trialID].contains(transaction.productID) {
                        await self.refreshEntitlements()
                        await transaction.finish()
                    }
                }
            }
        }
        await refreshEntitlements()
        refreshDate()
        scheduleReminders()
        showExpiryIfNeeded()
    }
    func refreshDate() {
        let oldDay = todayKey, wasPremium = premium
        now = Date()
        if oldDay != todayKey || wasPremium != premium {
            WidgetCenter.shared.reloadAllTimelines(); scheduleReminders(); showExpiryIfNeeded()
        }
    }
    func showExpiryIfNeeded() {
        guard !premium, !data.expiryNoticeShown, sheet == nil else { return }
        data.expiryNoticeShown = true; persist(); sheet = .paywall
    }
    func updateGoal(_ change: (inout Goal) -> Void) {
        guard canWrite, let index = data.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        change(&data.goals[index]); persist()
    }
    func persist() {
        guard canWrite else { return }
        do { try Store.save(data, to: storage) }
        catch { message = L.t("保存失败，请稍后重试。") }
        if !isolated { WidgetCenter.shared.reloadAllTimelines(); scheduleReminders() }
    }
    func spin() -> Int? {
        refreshDate()
        guard canWrite else { return nil }
        guard freeGoal else { sheet = .paywall; return nil }
        guard todayRecord == nil else { return nil }
        var rng = SystemRandomNumberGenerator()
        let day = todayKey
        var amount: Int?
        updateGoal { amount = $0.recordSpin(on: day, using: &rng) }
        return amount
    }
    @discardableResult
    func markSaved() -> Bool {
        refreshDate()
        guard canWrite, let record = todayRecord, !record.isSaved, !record.isDeleted else { return false }
        updateGoal { $0.setSaved(on: record.day, to: true) }
        return true
    }
    func undoToday(goalID: UUID, day: String) {
        refreshDate()
        guard canWrite, goal.id == goalID, todayKey == day else { return }
        updateGoal { $0.setSaved(on: day, to: false) }
    }
    func startGoalPlan(targetCents: Int, days: Int) {
        refreshDate()
        guard canWrite, data.startGoalPlan(targetCents: targetCents, days: days, today: now) else { return }
        persist()
    }
    func startCasualSaving() {
        guard canWrite else { return }
        data.startCasualSaving()
        persist()
    }
    func checkAchievements() {
        guard canWrite, data.onboarded, premium, sheet == nil else { return }
        var earned = SaveCore.achievements(goal.records, today: now)
        if goal.hasTarget && total >= goal.targetCents { earned.append("goal") }
        let fresh = earned.filter { !goal.announcedAchievements.contains($0) }
        if !fresh.isEmpty {
            achievementIDs = fresh
            updateGoal { $0.announcedAchievements.append(contentsOf: fresh) }
            sheet = .achievement
        }
    }
    func selectGoal(_ id: UUID) {
        guard canWrite, data.goals.contains(where: { $0.id == id }) else { return }
        data.selectedGoalID = id; persist()
    }
    func addGoal() {
        guard canWrite else { return }
        guard premium else { sheet = .paywall; return }
        guard data.goals.count < 50 else { message = L.t("最多可创建 50 个目标。") ; return }
        let new = Goal(); data.goals.append(new); data.selectedGoalID = new.id; persist()
    }
    @discardableResult
    func importCode(_ text: String, duringOnboarding: Bool = false) -> Bool {
        guard canWrite else { return false }
        guard let imported = ShareCode.decode(text) else { message = L.t("没有识别出口令，请复制完整的转盘口令后重试。") ; return false }
        if duringOnboarding { data.onboarded = true }
        updateGoal {
            $0.name = imported.name; $0.targetCents = imported.targetCents; $0.wheel = imported.wheel
            if !imported.hasTarget { $0.deadline = nil }
        }
        if !duringOnboarding { message = L.t("已导入同款转盘，已有记录和今天的结果会保留。") }
        return true
    }
    func edit(day: String, cents: Int, saved: Bool) -> Bool {
        refreshDate()
        guard canWrite, DayKey.date(day) != nil, day <= todayKey, (0...Money.limit).contains(cents) else { return false }
        let old = goal.records.first { $0.day == day }
        if day == todayKey && old == nil { return false }
        let makeup = day < todayKey && saved && !(old?.isSaved == true && old?.isDeleted == false)
        if makeup {
            guard premium else { message = L.t("补签需要高级版，已有记录仍可免费查看和修改。") ; return false }
            guard SaveCore.makeupRemaining(usage: data.makeupUsage, today: now) > 0 else { message = L.t("本月 3 张补签卡已用完，下月会补充。") ; return false }
            data.makeupUsage[String(todayKey.prefix(7)), default: 0] += 1
        }
        updateGoal { goal in
            var record = old ?? DayRecord(day: day, amountCents: cents)
            record.amountCents = cents; record.isSaved = saved; record.isDeleted = false
            record.isMakeup = record.isMakeup || makeup
            if let i = goal.records.firstIndex(where: { $0.day == day }) { goal.records[i] = record }
            else { goal.records.append(record) }
        }
        return true
    }
    func delete(day: String) {
        updateGoal { goal in
            if let i = goal.records.firstIndex(where: { $0.day == day }) {
                goal.records[i].isDeleted = true; goal.records[i].isSaved = false
            }
        }
    }
    func show(_ route: SheetRoute, requiresPremium: Bool = false) { sheet = requiresPremium && !premium ? .paywall : route }
    func share(_ kind: ShareKind = .today, year: Int? = nil, directly: Bool = true) {
        shareKind = kind; shareYear = year
        guard directly else { sheet = .share; return }
        let renderer = ImageRenderer(content: ShareCard(goal: goal, now: now, kind: kind, selectedYear: year))
        renderer.scale = 2
        guard let image = renderer.uiImage else { message = L.t("分享图生成失败，请重试。") ; return }
        var caption = "#转盘存钱挑战 #今天存多少 " + L.f("已连续存钱 %@ 天", String(streak))
        if let code = ShareCode.encode(goal) { caption += "\n" + L.t("复制这段话，在「今天存多少」点粘贴，一起用同款转盘。") + "\n" + code }
        sharedItems = [image, caption]
        sheet = .quickShare
    }

    func loadProducts() async {
        guard !isolated else { return }
        productLoadFailed = false
        do { products = try await Product.products(for: [proID, trialID]); productLoadFailed = products.isEmpty }
        catch { productLoadFailed = true }
    }
    func purchase(_ id: String) async {
        guard !purchasing, !isolated else { return }
        guard let product = products.first(where: { $0.id == id }) else { message = L.t("商品暂不可用，请稍后重试。") ; return }
        purchasing = true; defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { message = L.t("无法验证购买，请尝试恢复购买。") ; return }
                if transaction.productID == trialID {
                    data.entitlement.trialClaimedAt = min(data.entitlement.trialClaimedAt ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
                }
                await refreshEntitlements(); await transaction.finish()
                if data.entitlement.purchasedPro { sheet = nil }
            case .pending: message = L.t("购买正在等待批准，批准后会自动解锁。")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = L.t("购买未完成，请检查网络后重试。") }
    }
    func restore() async {
        guard !purchasing, !isolated else { return }
        purchasing = true; defer { purchasing = false }
        do {
            try await AppStore.sync(); await refreshEntitlements()
            message = data.entitlement.purchasedPro ? L.t("购买已恢复。") : L.t("已检查购买记录，未找到高级版买断。")
        } catch { message = L.t("恢复购买失败，请稍后重试。") }
    }
    func refreshEntitlements() async {
        guard !isolated else { return }
        var pro = false
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification, transaction.revocationDate == nil else { continue }
            if transaction.productID == proID { pro = true }
            if transaction.productID == trialID {
                let date = transaction.originalPurchaseDate
                data.entitlement.trialClaimedAt = min(data.entitlement.trialClaimedAt ?? date, date)
            }
        }
        data.entitlement.purchasedPro = pro; persist()
    }
    func setReminder(enabled: Bool, minute: Int) async {
        guard premium else { message = L.t("每天提醒需要高级版。") ; return }
        if enabled && !isolated {
            guard await ReminderScheduler.requestPermission() else { message = L.t("通知未开启，请到系统设置允许通知。") ; return }
        }
        data.reminderEnabled = enabled; data.reminderMinute = minute; persist()
    }
    private func scheduleReminders() {
        guard !isolated else { return }
        let previous = reminderTask
        reminderTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await ReminderScheduler.reschedule(data: self.data, now: self.now)
        }
    }
    static func demoData(now: Date, spun: Bool, ordinary: Bool = false) -> AppData {
        var data = AppData()
        var goal = Goal(name: L.t("旅行基金"), targetCents: 200_000)
        for offset in 1...12 {
            goal.records.append(DayRecord(day: DayKey.key(DayKey.adding(-offset, to: now)), amountCents: offset == 12 ? 2750 : 1900, isSaved: true))
        }
        goal.announcedAchievements = SaveCore.achievements(goal.records, today: now)
        if spun { goal.records.append(DayRecord(day: DayKey.key(now), amountCents: ordinary ? 200 : 2000, isSaved: true)) }
        data.onboarded = true
        data.goals = [goal]; data.selectedGoalID = goal.id; return data
    }
}
