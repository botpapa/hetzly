import SwiftUI

/// 4pt spacing grid used across Hetzly layouts.
enum Spacing {
    /// Base grid unit, 4pt.
    static let unit: CGFloat = 4
    /// Leading/trailing screen margins, 20pt.
    static let screenMargin: CGFloat = 20
    /// Internal padding for cards, 16pt.
    static let cardPadding: CGFloat = 16
}

/// Corner radii used across Hetzly components.
enum Radius {
    /// Cards and large glass surfaces, 24pt.
    static let card: CGFloat = 24
    /// Controls (buttons, text fields), 16pt.
    static let control: CGFloat = 16
    /// Fully rounded capsule chips.
    static let capsule: CGFloat = 999
}
