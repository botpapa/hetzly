import SwiftUI

/// Covers the view's content with an opaque privacy shield whenever the
/// scene is not `.active` (app switcher, backgrounding, etc.), so sensitive
/// data (tokens, server details) is never visible in an OS-level screenshot
/// or the app switcher preview.
struct PrivacyOverlay: ViewModifier {
    let enabled: Bool

    @Environment(\.scenePhase) private var scenePhase

    private var isShielded: Bool {
        enabled && scenePhase != .active
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShielded {
                    ZStack {
                        Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 12.0 / 255.0)
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        Image(systemName: "cube.fill")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            // Asymmetric on purpose: fade IN when leaving the app (a hard
            // cut there looks glitchy in the app-switcher zoom animation),
            // but drop the shield INSTANTLY on return — an eased fade-out
            // reads as the app being slow to open after unlock.
            .animation(isShielded ? .smooth : nil, value: isShielded)
    }
}

extension View {
    /// Shields this view's content with an opaque overlay whenever the scene
    /// phase is not `.active`. Pass `enabled: false` to disable the shield
    /// (e.g. for screens that never show sensitive data).
    func privacyOverlay(enabled: Bool = true) -> some View {
        modifier(PrivacyOverlay(enabled: enabled))
    }
}

#Preview("Shielded") {
    // scenePhase defaults to .active in Xcode previews, so the shield is
    // rendered directly here to preview its appearance.
    ZStack {
        Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 12.0 / 255.0)
        Rectangle()
            .fill(.ultraThinMaterial)
        Image(systemName: "cube.fill")
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(.white.opacity(0.35))
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}

#Preview("Unshielded") {
    VStack(spacing: 16) {
        Text("Sensitive Content")
            .font(.title)
        Text("Token: hcloud_xxx...")
            .font(.body.monospaced())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 12.0 / 255.0))
    .privacyOverlay(enabled: true)
    .preferredColorScheme(.dark)
}
