import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = CaptureViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                CameraPreviewView(session: vm.session)
                    .aspectRatio(3.0/4.0, contentMode: .fit)
                    .background(Color.black)
                    .clipped()
                    .overlay(alignment: .topLeading) { statusBadge }
                    .padding(.top, 24)

                Spacer(minLength: 0)
                shutterRow
                Spacer(minLength: 0)
            }
        }
        .task {
            await vm.start()
        }
        .onDisappear { vm.stop() }
        .alert("Camera Error",
               isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("")
    }

    private var statusBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.captureMode?.displayName ?? "Detecting…")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white)
            if let mode = vm.captureMode {
                Text(mode.detailDescription)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .padding(12)
    }

    private var shutterRow: some View {
        HStack {
            Spacer()
            ShutterButton(isCapturing: vm.camera.isCapturing) {
                Task {
                    if let pair = await vm.capture() {
                        vm.stop()
                        router.replaceTop(with: .processing(pair))
                    }
                }
            }
            .disabled(!vm.isReady || vm.camera.isCapturing)
            Spacer()
        }
        .padding(.bottom, 48)
    }
}

private struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                    .scaleEffect(isCapturing ? 0.86 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isCapturing)
            }
        }
        .buttonStyle(.plain)
    }
}
