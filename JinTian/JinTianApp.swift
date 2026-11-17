import SwiftUI

@main
struct JinTianApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                if model.data.onboarded { HomeView() }
                else { OnboardingView() }
            }.environmentObject(model)
                .tint(Palette.mint)
                .task { await model.start() }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await model.start() } }
                }
        }
    }
}
