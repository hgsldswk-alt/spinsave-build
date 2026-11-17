import WidgetKit
import SwiftUI

struct SavingsEntry: TimelineEntry {
    var date: Date
    var data: AppData
    var premium: Bool { data.entitlement.hasPro(at: date) }
    var goal: Goal { data.selectedGoal }
    var today: DayRecord? { goal.records.first { $0.day == DayKey.key(date) && !$0.isDeleted } }
    var status: String {
        guard let today else { return L.t("今天还没转") }
        let label = today.isSaved ? L.t("今天已存") : L.t("今天存")
        return data.widgetPrivacy ? label + " · •••" : label + " " + Money.yuan(today.amountCents)
    }
}

struct SavingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SavingsEntry { SavingsEntry(date: Date(), data: AppData()) }
    func getSnapshot(in context: Context, completion: @escaping (SavingsEntry) -> Void) {
        completion(SavingsEntry(date: Date(), data: (try? Store.load()) ?? AppData()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SavingsEntry>) -> Void) {
        let now = Date(), data = (try? Store.load()) ?? AppData()
        let midnight = DayKey.calendar.startOfDay(for: DayKey.adding(1, to: now))
        var dates = [now, midnight]
        if !Launch.isFree && !data.entitlement.purchasedPro && data.entitlement.trialEnd > now && data.entitlement.trialEnd < midnight {
            dates.append(data.entitlement.trialEnd)
        }
        let entries = dates.sorted().map { SavingsEntry(date: $0, data: data) }
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}

struct SavingsWidgetView: View {
    var entry: SavingsEntry
    @Environment(\.widgetFamily) private var family
    private var streak: Int { SaveCore.streak(entry.goal.records, today: entry.date) }
    var body: some View {
        Group {
            if !entry.premium {
                if family == .accessoryCircular {
                    VStack { Image(systemName: "lock"); Text(L.t("高级版")).font(.caption2) }
                        .accessibilityLabel(L.t("解锁高级版使用小组件"))
                } else {
                    Label(L.t("解锁高级版使用小组件"), systemImage: "lock.fill").font(.caption)
                }
            } else {
                switch family {
                case .accessoryInline:
                    Text(entry.status + " · " + L.f("连续 %@ 天", String(streak)))
                case .accessoryCircular:
                    if entry.goal.hasTarget {
                    Gauge(value: SaveCore.progress(entry.goal)) {
                        Image(systemName: "leaf.fill")
                    } currentValueLabel: { Text(String(streak)) }
                        .gaugeStyle(.accessoryCircular)
                        .accessibilityLabel(L.f("连续 %@ 天", String(streak)))
                    } else {
                        VStack { Image(systemName: "leaf.fill"); Text(String(streak)) }
                            .accessibilityLabel(L.f("连续 %@ 天", String(streak)))
                    }
                case .accessoryRectangular:
                    VStack(alignment: .leading) {
                        Text(entry.status).font(.headline)
                        Text(L.f("连续 %@ 天", String(streak))).font(.caption)
                        if entry.goal.hasTarget { ProgressView(value: SaveCore.progress(entry.goal)) }
                    }
                default:
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L.t("今天存多少"), systemImage: "leaf.fill").font(.caption).foregroundStyle(.secondary)
                            Text(entry.status).font(.headline).minimumScaleFactor(0.7).lineLimit(2)
                            Text(L.f("连续 %@ 天", String(streak))).font(.caption)
                            if entry.goal.hasTarget { ProgressView(value: SaveCore.progress(entry.goal)).tint(.green) }
                        }
                        if family == .systemMedium {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L.goalName(entry.goal)).font(.headline)
                                Text(entry.data.widgetPrivacy ? L.t("金额已隐藏") : Money.yuan(SaveCore.total(entry.goal.records))).font(.title3.bold())
                                if entry.goal.hasTarget {
                                Text(entry.data.widgetPrivacy ? L.f("目标已完成 %@", String(Int(SaveCore.progress(entry.goal) * 100)) + "%") :
                                    L.f("目标 %@", Money.yuan(entry.goal.targetCents))).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct JinTianWidget: Widget {
    let kind = "JinTianWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SavingsProvider()) { SavingsWidgetView(entry: $0) }
            .configurationDisplayName(L.t("今天存多少"))
            .description(L.t("今天的金额、连续天数和目标进度。"))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
