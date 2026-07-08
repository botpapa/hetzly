import SwiftUI
import UIKit

/// The app's selectable icons. Raw values are the alternate-icon asset
/// names wired in `project.yml` (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`)
/// against the `AppIcon-*.appiconset` catalogs in `Assets.xcassets`.
enum AppIconOption: String, CaseIterable, Identifiable {
    case appIcon = "AppIcon"
    case mono = "AppIcon-Mono"
    case light = "AppIcon-Light"
    case hetzi = "AppIcon-Hetzi"

    var id: String { rawValue }

    /// What `UIApplication.setAlternateIconName(_:)` expects: `nil` selects
    /// the primary icon, everything else is the appiconset name.
    var alternateIconName: String? { self == .appIcon ? nil : rawValue }

    var title: String {
        switch self {
        case .appIcon: "Default"
        case .mono: "Mono"
        case .light: "Light"
        case .hetzi: "Hetzi"
        }
    }

    /// Reads the icon iOS currently reports as active.
    @MainActor
    static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .appIcon }
        return AppIconOption(rawValue: name) ?? .appIcon
    }
}

/// A sheet offering the four Hetzi icon variants, each rendered as an inline
/// mascot preview (rather than duplicating the 1024px icon PNGs as regular
/// imagesets — app-icon-set assets aren't meant to be loaded as ordinary
/// `Image`s). Selecting a tile calls `UIApplication.setAlternateIconName`.
struct AppIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selection: AppIconOption = .current
    @State private var isApplying = false
    @State private var applyError: String?

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: Spacing.unit * 4)]

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.unit * 5) {
                        ForEach(AppIconOption.allCases) { option in
                            Button {
                                select(option)
                            } label: {
                                AppIconPreviewTile(option: option, isSelected: selection == option)
                            }
                            .buttonStyle(.plain)
                            .disabled(isApplying)
                            .accessibilityLabel("\(option.title) icon")
                            .accessibilityAddTraits(selection == option ? [.isSelected] : [])
                        }
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Couldn't Change Icon",
                isPresented: Binding(get: { applyError != nil }, set: { if !$0 { applyError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(applyError ?? "")
            }
        }
    }

    private func select(_ option: AppIconOption) {
        guard option != selection else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            applyError = "This device doesn't support alternate app icons."
            return
        }
        let previousSelection = selection
        selection = option
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                try await UIApplication.shared.setAlternateIconName(option.alternateIconName)
            } catch {
                selection = previousSelection
                applyError = "Couldn't switch to the \(option.title) icon. Please try again."
            }
        }
    }
}

/// One icon option's preview: a rounded-square swatch approximating the
/// real app icon (background tone + an inline `MascotView`) plus its name.
private struct AppIconPreviewTile: View {
    let option: AppIconOption
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Spacing.unit * 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundGradient)

                MascotView(state: .idle, scale: option == .hetzi ? 2.6 : 2.1)
                    .grayscale(tintsGray ? 1 : 0)
                    .colorMultiply(option == .light ? Color(red: 0.4, green: 0.32, blue: 0.26) : .white)
                    .offset(y: 6)
            }
            .frame(width: 72, height: 72)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? HetzlyColors.accent : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            }

            HStack(spacing: Spacing.unit) {
                Text(option.title)
                    .bodySecondary()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(HetzlyColors.accent)
                }
            }
        }
    }

    private var tintsGray: Bool {
        option == .mono || option == .light
    }

    private var backgroundGradient: LinearGradient {
        switch option {
        case .light:
            LinearGradient(
                colors: [Color(hex: 0xF7F7F9), Color(hex: 0xEDEDF0)],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            LinearGradient(
                colors: [Color(hex: 0x0A0A0C), Color(hex: 0x141418)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    AppIconPickerSheet()
        .preferredColorScheme(.dark)
}
