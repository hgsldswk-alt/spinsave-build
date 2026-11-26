import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var year = DayKey.calendar.component(.year, from: Date())
    private var years: [Int] {
        Array(Set(model.goal.records.compactMap { Int($0.day.prefix(4)) } + [DayKey.calendar.component(.year, from: model.now)])).sorted(by: >)
    }
    private var yearly: [DayRecord] { SaveCore.saved(model.goal.records).filter { $0.day.hasPrefix(String(year) + "-") } }
    private func total(month: Int) -> Int {
        let prefix = String(format: "%04d-%02d", year, month)
        return yearly.filter { $0.day.hasPrefix(prefix) }.reduce(0) { $0 + $1.amountCents }
    }
    var body: some View {
        SheetFrame(title: L.t("统计与年度回顾")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker(L.t("年份"), selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                    Text(Money.yuan(SaveCore.total(yearly))).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(Palette.mint)
                    Text(L.f("这一年，认真存下了 %@ 天", String(yearly.count))).foregroundStyle(Palette.sub)
                    Chart(1...12, id: \.self) { month in
                        BarMark(x: .value(L.t("月份"), String(month)), y: .value(L.t("金额（分）"), total(month: month)))
                            .foregroundStyle(Palette.mint.gradient).cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel { if let cents = value.as(Int.self) { Text(Money.yuan(cents)) } }
                        }
                    }
                    .frame(height: 230).card().accessibilityIdentifier("savingsChart")
                    Text(L.t("成就徽章")).font(.headline)
                    let earned = Set(model.goal.announcedAchievements + SaveCore.achievements(model.goal.records, today: model.now))
                    let ids = ["streak-7", "streak-30", "streak-100", "streak-365", "total-100000", "total-500000", "goal"].filter { earned.contains($0) }
                    if ids.isEmpty { Text(L.t("从第一天开始，下一枚徽章正在路上。")) }
                    ForEach(ids, id: \.self) { id in Label(L.achievement(id), systemImage: "medal.fill").foregroundStyle(Palette.mint) }
                    Button(L.t("分享年度回顾")) { model.share(.annual, year: year, directly: false) }.accessibilityIdentifier("shareAnnual")
                }.padding(24)
            }
        }
    }
}
