import SwiftUI

struct WheelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var config: WheelConfig
    var rotation: Double = 0
    var spinning = false
    var result: DayRecord?
    var action: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) * 178 / 420
            ZStack {
                Circle().fill(LinearGradient(colors: Palette.ring(config.theme), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: radius * 2, height: radius * 2)
                    .shadow(color: Palette.ring(config.theme)[1].opacity(0.25), radius: radius * 0.079, y: radius * 0.056)
                Canvas { context, size in
                    drawWheel(context: context, size: size, radius: radius)
                }
                .rotationEffect(.degrees(rotation))
                .accessibilityHidden(true)
                Circle().fill(Palette.accent(config.theme).opacity(0.10))
                    .frame(width: radius * 0.64, height: radius * 0.64)
                if result != nil {
                    coin(radius: radius).accessibilityElement(children: .contain)
                } else {
                    Button { action?() } label: { coin(radius: radius) }
                        .buttonStyle(CoinPressStyle()).disabled(spinning || action == nil)
                        .accessibilityIdentifier("spinButton")
                }
                CoinPointer().fill(LinearGradient(colors: [Palette.coinLight, Palette.coinDark], startPoint: .leading, endPoint: .trailing))
                    .overlay(CoinPointer().stroke(Palette.pointerLine, lineWidth: radius * 0.0067))
                    .frame(width: radius * 0.112, height: radius * 0.264)
                    .rotationEffect(.degrees(spinning && !reduceMotion ? -7 : 0), anchor: .top)
                    .animation(spinning && !reduceMotion ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .spring(response: 0.25, dampingFraction: 0.45), value: spinning)
                    .offset(y: -radius * 0.975)
                    .accessibilityHidden(true)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.aspectRatio(1, contentMode: .fit)
    }

    private func coin(radius: CGFloat) -> some View {
        VStack(spacing: radius * 0.025) {
            Text(result.map { "+" + Money.display($0.amountCents, integersOnly: config.integersOnly) } ?? "¥")
                .font(.system(size: radius * 0.135, weight: .heavy))
                .lineLimit(1).minimumScaleFactor(0.35)
                .accessibilityIdentifier(result == nil ? "coinSymbol" : "todayAmount")
            Text(result.map { L.t($0.isSaved ? "已记上" : "未记上") } ?? L.t("存一下"))
                .font(.system(size: radius * 0.067, weight: .bold)).tracking(radius * 0.011)
        }
        .foregroundStyle(Palette.coinInk)
        .padding(.horizontal, radius * 0.04)
        .frame(width: radius * 0.562, height: radius * 0.562)
        .background {
            Circle().fill(RadialGradient(stops: [.init(color: Palette.coinLight, location: 0),
                                                .init(color: Palette.coinMiddle, location: 0.55),
                                                .init(color: Palette.coinDark, location: 1)],
                                         center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: radius * 0.42))
        }
        .overlay(Circle().inset(by: radius * 0.045).stroke(Palette.coinStitch.opacity(0.6),
                 style: StrokeStyle(lineWidth: radius * 0.0067, dash: [radius * 0.011, radius * 0.017])))
    }

    private func drawWheel(context: GraphicsContext, size: CGSize, radius: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let face = Path(ellipseIn: CGRect(x: center.x - radius * 0.843, y: center.y - radius * 0.843,
                                         width: radius * 1.686, height: radius * 1.686))
        context.fill(face, with: .radialGradient(Gradient(colors: [Palette.wheelFace, Palette.wheelEdge]),
                                               center: center, startRadius: radius * 0.25, endRadius: radius * 0.843))
        let accent = Palette.accent(config.theme)
        let sectorColor = config.theme == "mint" ? Palette.wheelTint : accent
        let line = colorScheme == .dark ? Palette.ink.opacity(0.15) : sectorColor.opacity(0.22)
        for index in 0..<10 {
            let start = Double(index) * 36 - 90
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius * 0.843, startAngle: .degrees(start), endAngle: .degrees(start + 36), clockwise: false)
            wedge.closeSubpath()
            if index.isMultiple(of: 2) { context.fill(wedge, with: .color(sectorColor.opacity(0.07))) }
            let angle = CGFloat(start * .pi / 180)
            var divider = Path()
            divider.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.326, y: center.y + sin(angle) * radius * 0.326))
            divider.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.843, y: center.y + sin(angle) * radius * 0.843))
            context.stroke(divider, with: .color(line), lineWidth: radius / 178)
            let theta = CGFloat((start + 18) * .pi / 180)
            var labelContext = context
            labelContext.translateBy(x: center.x + cos(theta) * radius * 0.618, y: center.y + sin(theta) * radius * 0.618)
            labelContext.rotate(by: .degrees(start + 108))
            var label = String(config.label(index).dropFirst())
            if let result, config.sector(for: result.spunCents) == index {
                let shown = result.amountCents
                let fits = config.bounds(index).map { ($0.low...$0.high).contains(shown) } ?? false
                if !fits { label = Money.display(shown, integersOnly: config.integersOnly) }
            }
            if label.isEmpty { continue }
            let fontSize = min(radius * 0.146, radius * 0.47 / CGFloat(label.count + 1))
            let color = colorScheme == .dark ? Palette.ink : accent
            let text = Text("+").font(.system(size: fontSize * 0.8, weight: .medium, design: .serif)).foregroundColor(color.opacity(0.85))
                + Text(label).font(.system(size: fontSize, weight: .semibold, design: .serif)).foregroundColor(color)
            labelContext.draw(text, at: .zero)
        }
        context.stroke(face, with: .color(Palette.wheelGold), lineWidth: radius * 2 / 178)
        let characters = Array(L.t("SAVE A LITTLE EVERY DAY · 今天存多少 · SAVE A LITTLE EVERY DAY · 今天存多少 ·"))
        for (index, character) in characters.enumerated() {
            let angle = -84 + Double(index) * 348 / Double(characters.count)
            let radians = CGFloat(angle * .pi / 180)
            var letterContext = context
            letterContext.translateBy(x: center.x + cos(radians) * radius * 0.916, y: center.y + sin(radians) * radius * 0.916)
            letterContext.rotate(by: .degrees(angle + 90))
            letterContext.draw(Text(String(character)).font(.system(size: radius * 0.062, weight: .semibold))
                .foregroundColor(Palette.engraving), at: .zero)
        }
    }
}

private struct CoinPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct CoinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.12), control: CGPoint(x: rect.midX, y: -rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}
