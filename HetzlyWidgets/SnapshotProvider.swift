import WidgetKit

/// Single-entry timeline entry: just wraps whatever `WidgetSnapshot` (or
/// lack thereof) was on disk at render time.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Shared `TimelineProvider` for every Hetzly widget. There's no background
/// polling here by design — the widget extension makes no network calls at
/// all. The app writes a fresh snapshot after each dashboard load/refresh
/// and calls `WidgetCenter.shared.reloadAllTimelines()`, which is what
/// drives WidgetKit to ask this provider for a new timeline. Each timeline
/// is a single entry with a `.never` reload policy — the app is entirely in
/// charge of freshness.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(SnapshotEntry(date: Date(), snapshot: .placeholder))
        } else {
            completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshotIO.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotIO.load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}
