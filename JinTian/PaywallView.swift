import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        SheetFrame(title: L.t("高级版")) {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "seal").font(.system(size: 54)).foregroundStyle(Palette.gold).padding(.top, 24)
                    Text(model.data.entitlement.purchasedPro ? L.t("感谢你，继续慢慢攒") : L.t("让坚持更轻松一点")).font(.title.bold())
                    if !model.premium {
                        Text(L.f("已连续 %@ 天、存下 %@。6 元买断，保住小组件、提醒和补签。", String(model.streak), Money.yuan(model.total)))
                            .font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("expiredCopy")
                    } else if !model.data.entitlement.purchasedPro {
                        Text(L.f("高级功能免费体验还剩 %@ 天", String(model.data.entitlement.remainingDays(at: model.now))))
                            .foregroundStyle(Palette.mint).accessibilityIdentifier("trialRemaining")
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        feature("rectangle.on.rectangle", "桌面和锁屏，一眼看到坚持", "不用打开 App，也能记得今天的小目标。")
                        feature("bell.badge", "忙起来也不会忘记", "选个舒服的时间，每天提醒自己转一次。")
                        feature("heart.text.square", "偶尔漏一天，也有补救机会", "每月 3 张补签卡，让连续记录接着走。")
                        feature("flag.2.crossed", "把不同愿望分开攒", "多个目标、独立转盘，还有统计与年度回顾。")
                        feature("paintpalette", "把坚持变成喜欢的样子", "主题配色、成就徽章和分享卡。")
                    }.card()
                    if !model.data.entitlement.purchasedPro {
                        Button {
                            Task { await model.purchase(model.proID) }
                        } label: {
                            if model.purchasing { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                            else {
                                Text(model.products.first(where: { $0.id == model.proID }).map { L.f("%@ 一次买断", $0.displayPrice) } ?? L.t("6 元买断高级版"))
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(model.purchasing || !model.products.contains { $0.id == model.proID })
                            .accessibilityIdentifier("buyPro")
                        if model.data.entitlement.trialClaimedAt == nil && model.data.entitlement.remainingDays(at: model.now) > 0 {
                            Button(L.t("领取 0 元试用凭证")) { Task { await model.purchase(model.trialID) } }
                                .disabled(model.purchasing || !model.products.contains { $0.id == model.trialID })
                            Text(L.t("30 天从首次打开起计算，领取或恢复凭证不会重新开始试用。"))
                                .font(.caption).foregroundStyle(Palette.sub)
                        }
                    }
                    Button(L.t("恢复购买")) { Task { await model.restore() } }
                        .disabled(model.purchasing).accessibilityIdentifier("restorePurchases")
                    if model.productLoadFailed {
                        Text(L.t("商品加载失败，请检查网络后重试。"))
                        Button(L.t("重新加载")) { Task { await model.loadProducts() } }
                    }
                    Text(L.t("一次购买，不自动续费。存钱记录、日历、累计和第一个目标的转盘永久免费。"))
                        .font(.footnote).foregroundStyle(Palette.sub).multilineTextAlignment(.center)
                }.padding(24)
            }.task { await model.loadProducts() }
        }
    }
    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Palette.mint).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(title)).font(.headline)
                Text(L.t(detail)).font(.footnote).foregroundStyle(Palette.sub)
            }
        }
    }
}

struct AchievementView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        SheetFrame(title: L.t("新的里程碑")) {
            VStack(spacing: 24) {
                Image(systemName: "medal.fill").font(.system(size: 84)).foregroundStyle(Palette.gold)
                ForEach(model.achievementIDs, id: \.self) { Text(L.achievement($0)).font(.title2.bold()) }
                Text(L.t("每一笔小小的积累，都算数。"))
                Button(L.t("晒一下")) { model.share(model.achievementIDs.contains("goal") ? .goal : .streak) }.buttonStyle(PrimaryButtonStyle())
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
