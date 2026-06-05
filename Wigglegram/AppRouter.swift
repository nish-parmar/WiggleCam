import SwiftUI

enum AppDestination: Hashable {
    case capture
    case processing(CapturedPair)
    case preview(Wigglegram)
    case settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppDestination] = []

    func push(_ destination: AppDestination) {
        path.append(destination)
    }

    func popToRoot() {
        path.removeAll()
    }

    func replaceTop(with destination: AppDestination) {
        if !path.isEmpty { path.removeLast() }
        path.append(destination)
    }
}

struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .capture:
                        CaptureView()
                    case .processing(let pair):
                        ProcessingView(pair: pair)
                    case .preview(let wiggle):
                        PreviewView(wigglegram: wiggle)
                    case .settings:
                        SettingsView()
                    }
                }
        }
    }
}
