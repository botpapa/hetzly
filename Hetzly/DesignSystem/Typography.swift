import SwiftUI

/// Text style helpers for the Hetzly 17/15/13 type scale, plus the SF Mono
/// numeric style used for IPs, prices, and other metrics.
extension View {
    /// SF Mono (via the `.monospaced` font design) with monospaced digits,
    /// for IPs, prices, and other numeric readouts.
    func hetzlyMonoNumbers() -> some View {
        self
            .font(.system(.body, design: .monospaced))
            .monospacedDigit()
    }

    /// Primary body text, 17pt, primary text color.
    func bodyPrimary() -> some View {
        self
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(HetzlyColors.textPrimary)
    }

    /// Secondary body text, 15pt, secondary text color.
    func bodySecondary() -> some View {
        self
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(HetzlyColors.textSecondary)
    }

    /// Caption text, 13pt, tertiary text color.
    func caption() -> some View {
        self
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(HetzlyColors.textTertiary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.unit * 3) {
        Text("Primary body — 17pt").bodyPrimary()
        Text("Secondary body — 15pt").bodySecondary()
        Text("Caption — 13pt").caption()
        Text("192.168.1.1 · €4.90/mo").hetzlyMonoNumbers()
            .foregroundStyle(HetzlyColors.textPrimary)
    }
    .padding()
    .background(HetzlyColors.canvas)
    .preferredColorScheme(.dark)
}
