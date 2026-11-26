import Foundation
import UserNotifications

enum ReminderScheduler {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    static func reschedule(data: AppData, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("spinsave-") }.map(\.identifier))
        guard data.reminderEnabled, data.entitlement.hasPro(at: now) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let calendar = DayKey.calendar
        for offset in 0..<30 {
            let date = DayKey.adding(offset, to: now)
            let key = DayKey.key(date)
            if data.selectedGoal.records.contains(where: { $0.day == key }) { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = data.reminderMinute / 60; components.minute = data.reminderMinute % 60
            components.second = 0; components.timeZone = calendar.timeZone
            guard let fire = calendar.date(from: components), fire > now, data.entitlement.hasPro(at: fire) else { continue }
            let content = UNMutableNotificationContent()
            content.title = L.t("今天存多少"); content.body = L.t("今天还没转哦，给自己的小目标存一点。")
            content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "spinsave-" + key, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            } catch { /* OS may deny scheduling; the setting screen reports authorization separately. */ }
        }
    }
}
