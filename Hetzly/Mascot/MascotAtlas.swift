/// A single parsed animation frame: a 32x32 grid of `MascotPalette` indices.
///
/// Row-major: `frame[row][column]`, `row` 0 is the top of the sprite.
typealias MascotFrameGrid = [[UInt8]]

/// Parses the compact string art in `MascotFrameData` into `MascotFrameGrid`
/// values once, lazily, and caches them for the lifetime of the process.
///
/// Parsing (not just storage) happens here rather than at draw time so
/// `MascotView` never re-parses strings per frame — `MascotEngine` hands it
/// already-decoded `[[UInt8]]` grids.
struct MascotAtlas: Sendable {
    /// Every sprite frame is a square grid of this side length.
    static let gridSize = 32

    /// Process-wide parsed atlas. Swift initializes `static let` lazily and
    /// thread-safely exactly once, so this only pays the parsing cost the
    /// first time any `MascotState`'s frames are needed.
    static let shared = MascotAtlas()

    private let framesByState: [MascotState: [MascotFrameGrid]]

    private init() {
        var map: [MascotState: [MascotFrameGrid]] = [:]
        for state in MascotState.allCases {
            map[state] = MascotAtlas.rawFrames(for: state).map(MascotAtlas.parse)
        }
        framesByState = map
    }

    /// The parsed frame sequence for a state, in playback order.
    func frames(for state: MascotState) -> [MascotFrameGrid] {
        framesByState[state] ?? []
    }

    private static func rawFrames(for state: MascotState) -> [[String]] {
        switch state {
        case .idle: return MascotFrameData.idle
        case .walk: return MascotFrameData.walk
        case .run: return MascotFrameData.run
        case .sleep: return MascotFrameData.sleep
        case .alarm: return MascotFrameData.alarm
        case .celebrate: return MascotFrameData.celebrate
        case .work: return MascotFrameData.work
        case .peek: return MascotFrameData.peek
        }
    }

    /// Decodes one frame's rows of art characters into palette indices.
    ///
    /// All frame art in `MascotFrameData` is authored and validated offline
    /// (see the sprite-generation tooling referenced in the Mascot module's
    /// design notes), so a malformed frame indicates a source bug, not a
    /// runtime/user condition — hence `precondition` rather than `throws`.
    private static func parse(_ rows: [String]) -> MascotFrameGrid {
        precondition(
            rows.count == gridSize,
            "Mascot frame must have exactly \(gridSize) rows, got \(rows.count)"
        )
        return rows.map { row in
            let characters = Array(row)
            precondition(
                characters.count == gridSize,
                "Mascot frame row must have exactly \(gridSize) columns, got \(characters.count): \(row)"
            )
            return characters.map { character -> UInt8 in
                guard let index = MascotPalette.characterIndex[character] else {
                    preconditionFailure("Unknown mascot palette character '\(character)' in frame row: \(row)")
                }
                return index.rawValue
            }
        }
    }
}
