import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum ShareKind: String, CaseIterable, Identifiable {
    case today, streak, goal, annual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return L.t("今日结果")
        case .streak: return L.t("连续打卡")
        case .goal: return L.t("目标进度")
        case .annual: return L.t("年度回顾")
        }
    }
}

enum QRCode {
    static var downloadURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id)
    }
    static func image() -> UIImage? {
        guard let url = downloadURL else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct ShareCard: View {
    let goal: Goal
    let now: Date
    let kind: ShareKind
    var showAmounts = false
    var selectedYear: Int?
    private var total: Int { SaveCore.total(goal.records) }
    private var year: Int { selectedYear ?? DayKey.calendar.component(.year, from: now) }
    private var annual: [DayRecord] { SaveCore.saved(goal.records).filter { $0.day.hasPrefix(String(year) + "-") } }
    private var headline: String {
        switch kind {
        case .today: return L.t("今天，又为未来存一点")
        case .streak: return L.t("把小坚持，变成大期待")
        case .goal: return goal.hasTarget ? (total >= goal.targetCents ? L.t("目标达成") : L.t("愿望正在一点点靠近")) : L.t("把小坚持，变成大期待")
        case .annual: return L.f("%@ 年的每一笔，都算数", String(year))
        }
    }
    private var value: String {
        switch kind {
        case .today:
            let record = goal.records.first { $0.day == DayKey.key(now) && !$0.isDeleted }
            guard let record else { return L.t("今天还没转") }
            return "+" + Money.yuan(record.amountCents)
        case .streak: return L.f("%@ 天", String(SaveCore.streak(goal.records, today: now)))
        case .goal:
            if !goal.hasTarget { return showAmounts ? Money.yuan(total) : L.f("%@ 天", String(SaveCore.saved(goal.records).count)) }
            return showAmounts ? Money.yuan(total) : String(Int(SaveCore.progress(goal) * 100)) + "%"
        case .annual: return showAmounts ? Money.yuan(SaveCore.total(annual)) : L.f("%@ 天", String(annual.count))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack { Image(systemName: "circle.grid.cross"); Text(L.t("今天存多少")); Spacer(); Text(now.formatted(date: .abbreviated, time: .omitted)) }
                .font(.system(size: 21, weight: .semibold)).foregroundStyle(Palette.mint)
            Spacer(minLength: 10)
            Text(headline).font(.system(size: 32, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 82, weight: .bold, design: .rounded)).minimumScaleFactor(0.35).lineLimit(1)
                .foregroundStyle(Palette.mint)
            if kind == .today {
                let saved = goal.records.first { $0.day == DayKey.key(now) }?.isSaved == true
                Text(saved ? L.t("今天已存，明天再来") : L.t("今天这笔还没记"))
                    .font(.system(size: 23)).foregroundStyle(Palette.sub)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(L.goalName(goal)).font(.system(size: 27, weight: .bold))
                if goal.hasTarget {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.mint.opacity(0.12))
                        Capsule().fill(Palette.mint).frame(width: g.size.width * CGFloat(min(1, max(0, SaveCore.progress(goal)))))
                    }
                }.frame(height: 6)
                Text(showAmounts ? L.f("累计 %@ / 目标 %@", Money.yuan(total), Money.yuan(goal.targetCents)) :
                    L.f("目标已完成 %@", String(Int(SaveCore.progress(goal) * 100)) + "%")).font(.system(size: 21))
                } else {
                    Text(showAmounts ? L.f("累计存下 %@", Money.yuan(total)) : L.f("已坚持 %@ 天", String(SaveCore.saved(goal.records).count)))
                        .font(.system(size: 21))
                }
            }.card()
            if kind == .annual {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(1...12, id: \.self) { month in
                        let cents = annual.filter { $0.day.hasPrefix(String(format: "%04d-%02d", year, month)) }.reduce(0) { $0 + $1.amountCents }
                        VStack {
                            RoundedRectangle(cornerRadius: 5).fill(Palette.mint.opacity(0.7))
                                .frame(height: max(5, min(90, Double(cents) / Double(max(1, SaveCore.total(annual))) * 300)))
                            Text(String(month)).font(.system(size: 14))
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 125)
            } else {
                Text(L.f("已连续存钱 %@ 天", String(SaveCore.streak(goal.records, today: now)))).font(.system(size: 24, weight: .semibold))
            }
            Spacer(minLength: 10)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("#转盘存钱挑战 #今天存多少").font(.system(size: 21, weight: .medium))
                    Text(L.t("今天存一点，未来多一点")).font(.system(size: 19)).foregroundStyle(Palette.sub)
                }
                Spacer()
                if let image = QRCode.image() {
                    VStack(spacing: 5) {
                        Image(uiImage: image).interpolation(.none).resizable().frame(width: 96, height: 96)
                        Text(L.t("扫码一起存")).font(.system(size: 15))
                    }
                }
            }
        }
        .padding(48).frame(width: 720, height: 960)
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .medium)
    }
}

struct SharingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var kind: ShareKind = .today
    @State private var image: UIImage?
    @State private var activity = false
    @State private var showAmounts = false
    var body: some View {
        SheetFrame(title: L.t("分享这份坚持")) {
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text(L.t("导入朋友的口令")).font(.subheadline)
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            Task { @MainActor in model.importCode(strings.joined(separator: "\n")) }
                        }.accessibilityIdentifier("pasteCode")
                    }.card()
                    Picker(L.t("分享内容"), selection: $kind) {
                        ForEach(ShareKind.allCases.filter { (model.premium || $0 != .annual) && (model.goal.hasTarget || $0 != .goal) }) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("shareKind")
                    Toggle(L.t("分享图显示金额"), isOn: $showAmounts).accessibilityIdentifier("shareAmounts")
                    if let image {
                        Image(uiImage: image).resizable().aspectRatio(0.75, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .accessibilityLabel(L.t("分享图预览")).accessibilityIdentifier("sharePreview")
                        Button(L.t("分享图片")) { activity = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("shareImage")
                    }
                    Button(L.t("复制文案")) {
                        UIPasteboard.general.string = "#转盘存钱挑战 #今天存多少 " +
                            (showAmounts ? L.f("今天存一点，已累计 %@。", Money.yuan(model.total)) : L.f("已连续存钱 %@ 天", String(model.streak)))
                        model.message = L.t("文案已复制。")
                    }.accessibilityIdentifier("copyCaption")
                    Button(L.t("复制转盘口令")) {
                        guard let code = ShareCode.encode(model.goal) else { return }
                        UIPasteboard.general.string = L.t("复制这段话，在「今天存多少」点粘贴，一起用同款转盘。") + "\n" + code
                        model.message = L.t("口令已复制，不包含你的存钱记录。")
                    }.accessibilityIdentifier("copyShareCode")
                    Text(L.t("口令只分享目标和转盘设置，不含存钱记录。"))
                        .font(.caption).foregroundStyle(Palette.sub)
                }.padding(24)
            }.onAppear { kind = model.shareKind; render() }.onChange(of: kind) { _, _ in render() }
                .onChange(of: showAmounts) { _, _ in render() }
                .sheet(isPresented: $activity) { if let image { ShareActivity(items: [image]) } }
        }
    }
    @MainActor private func render() {
        let renderer = ImageRenderer(content: ShareCard(goal: model.goal, now: model.now, kind: kind, showAmounts: showAmounts, selectedYear: model.shareYear))
        renderer.scale = 2
        image = renderer.uiImage
        if image == nil { model.message = L.t("分享图生成失败，请重试。") }
    }
}

struct ShareActivity: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.view.accessibilityIdentifier = "systemShare"
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
