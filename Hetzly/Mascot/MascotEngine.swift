import Foundation

/// Maps a `MascotState` to its frame sequence and playback speed, and picks
/// the frame to display at a given point in time.
///
/// Playback is a deterministic function of wall-clock time (no timers, no
/// mutable state) so it works naturally with `TimelineView`: every observer
/// computing `frame(at:)` for the same `Date` gets the same frame, and there
/// is nothing to start, stop, or leak.
struct MascotEngine: Sendable {
    /// A resolved, playable frame sequence for one state.
    struct Sequence: Sendable {
        let grids: [MascotFrameGrid]
        let frameDuration: TimeInterval

        /// Total time to play through all frames once before looping.
        var cycleDuration: TimeInterval {
            frameDuration * Double(grids.count)
        }

        /// The frame that should be on screen at `date`, looping forever.
        func grid(at date: Date) -> MascotFrameGrid {
            guard !grids.isEmpty, frameDuration > 0 else { return [] }
            let elapsed = date.timeIntervalSince1970
            let cycled = elapsed.truncatingRemainder(dividingBy: cycleDuration)
            let normalized = cycled < 0 ? cycled + cycleDuration : cycled
            let index = min(grids.count - 1, Int(normalized / frameDuration))
            return grids[index]
        }
    }

    /// Builds the playable sequence for `state` from the shared parsed atlas.
    static func sequence(for state: MascotState) -> Sequence {
        Sequence(grids: MascotAtlas.shared.frames(for: state), frameDuration: frameDuration(for: state))
    }

    /// Per-frame duration for each state's animation. Idle/sleep/peek read as
    /// calm and slow; walk/work are a brisk everyday pace; run is fast enough
    /// to read as a loopable pull-to-refresh spinner.
    static func frameDuration(for state: MascotState) -> TimeInterval {
        // Tuned for the Elthen sheet's frame counts (idle 6, movement 8,
        // sleep 8, attack 8): the sheet was authored at ~100ms/frame.
        switch state {
        case .idle: return 0.16
        case .walk: return 0.12
        case .run: return 0.07
        case .sleep: return 0.28
        case .alarm: return 0.3
        case .celebrate: return 0.12
        case .work: return 0.1
        case .peek: return 0.5
        }
    }
}
