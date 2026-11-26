import SwiftUI
import StoreKit
import UIKit

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0
    @State private var spinning = false
    @State private var spinTask: Task<Void, Never>?
    @State private var showPasteHint = false
    @State private var recalculateRange = false
    @State private var undoNotice: UndoNotice?
    @State private var undoTask: Task<Void, Never>?
    @State private var pendingSavedFeedback = false
    private struct UndoNotice: Equatable {
        let goalID: UUID
        let day: String
        let cents: Int
    }
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                topBar
                header
                if showPasteHint { importRow }
                if !model.freeGoal {
                    Button(L.t("此目标的记录永久保留，解锁后可继续为多个目标转盘。")) { model.sheet = .paywall }
                        .font(.footnote)
                }
                if let record = model.todayRecord, !spinning { result(record) }
                else {
                    VStack(spacing: 10) {
                        Text(L.t("今天，给未来存一点")).font(.title3.bold())
                        WheelView(config: model.goal.wheel, rotation: rotation, spinning: spinning, action: spin)
                            .frame(maxWidth: 366)
                        Text(L.t("每天转一次，让小小的坚持有惊喜")).font(.footnote).foregroundStyle(Palette.sub)
                    }.padding(.vertical, 8)
                }
                MonthCalendarView()
                HStack(spacing: 0) {
                    footerButton("目标", icon: "flag", id: "openGoals") { model.sheet = .goals }
                    footerButton("统计", icon: "chart.bar", id: "openStatistics") { model.show(.statistics, requiresPremium: true) }
                }.padding(.vertical, 6)
                if !Launch.isFree { Button(model.data.entitlement.purchasedPro ? L.t("已解锁高级版") : L.t("小组件、提醒与更多惊喜")) { model.sheet = .paywall }
                    .font(.footnote).foregroundStyle(Palette.sub).accessibilityIdentifier("openPaywall") }
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.mint)
        .accessibilityIdentifier("homeView")
        .safeAreaInset(edge: .bottom) {
            if let notice = undoNotice {
                HStack {
                    Label(L.f("已记上 %@", "¥" + Money.display(notice.cents, integersOnly: model.goal.wheel.integersOnly)), systemImage: "checkmark")
                        .font(.subheadline).foregroundStyle(Color.white)
                    Spacer(minLength: 8)
                    Button(L.t("撤销")) {
                        model.undoToday(goalID: notice.goalID, day: notice.day)
                        clearUndo()
                    }.font(.subheadline.bold()).foregroundStyle(Palette.coinLight)
                        .frame(minHeight: 44).accessibilityIdentifier("undoToday")
                }.padding(.horizontal, 18).padding(.vertical, 4)
                    .background(Palette.color(0x1E2A25), in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("savedNotice")
            }
        }
        .sheet(item: $model.sheet, onDismiss: {
            if undoNotice == nil {
                if pendingSavedFeedback { finishSaving() }
                else { model.checkAchievements() }
            }
        }) { route in
            switch route {
            case .settings: WheelSettingsView(recalculate: recalculateRange)
            case .goals: GoalsView()
            case .statistics: StatisticsView()
            case .share: SharingView()
            case .quickShare: ShareActivity(items: model.sharedItems)
            case .paywall: PaywallView()
            case .achievement: AchievementView()
            case .day(let day): RecordEditorView(day: day)
            }
        }
        .appMessage(model)
        .onReceive(timer) { _ in model.refreshDate() }
        .onAppear {
            refreshPasteHint()
            syncRotation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in refreshPasteHint() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshPasteHint() }
        .onChange(of: model.goal.id) { _, _ in clearUndo(); syncRotation() }
        .onChange(of: model.goal.wheel) { _, _ in syncRotation() }
        .onChange(of: model.todayKey) { _, _ in clearUndo() }
        .onChange(of: model.todayRecord) { _, record in
            if record?.spunCents != nil { syncRotation() }
            if record?.isSaved != true || record?.isDeleted == true || (undoNotice != nil && record?.amountCents != undoNotice?.cents) {
                clearUndo()
            }
        }
        .onDisappear { spinTask?.cancel(); spinning = false; clearUndo() }
    }
    private var importRow: some View {
        HStack {
            Text(L.t("朋友发了转盘口令？粘贴")).font(.caption)
            Spacer(minLength: 0)
            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in model.importCode(strings.joined(separator: "\n")) }
            }.labelStyle(.iconOnly).accessibilityIdentifier("pasteCode")
            Button {
                model.dismissPasteHint(changeCount: UIPasteboard.general.changeCount)
                showPasteHint = false
            } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                .accessibilityLabel(L.t("关闭")).accessibilityIdentifier("dismissPasteHint")
        }.padding(12).background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
    private func refreshPasteHint() {
        if model.isolated && ProcessInfo.processInfo.arguments.contains("-hide-paste-hint") {
            showPasteHint = false
            return
        }
        showPasteHint = UIPasteboard.general.hasStrings && model.shouldShowPasteHint(changeCount: UIPasteboard.general.changeCount)
    }
    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("今天存多少")).font(.system(size: 28, weight: .heavy)).minimumScaleFactor(0.65).lineLimit(1)
                Text(model.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.caption).foregroundStyle(Palette.sub)
            }
            Spacer(minLength: 0)
            topButton("分享", icon: "square.and.arrow.up", id: "openShare") { model.share(directly: false) }
            topButton("转盘设置", icon: "slider.horizontal.3", id: "openSettings") {
                recalculateRange = false
                model.sheet = .settings
            }
        }
    }
    private func topButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 38, height: 38)
                .background(Palette.card, in: Circle()).overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }.accessibilityLabel(L.t(title)).accessibilityIdentifier(id)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("连续打卡")).font(.caption).foregroundStyle(Palette.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(model.streak)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("streakValue")
                        Text(L.t("天")).font(.subheadline).foregroundStyle(Palette.sub)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Palette.line).frame(width: 1, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("累计存下")).font(.caption).foregroundStyle(Palette.sub)
                    (Text("¥").font(.system(size: 20, weight: .semibold)) +
                     Text(Money.text(model.total)).font(.system(size: 34, weight: .bold, design: .rounded))).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("totalValue")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.goal.hasTarget {
            Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 600, y: 0)) }
                .stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).clipped()
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(L.goalName(model.goal)).font(.subheadline.bold())
                    Spacer(minLength: 8)
                    goalProgressLabel
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.goalName(model.goal)).font(.subheadline.bold())
                    goalProgressLabel
                }
            }
            GeometryReader { geometry in
                Capsule().fill(Palette.progressTrack)
                Capsule().fill(LinearGradient(colors: [Palette.progressAccent, Palette.mint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * SaveCore.progress(model.goal))
            }.frame(height: 6)
            if model.total < model.goal.targetCents {
                if let projected = SaveCore.projectedCompletion(model.goal, today: model.now) {
                    Text(L.f("按现在进度，预计 %@ 存满", projected.formatted(.dateTime.month().day())))
                        .font(.caption).foregroundStyle(Palette.sub).accessibilityIdentifier("projectedCompletion")
                } else {
                    Text(L.t("当前进度暂无法预计存满日期")).font(.caption).foregroundStyle(Palette.sub)
                }
                if behindSchedule {
                    Button(L.t("重新按剩余天数算范围")) {
                        recalculateRange = true
                        model.sheet = .settings
                    }.font(.caption).accessibilityIdentifier("recalculateRange")
                }
            }
            if let deadline = model.goal.deadline {
                Text(L.f("截止日期 %@", deadline.formatted(date: .abbreviated, time: .omitted))).font(.caption).foregroundStyle(Palette.sub)
            }
            }
            if model.streak == 0 && !SaveCore.saved(model.goal.records).isEmpty {
                Button(L.t("断签了？用补签卡接上坚持")) { model.sheet = .day(DayKey.key(DayKey.adding(-1, to: model.now))) }.font(.caption)
            }
        }.card(decorated: true)
    }
    private var goalProgressLabel: some View {
        Text(Money.yuan(model.total) + " / " + Money.yuan(model.goal.targetCents) + " · " + String(model.goal.targetCents > 0 ? min(100, model.total * 100 / model.goal.targetCents) : 0) + "%")
            .font(.caption).foregroundStyle(Palette.sub).lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityIdentifier("goalProgress")
    }
    private var behindSchedule: Bool {
        guard model.goal.hasTarget, let deadline = model.goal.deadline else { return false }
        guard let projected = SaveCore.projectedCompletion(model.goal, today: model.now) else { return true }
        return DayKey.key(projected) > DayKey.key(deadline)
    }
    private func result(_ record: DayRecord) -> some View {
        VStack(spacing: 8) {
            Text(record.isDeleted ? L.t("今天的记录已删除") : (record.isSaved ?
                L.f("今天存 %@，已记上", "¥" + Money.display(record.amountCents, integersOnly: model.goal.wheel.integersOnly)) : L.t("今天这笔还没记")))
                .font(.title3.bold()).multilineTextAlignment(.center).accessibilityIdentifier("todayStatus")
            WheelView(config: model.goal.wheel, rotation: rotation, result: record)
                .frame(maxWidth: 366)
            if record.isDeleted {
                Button(L.t("查看或恢复记录")) { model.sheet = .day(record.day) }.accessibilityIdentifier("restoreToday")
            } else if !record.isSaved {
                Button {
                    guard model.markSaved() else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showUndo(for: record)
                    finishSaving()
                } label: { Text(L.t("记上")).frame(minWidth: 120) }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("markSaved")
            }
            Button { model.share() } label: {
                Label(L.t(SaveCore.special(record.spunCents, config: model.goal.wheel) ?
                    "今天的幸运数字，晒一下" : "晒一下今天的数"), systemImage: "square.and.arrow.up")
                    .font(.caption).padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Palette.card, in: Capsule()).overlay(Capsule().stroke(Palette.line, lineWidth: 1))
            }.buttonStyle(.plain).foregroundStyle(Palette.mint).accessibilityIdentifier("shareToday")
            if !record.isDeleted {
                Button(L.t("修改今天的记录")) { model.sheet = .day(record.day) }
                    .font(.caption).foregroundStyle(Palette.sub).accessibilityIdentifier("editToday")
            }
        }.frame(maxWidth: .infinity).padding(.top, 4)
    }
    private func showUndo(for record: DayRecord) {
        undoTask?.cancel()
        let notice = UndoNotice(goalID: model.goal.id, day: record.day, cents: record.amountCents)
        undoNotice = notice
        pendingSavedFeedback = true
        undoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, undoNotice == notice else { return }
            undoNotice = nil
            finishSaving()
        }
    }
    private func syncRotation() {
        guard !spinning, let record = model.todayRecord else { return }
        rotation = -Double(model.goal.wheel.sector(for: record.spunCents)) * 36 - 18
    }
    private func clearUndo() {
        undoTask?.cancel()
        undoNotice = nil
        pendingSavedFeedback = false
    }
    private func finishSaving() {
        guard pendingSavedFeedback, undoNotice == nil, model.sheet == nil,
              model.todayRecord?.isSaved == true, model.todayRecord?.isDeleted == false else { return }
        pendingSavedFeedback = false
        model.checkAchievements()
        if model.sheet == nil && ReviewGate.shouldAsk(model) { requestReview() }
    }
    private func footerButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L.t(title), systemImage: icon).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier(id)
    }
    private func spin() {
        guard !spinning, let cents = model.spin() else { return }
        spinning = true
        let goalID = model.goal.id, day = model.todayKey
        let sector = model.goal.wheel.sector(for: cents)
        let target = ceil(rotation / 360) * 360 + 1800 - Double(sector) * 36 - 18
        let seconds = reduceMotion ? 0.15 : (model.isolated ? 0.5 : 3.2)
        let travel = target - rotation
        withAnimation(.timingCurve(1.0 / 3, 1, 2.0 / 3, 1, duration: seconds)) { rotation = target }
        spinTask = Task { @MainActor in
            var elapsed = 0.0
            if !reduceMotion && !model.isolated {
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.prepare()
                for tick in 1...max(1, Int(travel / 36)) {
                    let fraction = min(1, Double(tick) * 36 / travel)
                    let time = seconds * (1 - pow(1 - fraction, 1.0 / 3))
                    try? await Task.sleep(nanoseconds: UInt64(max(0, time - elapsed) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    feedback.impactOccurred(intensity: 0.35)
                    elapsed = time
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds - elapsed) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            spinning = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            model.refreshDate()
            guard model.goal.id == goalID, model.todayKey == day,
                  let record = model.todayRecord, record.isSaved, !record.isDeleted else { return }
            showUndo(for: record)
            finishSaving()
        }
    }
}

struct MonthCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var offset = 0
    private var month: Date { DayKey.calendar.date(byAdding: .month, value: offset, to: model.now) ?? model.now }
    private var days: [CalendarDay] { SaveCore.month(month, records: model.goal.records) }
    private var leading: Int { ((DayKey.calendar.component(.weekday, from: days.first?.date ?? month)) + 5) % 7 }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { offset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel(L.t("上个月")).accessibilityIdentifier("previousMonth")
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide))).font(.headline)
                Spacer()
                Button { offset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(offset >= 0).accessibilityLabel(L.t("下个月")).accessibilityIdentifier("nextMonth")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 5) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text(L.t($0)).font(.caption).foregroundStyle(Palette.sub) }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(days) { day in
                    let saved = day.record?.isSaved == true
                    let today = day.key == model.todayKey
                    let future = day.key > model.todayKey
                    let accent = Palette.accent(model.goal.wheel.theme)
                    Button { model.sheet = .day(day.key) } label: {
                        VStack(spacing: 2) {
                            Text(String(DayKey.calendar.component(.day, from: day.date)))
                                .font(.system(size: 14, weight: saved ? .bold : .medium))
                            if saved, let record = day.record {
                                Text(record.isMakeup ? L.t("补") : "+" + Money.display(record.amountCents, integersOnly: model.goal.wheel.integersOnly))
                                    .font(.system(size: 9.5)).lineLimit(1).minimumScaleFactor(0.6)
                            } else if today {
                                Text(L.t("待存")).font(.system(size: 9.5)).foregroundStyle(Palette.gold)
                            } else { Text(" ").font(.system(size: 9.5)) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(future ? Palette.sub.opacity(0.45) : (saved || today ? accent : Palette.ink))
                        .background(saved ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(today && !saved ? Palette.gold : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain).disabled(day.key > model.todayKey)
                    .accessibilityLabel(day.key + (saved ? " " + L.t("已存") : " " + L.t("未存")))
                    .accessibilityIdentifier("day-" + day.key)
                }
            }
            Text(L.t("点日期查看、修改或补签")).font(.caption).foregroundStyle(Palette.sub)
        }.card()
    }
}
