import SwiftUI

struct PreviewView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm: PreviewViewModel

    init(wigglegram: Wigglegram) {
        _vm = StateObject(wrappedValue: PreviewViewModel(wigglegram: wigglegram))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                wigglePreview
                    .padding(.top, 16)

                filmLookToggle
                exportButtons
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear { vm.startPlayback(fps: settings.framesPerSecond) }
        .onDisappear { vm.stopPlayback() }
        .onChange(of: settings.framesPerSecond) { _, fps in
            vm.startPlayback(fps: fps)
        }
        .overlay(alignment: .bottom) {
            if let msg = vm.exportMessage {
                Toast(text: msg)
                    .padding(.bottom, 32)
                    .transition(.opacity)
            }
        }
        .overlay {
            if vm.isExporting {
                Color.black.opacity(0.55).ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .alert("Export Error",
               isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(vm.errorMessage ?? "") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { router.popToRoot() }
                    .foregroundStyle(.white)
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var frames: [UIImage] {
        settings.filmLookEnabled ? vm.displayFramesWithFilmLook : vm.displayFrames
    }

    private var wigglePreview: some View {
        GeometryReader { geo in
            let frame = frames[vm.currentFrameIndex.clamped(to: 0..<frames.count)]
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color.black)
        }
        .aspectRatio(3.0/4.0, contentMode: .fit)
        .padding(.horizontal, 16)
    }

    private var filmLookToggle: some View {
        HStack {
            Text("FILM LOOK")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Toggle("", isOn: $settings.filmLookEnabled)
                .labelsHidden()
                .tint(.white)
        }
        .padding(.horizontal, 32)
    }

    private var exportButtons: some View {
        VStack(spacing: 12) {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    Task {
                        await vm.export(format,
                                        fps: settings.framesPerSecond,
                                        filmLook: settings.filmLookEnabled)
                    }
                } label: {
                    HStack {
                        Image(systemName: format.systemImage)
                        Text(format.title)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(2)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                }
                .disabled(vm.isExporting)
            }
        }
    }
}

private struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(Capsule())
    }
}

private extension Comparable {
    func clamped(to range: Range<Int>) -> Int where Self == Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
