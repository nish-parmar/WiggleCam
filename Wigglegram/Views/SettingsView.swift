import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {

                section(title: "Playback") {
                    Stepper(value: $settings.framesPerSecond, in: 4...24, step: 1) {
                        HStack {
                            Text("Frame Rate")
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(settings.framesPerSecond) FPS")
                                .foregroundStyle(.white.opacity(0.7))
                                .monospaced()
                        }
                    }
                }

                section(title: "Look") {
                    Toggle(isOn: $settings.filmLookEnabled) {
                        Text("Apply film look")
                            .foregroundStyle(.white)
                    }
                    .tint(.white)
                }

                section(title: "Capture") {
                    Toggle(isOn: $settings.preferDualCamera) {
                        Text("Prefer dual camera when available")
                            .foregroundStyle(.white)
                    }
                    .tint(.white)
                }

                Spacer()
                Text("Wigglegram • MVP")
                    .font(.system(size: 11))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }
}
