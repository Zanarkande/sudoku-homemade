import SwiftUI

@main struct MyApp: App {
    @State private var session = GameSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .themed()
                .environment(session)
        }
        .onChange(of: scenePhase) { _, phase in
            session.setSceneActive(phase == .active)
        }
    }
}
