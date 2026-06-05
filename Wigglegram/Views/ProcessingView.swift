import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = ProcessingViewModel()

    let pair: CapturedPair

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()

                ProgressIndicator(fraction: vm.stage.progressFraction)
                    .frame(width: 64, height: 64)

                VStack(spacing: 14) {
                    ForEach(visibleStages, id: \.self) { stage in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(stageColor(stage))
                                .frame(width: 6, height: 6)
                            Text(stage.rawValue)
                                .font(.system(size: 14, weight: stage == vm.stage ? .semibold : .regular))
                                .tracking(1)
                                .foregroundStyle(stageTextColor(stage))
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: 240)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .task { await vm.run(on: pair) }
        .onChange(of: vm.result) { _, newValue in
            if let wg = newValue {
                router.replaceTop(with: .preview(wg))
            }
        }
        .alert("Processing Error",
               isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
            Button("OK", role: .cancel) { router.popToRoot() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var visibleStages: [WigglegramStage] {
        [.aligning, .cropping, .building]
    }

    private func stageColor(_ stage: WigglegramStage) -> Color {
        if isStageComplete(stage)        { return .white }
        else if stage == vm.stage         { return .white }
        else                               { return .white.opacity(0.25) }
    }

    private func stageTextColor(_ stage: WigglegramStage) -> Color {
        if isStageComplete(stage) || stage == vm.stage { return .white }
        return .white.opacity(0.4)
    }

    private func isStageComplete(_ stage: WigglegramStage) -> Bool {
        let order: [WigglegramStage] = [.aligning, .cropping, .building, .done]
        guard let current = order.firstIndex(of: vm.stage),
              let me = order.firstIndex(of: stage) else { return false }
        return me < current
    }
}

private struct ProgressIndicator: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: fraction)
        }
    }
}
