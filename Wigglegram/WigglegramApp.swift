import SwiftUI

@main
struct WigglegramApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var settings = AppSettings()

    init() {
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
