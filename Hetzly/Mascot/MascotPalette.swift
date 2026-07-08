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
        case brown
        case midBrown
    }

    /// Maps a frame-art character to its palette index.
    /// '.' transparent, 'k' outline, 'r' orange, 'd' dark orange, 'c' light
    /// gray, 'p' pink (legacy, unused by the current sheet), 'w' white,
    /// 'b' dark brown, 'm' mid brown.
    static let characterIndex: [Character: Index] = [
        ".": .clear,
        "k": .outline,
        "r": .rust,
        "d": .darkRust,
        "c": .cream,
        "p": .pink,
        "w": .white,
        "b": .brown,
        "m": .midBrown,
    ]

    /// Resolves a palette index to a `Color`. Returns `nil` for `clear`,
    /// meaning the pixel should not be painted (transparent background shows
    /// through). Values match Elthen's red panda sheet exactly (see
    /// ASSETS-LICENSE.md).
    static func color(for index: UInt8) -> Color? {
        guard let entry = Index(rawValue: index) else { return nil }
        switch entry {
        case .clear:
            return nil
        case .outline:
            return Color(red: 0x2F / 255, green: 0x2F / 255, blue: 0x2E / 255)
        case .rust:
            return Color(red: 0xD6 / 255, green: 0x79 / 255, blue: 0x41 / 255)
        case .darkRust:
            return Color(red: 0x9D / 255, green: 0x50 / 255, blue: 0x21 / 255)
        case .cream:
            return Color(red: 0xB8 / 255, green: 0xB8 / 255, blue: 0xB8 / 255)
        case .pink:
            return Color(red: 0xE8 / 255, green: 0xA2 / 255, blue: 0xA0 / 255)
        case .white:
            return .white
        case .brown:
            return Color(red: 0x69 / 255, green: 0x41 / 255, blue: 0x29 / 255)
        case .midBrown:
            return Color(red: 0x82 / 255, green: 0x52 / 255, blue: 0x35 / 255)
        }
    }
}
