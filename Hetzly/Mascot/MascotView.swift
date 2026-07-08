import SwiftUI

/// Renders Hetzi, the pixel-art marten mascot, animating through the frames
/// for a given `MascotState`.
///
/// Pixels are drawn as individual `Canvas` rectangle fills rather than an
/// `Image`, so there is no bitmap to interpolate: edges are always crisp,
/// nearest-neighbor-sharp squares at any `scale`. When
/// `accessibilityReduceMotion` is enabled the view renders the state's first
/// frame once and stops driving the animation timeline entirely.
struct MascotView: View {
    let state: MascotState
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: MascotState, scale: CGFloat = 2) {
        self.state = state
        self.scale = scale
    }

    private var side: CGFloat {
        CGFloat(MascotAtlas.gridSize) * scale
    }

    var body: some View {
        let sequence = MascotEngine.sequence(for: state)
        Group {
            if reduceMotion {
                MascotPixelCanvas(grid: sequence.grids.first ?? [], scale: scale)
            } else {
                TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                    MascotPixelCanvas(grid: sequence.grid(at: timeline.date), scale: scale)
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Paints one already-decoded frame grid as flat-colored pixel rectangles.
///
/// Runs of identical palette indices within a row are merged into a single
/// fill rect (up to 32 fills per row worst case, typically far fewer) rather
/// than one fill per pixel, which keeps `Canvas` drawing cheap even when
/// several `MascotView`s animate on screen at once.
private struct MascotPixelCanvas: View {
    let grid: MascotFrameGrid
    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            for (rowIndex, row) in grid.enumerated() {
                var column = 0
                while column < row.count {
                    let paletteIndex = row[column]
                    var runLength = 1
                    while column + runLength < row.count, row[column + runLength] == paletteIndex {
                        runLength += 1
                    }
                    if let color = MascotPalette.color(for: paletteIndex) {
                        let rect = CGRect(
                            x: CGFloat(column) * scale,
                            y: CGFloat(rowIndex) * scale,
                            width: CGFloat(runLength) * scale,
                            height: scale
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                    column += runLength
                }
            }
        }
        .frame(
            width: CGFloat(MascotAtlas.gridSize) * scale,
            height: CGFloat(MascotAtlas.gridSize) * scale
        )
    }
}

#Preview {
    VStack(spacing: 24) {
        MascotView(state: .idle, scale: 4)
        MascotView(state: .run, scale: 4)
    }
    .padding(40)
    .background(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0C / 255))
    .preferredColorScheme(.dark)
}
