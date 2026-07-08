import SwiftUI

extension View {
    /// Standard row treatment for glass cards hosted inside a `List`: clear
    /// row background (the canvas shows through), no separators, and the
    /// app's screen margins as insets. Lists are used (rather than
    /// `ScrollView`) wherever rows need `.swipeActions`.
    ///
    /// Also used (with an explicit `.listRowBackground` applied afterward to
    /// override the clear fill) by any row that wants a custom rounded
    /// background but still needs the system separator suppressed so it
    /// doesn't poke past the rounded corners — see `SettingsView`.
    func plainRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Spacing.unit,
                leading: Spacing.screenMargin,
                bottom: Spacing.unit,
                trailing: Spacing.screenMargin
            ))
    }
}
