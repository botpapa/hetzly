import SwiftUI
import XCTest

/// Shared helpers for `HetzlyTests`' snapshot-lite render tests: render a
/// `View` to a `CGImage` via `ImageRenderer` and read back individual pixel
/// values. This is deliberately not golden-file snapshot testing (zero deps,
/// no recorded baseline images to keep in sync) — it exists to catch
/// catastrophic render regressions (a view that crashes, renders at zero
/// size, or renders fully transparent/black where it shouldn't) that a pure
/// logic/compile check would miss.
enum RenderTestSupport {
    struct RGBA: Equatable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    /// Renders `view` at a fixed `size` (points), pinned via `.frame`, so the
    /// resulting `CGImage`'s pixel dimensions are deterministic:
    /// `size * scale`.
    @MainActor
    static func renderCGImage<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage
    }

    /// Reads back a single pixel's RGBA (0...255 per channel) by drawing the
    /// whole image, translated, into a 1×1-pixel bitmap context — a standard
    /// trick that lets Core Graphics do the color-space conversion and
    /// clipping for us rather than hand-rolling raw buffer indexing.
    static func pixel(of image: CGImage, x: Int, y: Int) -> RGBA? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }

        var data = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: CGFloat(-x), y: CGFloat(-y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return RGBA(r: data[0], g: data[1], b: data[2], a: data[3])
    }
}
