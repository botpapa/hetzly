import SwiftUI

/// The fixed color palette used by every Hetzi sprite frame.
///
/// Frame art is authored as compact strings (see `MascotFrameData`) where each
/// character names one palette entry. `MascotAtlas` converts those characters
/// into `UInt8` indices; `MascotPalette` maps those indices back to `Color`
/// at draw time. Keeping the palette tiny (7 entries) keeps sprite source
/// small and every frame visually consistent.
enum MascotPalette {
    /// Raw palette index values. `clear.index` pixels are not drawn (fully transparent).
    enum Index: UInt8, CaseIterable, Sendable {
        case clear = 0
        case outline
        case rust
        case darkRust
        case cream
        case pink
        case white
    }

    /// Maps a frame-art character to its palette index.
    /// '.' transparent, 'k' outline, 'r' rust, 'd' dark rust, 'c' cream, 'p' pink, 'w' white.
    static let characterIndex: [Character: Index] = [
        ".": .clear,
        "k": .outline,
        "r": .rust,
        "d": .darkRust,
        "c": .cream,
        "p": .pink,
        "w": .white,
    ]

    /// Resolves a palette index to a `Color`. Returns `nil` for `clear`,
    /// meaning the pixel should not be painted (transparent background shows through).
    static func color(for index: UInt8) -> Color? {
        guard let entry = Index(rawValue: index) else { return nil }
        switch entry {
        case .clear:
            return nil
        case .outline:
            return Color(red: 0x1B / 255, green: 0x15 / 255, blue: 0x12 / 255)
        case .rust:
            return Color(red: 0xC1 / 255, green: 0x64 / 255, blue: 0x3B / 255)
        case .darkRust:
            return Color(red: 0x8F / 255, green: 0x45 / 255, blue: 0x27 / 255)
        case .cream:
            return Color(red: 0xF2 / 255, green: 0xE3 / 255, blue: 0xC6 / 255)
        case .pink:
            return Color(red: 0xE8 / 255, green: 0xA2 / 255, blue: 0xA0 / 255)
        case .white:
            return .white
        }
    }
}
