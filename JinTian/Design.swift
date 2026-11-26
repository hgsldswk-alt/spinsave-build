import SwiftUI
import UIKit

enum Palette {
    static func color(_ hex: UInt32) -> Color { Color(uiColor: uiColor(hex)) }
    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
    }
    static let mint = adaptive(0x24513F, 0x92BBA6)
    static let background = adaptive(0xF6F3EA, 0x131C18)
    static let card = adaptive(0xFFFDF8, 0x1D2923)
    static let line = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.06) : uiColor(0xE9E2D0) })
    static let ink = adaptive(0x1E2A25, 0xEFE6CF)
    static let sub = adaptive(0x7E857F, 0xA6B0A8)
    static let gold = adaptive(0xB8915A, 0xD9C08A)
    static let progressTrack = adaptive(0xEDE7D8, 0x303C34)
    static let progressAccent = adaptive(0x2F6352, 0x6E9B84)
    static let wheelTint = color(0x2F6352)
    static let coinLight = color(0xF3DDA6)
    static let coinMiddle = color(0xC9A160)
    static let coinDark = color(0x94703A)
    static let coinInk = color(0x5A3F17)
    static let engraving = color(0xD9C08A)
    static let coinStitch = color(0xFFF3CF)
    static let pointerLine = color(0x6E5226)
    static let wheelFace = adaptive(0xFBF8F0, 0x23302B)
    static let wheelEdge = adaptive(0xEFE7D4, 0x1B2622)
    static let wheelGold = color(0xB8915A)
    static func ring(_ theme: String) -> [Color] {
        switch theme {
        case "peach": return [color(0x67514D), color(0x3D2E2C)]
        case "violet": return [color(0x57506A), color(0x322C40)]
        default: return [color(0x2C5E4D), color(0x173A2E)]
        }
    }
    static func accent(_ theme: String) -> Color {
        switch theme {
        case "peach": return adaptive(0x67514D, 0xC3ABA6)
        case "violet": return adaptive(0x57506A, 0xB9ACC9)
        default: return mint
        }
    }
}

struct CardStyle: ViewModifier {
    var decorated = false
    func body(content: Content) -> some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Palette.card)
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    if decorated {
                        Color.clear.overlay(alignment: .topTrailing) {
                            Circle().stroke(Palette.gold.opacity(0.20), lineWidth: 1)
                                .background(Circle().stroke(Palette.gold.opacity(0.05), lineWidth: 28))
                                .frame(width: 150, height: 150).offset(x: 40, y: -40)
                                .accessibilityHidden(true)
                        }.clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
    }
}
extension View {
    func card(decorated: Bool = false) -> some View { modifier(CardStyle(decorated: decorated)) }
    func appMessage(_ model: AppModel, onSheet: Bool = false) -> some View {
        alert(L.t("提示"), isPresented: Binding(get: { model.message != nil && (onSheet || model.sheet == nil) }, set: { if !$0 { model.message = nil } })) {
            Button(L.t("好")) { model.message = nil }.accessibilityIdentifier("dismissMessage")
        } message: { Text(model.message ?? "") }
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L.t("完成")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }.accessibilityIdentifier("keyboardDone")
            }
        }
    }
}

struct SheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationStack {
            content().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden)
                .background(Palette.background)
                .foregroundStyle(Palette.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet")
                } }
        }.tint(Palette.mint).appMessage(model, onSheet: true)
    }
}


struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).foregroundStyle(Color.white)
            .padding(.horizontal, 22).frame(minHeight: 48)
            .background(Palette.mint.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
