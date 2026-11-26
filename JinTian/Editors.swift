import SwiftUI

struct WheelSettingsView: View {
    var recalculate = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var minimum = "1"
    @State private var maximum = "30"
    @State private var integers = true
    @State private var lowPressure = true
    @State private var theme = "mint"
    @State private var reminder = false
    @State private var widgetPrivacy = true
    @State private var reminderTime = Date()
    @State private var error: String?
    @State private var targetAmount = "2000"
    @State private var dayCount = "30"
    @State private var useDeadline = false
    @State private var targetDeadline = Date()
    @State private var appliedTarget: Int?
    @State private var appliedDeadline: Date?
    private var remainingCents: Int? {
        guard let target = Money.parse(targetAmount), target > 0 else { return nil }
        return max(0, target - model.total)
    }
    private var availableDays: Int {
        if useDeadline {
            return SaveCore.remainingDays(until: targetDeadline, today: model.now, savedToday: model.todayRecord?.isSaved == true)
        }
        return Int(dayCount) ?? 0
    }
    private var recommendation: WheelConfig? {
        guard let remainingCents, planDeadline != nil else { return nil }
        return SaveCore.suggestedRange(remainingCents: remainingCents, days: availableDays,
                                       integersOnly: integers, lowPressure: lowPressure, theme: theme)
    }
    private var planDeadline: Date? {
        guard availableDays > 0 else { return nil }
        let offset = availableDays - (model.todayRecord?.isSaved == true ? 0 : 1)
        guard let date = useDeadline ? targetDeadline : DayKey.calendar.date(byAdding: .day, value: offset, to: model.now),
              (1...9999).contains(DayKey.calendar.component(.year, from: date)) else { return nil }
        return date
    }
    private var config: WheelConfig? {
        guard let min = Money.parse(minimum), let max = Money.parse(maximum) else { return nil }
        let result = WheelConfig(minimumCents: min, maximumCents: max, integersOnly: integers, lowPressure: lowPressure, theme: theme)
        return result.isValid ? result : nil
    }
    var body: some View {
        SheetFrame(title: L.t("转盘设置")) {
            Form {
                goalCalculator
                Section(L.t("金额范围（元）")) {
                    HStack {
                        TextField(L.t("最小金额"), text: $minimum).keyboardType(.decimalPad).accessibilityIdentifier("minimumAmount")
                        Text("~")
                        TextField(L.t("最大金额"), text: $maximum).keyboardType(.decimalPad).accessibilityIdentifier("maximumAmount")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach([[0, 5], [1, 20], [1, 30], [1, 100], [0, 200]], id: \.self) { range in
                                Button("\(range[0])~\(range[1])") { minimum = String(range[0]); maximum = String(range[1]) }
                                    .buttonStyle(.bordered).accessibilityIdentifier("preset-\(range[1])")
                            }
                        }
                    }
                    Toggle(L.t("仅整数"), isOn: $integers).accessibilityIdentifier("integersOnly")
                    Toggle(L.t("低压力模式"), isOn: $lowPressure).accessibilityIdentifier("lowPressure")
                    Text(L.t("低压力模式会更容易转到小金额；每天只转一次，修改设置不会改变今天的结果。"))
                        .font(.caption).foregroundStyle(Palette.sub)
                    if let config, let remainingCents {
                        estimate(config, remaining: remainingCents)
                            .accessibilityIdentifier("manualEstimate")
                    }
                    if let config { WheelView(config: config).frame(height: 160).frame(maxWidth: .infinity) }
                }.listRowBackground(Palette.card)
                Section(Launch.isFree ? L.t("主题配色") : L.t("主题配色（高级）")) {
                    Picker(L.t("主题"), selection: $theme) {
                        Text(L.t("薄荷绿")).tag("mint")
                        if model.premium {
                            Text(L.t("暖灰棕")).tag("peach")
                            Text(L.t("紫罗兰")).tag("violet")
                        }
                    }.disabled(!model.premium)
                    if !model.premium { Button(L.t("解锁更多配色")) { model.sheet = .paywall } }
                }.listRowBackground(Palette.card)
                Section(Launch.isFree ? L.t("每天提醒") : L.t("每天提醒（高级）")) {
                    Toggle(L.t("提醒我转盘"), isOn: $reminder).disabled(!model.premium)
                    DatePicker(L.t("提醒时间"), selection: $reminderTime, displayedComponents: .hourAndMinute).disabled(!model.premium || !reminder)
                    Text(L.t("今天已经转过就不再提醒。每次打开 App 会安排未来 30 天的提醒。"))
                        .font(.caption).foregroundStyle(Palette.sub)
                    if !model.premium { Button(L.t("解锁每天提醒")) { model.sheet = .paywall } }
                }.listRowBackground(Palette.card)
                Section(L.t("隐私")) {
                    Toggle(L.t("小组件隐藏金额"), isOn: $widgetPrivacy).accessibilityIdentifier("widgetPrivacy")
                }.listRowBackground(Palette.card)
                if let error { Text(error).foregroundStyle(.red) }
                Button(L.t("保存")) {
                    guard let config else { error = L.t("请输入有效范围：0～1000000 元，整数模式不能有小数。") ; return }
                    model.data.widgetPrivacy = widgetPrivacy
                    model.updateGoal {
                        $0.wheel = config
                        if let appliedTarget {
                            $0.targetCents = appliedTarget
                            $0.deadline = appliedDeadline
                        }
                    }
                    let c = DayKey.calendar.dateComponents([.hour, .minute], from: reminderTime)
                    Task {
                        if model.premium { await model.setReminder(enabled: reminder, minute: (c.hour ?? 20) * 60 + (c.minute ?? 0)) }
                        if model.message == nil { dismiss() }
                    }
                }.accessibilityIdentifier("saveWheel")
            }
            .scrollDismissesKeyboard(.interactively).keyboardDoneButton()
            .onAppear {
                let wheel = model.goal.wheel
                minimum = Money.text(wheel.minimumCents); maximum = Money.text(wheel.maximumCents)
                integers = wheel.integersOnly; lowPressure = wheel.lowPressure
                theme = model.premium ? wheel.theme : "mint"
                reminder = model.data.reminderEnabled
                widgetPrivacy = model.data.widgetPrivacy
                reminderTime = DayKey.calendar.date(bySettingHour: model.data.reminderMinute / 60, minute: model.data.reminderMinute % 60, second: 0, of: model.now) ?? model.now
                targetAmount = Money.text(model.goal.targetCents)
                useDeadline = model.goal.deadline != nil
                targetDeadline = model.goal.deadline ?? DayKey.adding(29, to: model.now)
                if recalculate, let recommendation {
                    minimum = Money.text(recommendation.minimumCents)
                    maximum = Money.text(recommendation.maximumCents)
                }
            }
        }
    }
    private var goalCalculator: some View {
        Section(L.t("按目标算")) {
            TextField(L.t("目标金额（元）"), text: $targetAmount).keyboardType(.decimalPad)
                .accessibilityIdentifier("calculatorTarget")
            Toggle(L.t("使用截止日期"), isOn: $useDeadline).accessibilityIdentifier("calculatorUseDeadline")
            if useDeadline {
                DatePicker(L.t("截止日期"), selection: $targetDeadline, displayedComponents: .date)
                    .accessibilityIdentifier("calculatorDeadline")
            } else {
                TextField(L.t("计划天数"), text: $dayCount).keyboardType(.numberPad)
                    .accessibilityIdentifier("calculatorDays")
            }
            if model.total > 0, let remainingCents {
                Text(L.f("扣除已存，还需 %@", Money.yuan(remainingCents))).font(.caption).foregroundStyle(Palette.sub)
            }
            if let recommendation, let remainingCents {
                estimate(recommendation, remaining: remainingCents).accessibilityIdentifier("goalEstimate")
                Text(L.f("建议范围 %@～%@", Money.yuan(recommendation.minimumCents), Money.yuan(recommendation.maximumCents)))
                    .font(.subheadline).foregroundStyle(Palette.mint)
            } else {
                Text(L.t("请输入未完成的目标金额及大于 0 的天数，或有效截止日期。"))
                    .font(.caption).foregroundStyle(Palette.sub)
            }
            Button(L.t("一键应用范围")) {
                guard let recommendation, let target = Money.parse(targetAmount) else { return }
                minimum = Money.text(recommendation.minimumCents)
                maximum = Money.text(recommendation.maximumCents)
                appliedTarget = target
                appliedDeadline = planDeadline
            }.disabled(recommendation == nil).accessibilityIdentifier("applyGoalRange")
            Text(appliedTarget == nil ? L.t("应用后点击保存，将同时更新目标金额和截止日期。") : L.t("范围已应用，点击保存生效。"))
                .font(.caption).foregroundStyle(Palette.sub)
        }
        .listRowBackground(Palette.card)
        .onChange(of: targetAmount) { _, _ in appliedTarget = nil }
        .onChange(of: dayCount) { _, _ in appliedTarget = nil }
        .onChange(of: useDeadline) { _, _ in appliedTarget = nil }
        .onChange(of: targetDeadline) { _, _ in appliedTarget = nil }
    }
    private func estimate(_ wheel: WheelConfig, remaining: Int) -> some View {
        let expectation = SaveCore.expectedDailyCents(wheel)
        return Group {
            if let days = SaveCore.estimatedDays(remainingCents: remaining, dailyCents: expectation) {
                Text(L.f("平均每天约 %@，预计 %@ 天存满", Money.yuan(Int(expectation.rounded(.up))), String(days)))
            } else {
                Text(L.t("当前范围每天为 0，请提高最大金额。"))
            }
        }.font(.caption).foregroundStyle(Palette.sub)
    }
}

struct GoalsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = "2000"
    @State private var hasTarget = true
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var error: String?
    var body: some View {
        SheetFrame(title: L.t("存钱目标")) {
            Form {
                Section(L.t("我的目标")) {
                    ForEach(model.data.goals) { goal in
                        Button { model.selectGoal(goal.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(L.goalName(goal)).foregroundStyle(Palette.ink)
                                    Text(Money.yuan(SaveCore.total(goal.records))).font(.caption).foregroundStyle(Palette.sub)
                                }
                                Spacer()
                                if goal.id == model.goal.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }.accessibilityIdentifier("selectGoal-" + goal.id.uuidString)
                    }
                    Button(Launch.isFree ? L.t("新增目标") : L.t("新增目标（高级）")) { model.addGoal() }.accessibilityIdentifier("addGoal")
                    if !Launch.isFree {
                        Text(L.t("免费版可持续使用第一个目标，其他目标的已有记录始终可以查看和修改。"))
                            .font(.caption).foregroundStyle(Palette.sub)
                    }
                }.listRowBackground(Palette.card)
                Section(L.t("编辑当前目标")) {
                    TextField(L.t("目标名称"), text: $name).accessibilityIdentifier("goalName")
                    Toggle(L.t("设置存钱目标"), isOn: $hasTarget).accessibilityIdentifier("goalEnabled")
                    if hasTarget {
                    TextField(L.t("目标金额（元）"), text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("goalAmount")
                    Toggle(L.t("设置截止日期"), isOn: $hasDeadline)
                    if hasDeadline { DatePicker(L.t("截止日期"), selection: $deadline, displayedComponents: .date) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(L.t("保存目标")) {
                        guard let cents = hasTarget ? Money.parse(amount) : 0,
                              (!hasTarget || cents > 0), name.count <= 40 else {
                            error = L.t("目标金额需大于 0，名称最多 40 字。") ; return
                        }
                        let newDeadline: Date? = hasTarget && hasDeadline ? deadline : nil
                        let planChanged = cents != model.goal.targetCents || newDeadline != model.goal.deadline
                        var newWheel: WheelConfig?
                        if planChanged, let newDeadline {
                            let days = SaveCore.remainingDays(until: newDeadline, today: model.now,
                                                              savedToday: model.todayRecord?.isSaved == true)
                            newWheel = SaveCore.centeredRange(remainingCents: max(0, cents - model.total), days: days,
                                                              theme: model.goal.wheel.theme)
                        }
                        model.updateGoal {
                            $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines); $0.targetCents = cents; $0.deadline = newDeadline
                            if let newWheel { $0.wheel = newWheel }
                        }
                        dismiss()
                    }.accessibilityIdentifier("saveGoal")
                }.listRowBackground(Palette.card)
            }.scrollDismissesKeyboard(.interactively).keyboardDoneButton().onAppear(perform: load).onChange(of: model.goal.id) { _, _ in load() }
        }
    }
    private func load() {
        name = model.goal.name; amount = model.goal.hasTarget ? Money.text(model.goal.targetCents) : "2000"
        hasTarget = model.goal.hasTarget
        hasDeadline = model.goal.deadline != nil; deadline = model.goal.deadline ?? model.now; error = nil
    }
}

struct RecordEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: String
    @State private var amount = "0"
    @State private var saved = true
    @State private var confirmDelete = false
    @State private var error: String?
    private var record: DayRecord? { model.goal.records.first { $0.day == day } }
    private var mustSpin: Bool { day == model.todayKey && record == nil }
    var body: some View {
        SheetFrame(title: day) {
            Form {
                if mustSpin { Text(L.t("今天先转一次，再来修改或确认记录。")) }
                else {
                    Section {
                        TextField(L.t("金额（元）"), text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("recordAmount")
                        Toggle(L.t("已存"), isOn: $saved).accessibilityIdentifier("recordSaved")
                        if let record { Text(L.f("最初转到 %@", Money.yuan(record.spunCents))).font(.caption).foregroundStyle(Palette.sub) }
                    }.listRowBackground(Palette.card)
                    if day < model.todayKey {
                        Text(L.f("本月剩余 %@ 张补签卡，所有目标共用。", String(SaveCore.makeupRemaining(usage: model.data.makeupUsage, today: model.now))))
                            .font(.footnote)
                        Text(L.t("补存过去未存的日期需用补签卡；修改已存金额免费。删除或取消已存不退补签卡。"))
                            .font(.caption).foregroundStyle(Palette.sub)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(L.t("保存记录")) {
                        guard let cents = Money.parse(amount) else { error = L.t("请输入有效金额，最多两位小数。") ; return }
                        if model.edit(day: day, cents: cents, saved: saved) { dismiss() }
                    }.accessibilityIdentifier("saveRecord")
                    if record != nil && record?.isDeleted != true {
                        Button(L.t("删除这天记录"), role: .destructive) { confirmDelete = true }.accessibilityIdentifier("deleteRecord")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively).keyboardDoneButton()
            .onAppear { amount = Money.text(record?.amountCents ?? 0); saved = record?.isDeleted == true ? true : (record?.isSaved ?? true) }
            .confirmationDialog(L.t("删除后不计入累计和连续天数，今天不能重新转盘。"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L.t("删除"), role: .destructive) { model.delete(day: day); dismiss() }.accessibilityIdentifier("confirmDelete")
            }
        }
    }
}
