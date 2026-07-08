import SwiftUI

/// Wave 1 scaffold. Wave 2 replaces this with the real switch between
/// onboarding and `MainTabView`, backed by `AppContainer`.
struct RootView: View {
    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.047)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("Hetzly")
                    .font(.largeTitle.bold())
                Text("Wave 1 scaffold")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
