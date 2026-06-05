import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 48) {
                Spacer()
                AppLogo()
                Spacer()

                Button {
                    HapticManager.impact(.light)
                    router.push(.capture)
                } label: {
                    Text("Capture")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .tracking(2)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                .padding(.horizontal, 40)

                Button {
                    router.push(.settings)
                } label: {
                    Text("Settings")
                        .font(.system(size: 14, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct AppLogo: View {
    var body: some View {
        VStack(spacing: 12) {
            // Two stacked rectangles that suggest dual-lens capture.
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 92, height: 60)
                    .offset(x: -6, y: -4)
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: 92, height: 60)
                    .offset(x: 6, y: 4)
            }
            .frame(height: 80)

            Text("WIGGLEGRAM")
                .font(.system(size: 22, weight: .light, design: .default))
                .tracking(8)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environmentObject(AppRouter())
}
