import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var choosingGoal = false
    @State private var amount = "5000"
    @State private var days = "100"
    @State private var showPaste = false
    @FocusState private var editing: Bool

    private var target: Int? {
        guard let cents = Money.parse(amount), cents > 0 else { return nil }
        return cents
    }
    private var dayCount: Int? {
        guard let count = Int(days), (1...36500).contains(count) else { return nil }
        return count
    }
    private var range: WheelConfig? {
        guard let target, let dayCount else { return nil }
        return SaveCore.centeredRange(remainingCents: target, days: dayCount, theme: model.goal.wheel.theme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if choosingGoal { goalPage }
                else { choicePage }
            }
            .padding(24).frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.mint)
        .safeAreaInset(edge: .bottom) {
            if choosingGoal {
                Button {
                    guard let target, let dayCount else { return }
                    editing = false
                    model.startGoalPlan(targetCents: target, days: dayCount)
                } label: { Text(L.t("开始存")).frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle()).disabled(range == nil)
                    .accessibilityIdentifier("startSaving")
                    .padding(24).background(Palette.background)
            } else {
                VStack(spacing: 12) {
                    if showPaste {
                        HStack {
                            Text(L.t("用朋友的同款转盘")).font(.subheadline)
                            PasteButton(payloadType: String.self) { strings in
                                Task { @MainActor in
                                    if model.importCode(strings.joined(separator: "\n"), duringOnboarding: true) {
                                        model.dismissPasteHint(changeCount: UIPasteboard.general.changeCount)
                                    }
                                }
                            }.labelStyle(.iconOnly).accessibilityIdentifier("onboardingPaste")
                        }
                    }
                    Text(L.t("以后可以在设置里随时改")).font(.caption).foregroundStyle(Palette.sub)
                }.padding(24).frame(maxWidth: .infinity).background(Palette.background)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L.t("完成")) { editing = false }
            }
        }
        .appMessage(model)
        .onAppear(perform: refreshPaste)
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in refreshPaste() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshPaste() }
    }

    private var choicePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "yensign.circle.fill").font(.system(size: 44)).foregroundStyle(Palette.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("你想怎么存？")).font(.system(size: 32, weight: .heavy))
                    .accessibilityIdentifier("onboardingTitle")
                Text(L.t("每天转一下，转到几就存几。")).foregroundStyle(Palette.sub)
            }.padding(.top, 42)
            VStack(spacing: 16) {
                choice("存够一个数", detail: "比如 100 天存 ¥5000，自动算好每天转多少", highlighted: true, id: "onboardingGoal") {
                    choosingGoal = true
                }
                choice("每天随手存点", detail: "不用设目标，直接开始（每天 +1 到 +20）", highlighted: false, id: "onboardingCasual") {
                    model.startCasualSaving()
                }
            }.padding(.top, 12)
        }.padding(.top, 16)
    }

    private func choice(_ title: String, detail: String, highlighted: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t(title)).font(.title3.bold()).foregroundStyle(Palette.ink)
                    Text(L.t(detail)).font(.subheadline).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Palette.gold)
            }.padding(22).frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(highlighted ? Palette.mint : Palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var goalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                editing = false
                choosingGoal = false
            } label: { Label(L.t("返回"), systemImage: "chevron.left").frame(minHeight: 44) }
                .accessibilityIdentifier("onboardingBack")
            Text(L.t("存够多少？")).font(.system(size: 32, weight: .heavy)).padding(.top, 12)
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("目标金额（元）")).font(.caption).foregroundStyle(Palette.sub)
                HStack(spacing: 2) {
                    Text("¥")
                    TextField(L.t("目标金额（元）"), text: $amount).keyboardType(.decimalPad).focused($editing)
                        .accessibilityIdentifier("onboardingAmount")
                }.font(.system(size: 32, weight: .bold, design: .rounded))
                chips([1000, 3000, 5000, 10000], value: $amount, money: true)
            }.card()
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("用多少天")).font(.caption).foregroundStyle(Palette.sub)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField(L.t("计划天数"), text: $days).keyboardType(.numberPad).focused($editing)
                        .font(.system(size: 32, weight: .bold, design: .rounded)).accessibilityIdentifier("onboardingDays")
                    Text(L.t("天")).foregroundStyle(Palette.sub)
                }
                chips([30, 100, 365], value: $days, money: false)
            }.card()
            if let range, let target, let dayCount,
               let estimate = SaveCore.estimatedDays(remainingCents: target, dailyCents: SaveCore.expectedDailyCents(range)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.f("每天转 +%@ ~ +%@", String(range.minimumCents / 100), String(range.maximumCents / 100)))
                        .font(.title3.bold())
                    Text(L.f("平均下来约 %@ 天存够 %@", String(estimate), "¥" + Money.display(target, integersOnly: true)))
                        .font(.subheadline)
                    if estimate != dayCount {
                        Text(L.t("整数范围会取整，实际进度随每天结果变化。")).font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .foregroundStyle(Palette.mint).background(Palette.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("onboardingEstimate")
            } else {
                Text(L.t("请输入大于 0 的目标金额和 1～36500 天。")).font(.caption).foregroundStyle(Palette.sub)
            }
        }
    }

    private func chips(_ options: [Int], value: Binding<String>, money: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = Int(value.wrappedValue) == option
                    Button {
                        editing = false
                        value.wrappedValue = String(option)
                    } label: {
                        Text(money ? "¥" + String(option) : L.f("%@ 天", String(option)))
                            .font(.subheadline).padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(selected ? Palette.card : Palette.ink)
                            .background(selected ? Palette.mint : Palette.progressTrack, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func refreshPaste() {
        showPaste = !(model.isolated && ProcessInfo.processInfo.arguments.contains("-hide-paste-hint")) && UIPasteboard.general.hasStrings
    }
}
