import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.ssBackground.ignoresSafeArea()
            switch model.stage {
            case .starting: ProgressView().tint(Color.ssSage)
            case .configMissing: ConfigMissingView()
            case .consent: ConsentView()
            case .signedOut: LoginView()
            case .setupActivities: ActivitiesSetupView()
            case .setupRhythm: RhythmSetupView()
            case .home: HomeView()
            }
        }
        .gentle(value: model.stage)
        .task { await model.start() }
        .onChange(of: scenePhase) { if scenePhase == .active, model.stage == .home { Task { await model.syncReminders() } } }
    }
}

struct ConfigMissingView: View {
    var body: some View {
        ScreenScroll {
            Text("Not connected yet").ssHeadingText()
            Text("This build is missing its study settings. Copy ios/Config.example.xcconfig to ios/Config.local.xcconfig, fill it in, and rebuild.")
                .ssBodyText()
        }
    }
}
