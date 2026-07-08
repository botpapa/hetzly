/// The behavioral states Hetzi, the pixel-art marten mascot, can be drawn in.
///
/// Each case corresponds to a distinct animated frame sequence produced by
/// `MascotEngine` and rendered by `MascotView`.
enum MascotState: String, CaseIterable, Sendable {
    case idle
    case walk
    case run
    case sleep
    case alarm
    case celebrate
    case work
    case peek
}
