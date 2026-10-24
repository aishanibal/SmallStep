import SwiftUI

@main
struct SmallStepApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "preview") {
                PreviewGallery(name: name)
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    private var root: some View {
        RootView()
            .environment(model)
            .tint(Color.ssSage)
    }
}
