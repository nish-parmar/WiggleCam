import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = CaptureViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                previewBlock
                    .padding(.top, 24)

                Spacer(minLength: 0)
                hintText
                shutterRow
                Spacer(minLength: 0)
            }
        }
        .task {
            await vm.start(preference: settings.captureModePreference)
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

    // MARK: - Preview + overlays
    private var previewBlock: some View {
        CameraPreviewView(session: vm.session,
                          onTap: { layerPoint, devicePoint in
                              vm.focus(at: layerPoint, devicePoint: devicePoint)
                          })
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .background(Color.black)
            .clipped()
            .overlay(alignment: .topLeading) { statusBadge }
            .overlay(focusReticle)
            .overlay(guideOverlay)
            .overlay(frameAFlash)
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

    // MARK: - Focus reticle
    @ViewBuilder
    private var focusReticle: some View {
        if let pt = vm.lastFocusPoint {
            FocusReticle()
                .position(pt)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Brief "frame A captured" flash (sequential mode only)
    @ViewBuilder
    private var frameAFlash: some View {
        if vm.phase == .firingA, case .sequential = vm.captureMode {
            Color.white.opacity(0.85)
                .transition(.opacity)
        }
    }

    // MARK: - Sequential guide overlay (Panorama-style)
    @ViewBuilder
    private var guideOverlay: some View {
        if vm.phase == .guiding {
            GuideOverlay(progress: vm.motionGuide.progress)
                .transition(.opacity)
        }
    }

    // MARK: - Hint
    private var hintText: some View {
        Group {
            switch (vm.captureMode, vm.phase) {
            case (.sequential, .idle):
                Text("Tap shutter, then slowly slide phone →")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            case (.sequential, .guiding):
                Text("KEEP SLIDING →")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white)
            case (.dualCamera, _):
                Text("Hold steady — both lenses fire at once")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            default:
                EmptyView()
            }
        }
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: vm.phase)
    }

    // MARK: - Shutter
    private var shutterRow: some View {
        HStack {
            Spacer()
            ShutterButton(phase: vm.phase) {
                Task {
                    if let pair = await vm.capture() {
                        vm.stop()
                        router.replaceTop(with: .processing(pair))
                    }
                }
            }
            .disabled(!vm.isReady || vm.isCapturing)
            Spacer()
        }
        .padding(.bottom, 48)
    }
}

// MARK: - Focus Reticle
private struct FocusReticle: View {
    @State private var scale: CGFloat = 1.6
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(Color.yellow, lineWidth: 1.2)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                    opacity = 1.0
                }
                withAnimation(.easeIn(duration: 0.5).delay(0.4)) {
                    opacity = 0.4
                }
            }
    }
}

// MARK: - Shutter Button
private struct ShutterButton: View {
    let phase: CapturePhase
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
                    .scaleEffect(isPressed ? 0.86 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: phase)
            }
        }
        .buttonStyle(.plain)
    }

    private var isPressed: Bool {
        switch phase {
        case .idle, .done: return false
        default: return true
        }
    }
}

// MARK: - Sequential Capture Guide Overlay
private struct GuideOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            // Dimmed backdrop so the guide stands out
            Color.black.opacity(0.35)

            VStack(spacing: 22) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white)
                    .opacity(0.85)
                    .offset(x: CGFloat(progress) * 14 - 7)
                    .animation(.easeOut(duration: 0.15), value: progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                            .animation(.easeOut(duration: 0.12), value: progress)
                    }
                    .frame(height: 4)
                }
                .frame(width: 220)

                Text("SLIDE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
