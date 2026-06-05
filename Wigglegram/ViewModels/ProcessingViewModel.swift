import SwiftUI

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published var stage: WigglegramStage = .aligning
    @Published var errorMessage: String?
    @Published var result: Wigglegram?

    private let builder: WigglegramBuilding

    init(builder: WigglegramBuilding = WigglegramBuilder()) {
        self.builder = builder
    }

    func run(on pair: CapturedPair) async {
        do {
            let wg = try await builder.build(from: pair) { [weak self] stage in
                self?.stage = stage
            }
            self.result = wg
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
