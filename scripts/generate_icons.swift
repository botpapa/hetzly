#!/usr/bin/env swift
//
// generate_icons.swift
//
// Rasterizes Hetzi (the pixel-art marten mascot) into four 1024x1024 app
// icon PNGs and writes them straight into the appiconsets under
// Hetzly/Resources/Assets.xcassets, alongside their Contents.json.
//
// Zero third-party tools: CoreGraphics + ImageIO only, run with
// `swift scripts/generate_icons.swift` from the repo root.
//
// The 32x32 idle-frame-0 pixel grid below is copied verbatim from
// `Hetzly/Mascot/MascotFrameData+Idle.swift` (first frame of the `idle`
// array) and the palette below mirrors `Hetzly/Mascot/MascotPalette.swift`.
// This script intentionally does not import the app target (it is a build
// tool, not app code), so the art/palette are duplicated here rather than
// shared — if the idle frame or palette changes, re-sync both by hand.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Mascot source (idle animation, frame 0)

let idleFrame0: [String] = [
    "................................",
    "................................",
    "................................",
    ".....ddd........................",
    "....rddd........................",
    "..rrrddd........................",
    ".rrrrrr.........................",
    ".rrrrr..................ddd.....",
    ".rrrrr.............ddd.rdpp.....",
    "rrrrr..............ppdrrdpp.....",
    "rrrrrr.............ppdrrdddr....",
    "rrrrrr.............dddrrrwrr....",
    "rrrrrr...........rrrrrrrkrrr....",
    "rrrrr...........rrrrrrrrrrrrck..",
    ".rrrrr..........rrrrrrrrrrrrcc..",
    "rrrrrrr.......r.rrrrrrrrrrrrrr..",
    "rrrrrrr...rrrrrrrrrrrrrrrrrr....",
    "rrrrrrr..rrrrrrrrrrrrrrrrrr.....",
    ".rrrrrrrrrrrrrrrrrcrrrrr........",
    "..rrrrrrrrrrrrrcccccccr.........",
    "..rrrrrrrrrrrrccccccccc.........",
    ".rrrrrrrrrrrrrccccccccc.........",
    "..rrrrrrrrrrrrccccccccc.........",
    "..rrrrrrrrrrrccccccccccc........",
    "...rrrrrrrrrrrccccccccc.........",
    "...rrrrrrrrrrrccccccccc.........",
    "....rrrrrrrrccccccccccc.........",
    "....rrrrrrr.cccccdddcddd........",
    ".....rrrrdddd....ddd.ddd........",
    ".......r.dddd....ddd.ddd........",
    ".........dddd....ddd.ddd........",
    "................................",
]

let gridSize = 32

// MARK: - Palettes

struct RGB {
    let r: Double
    let g: Double
    let b: Double

    init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = Double(r) / 255
        self.g = Double(g) / 255
        self.b = Double(b) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Mirrors `MascotPalette.color(for:)`'s rust-on-dark palette.
func rustPixel(_ character: Character) -> RGB? {
    switch character {
    case ".": nil
    case "k": RGB(0x1B, 0x15, 0x12) // outline
    case "r": RGB(0xC1, 0x64, 0x3B) // rust
    case "d": RGB(0x8F, 0x45, 0x27) // dark rust
    case "c": RGB(0xF2, 0xE3, 0xC6) // cream
    case "p": RGB(0xE8, 0xA2, 0xA0) // pink
    case "w": RGB(0xFF, 0xFF, 0xFF) // white
    default: nil
    }
}

/// Grayscale (relative luminance) of the rust palette, for the Mono icon.
func monoPixel(_ character: Character) -> RGB? {
    guard let base = rustPixel(character) else { return nil }
    let luminance = 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b
    return RGB(r: luminance, g: luminance, b: luminance)
}

/// A dark, warm duotone silhouette (outline darkest, belly lightest-of-the-
/// darks) for the Light icon, so the mascot stays legible on a light canvas.
func lightPixel(_ character: Character) -> RGB? {
    switch character {
    case ".": nil
    case "k": RGB(0x14, 0x12, 0x10)
    case "r": RGB(0x3A, 0x2A, 0x22)
    case "d": RGB(0x24, 0x1A, 0x14)
    case "c": RGB(0x6E, 0x5A, 0x44)
    case "p": RGB(0x55, 0x38, 0x34)
    case "w": RGB(0x24, 0x1A, 0x14)
    default: nil
    }
}

// MARK: - Variants

enum Variant: String, CaseIterable {
    case appIcon = "AppIcon"
    case mono = "AppIcon-Mono"
    case light = "AppIcon-Light"
    case hetzi = "AppIcon-Hetzi"

    /// Upscale factor applied to the 32x32 grid (nearest-neighbor).
    var scale: CGFloat {
        switch self {
        case .hetzi: 30 // fills more of the frame
        default: 24 // ~768px
        }
    }

    /// How far to push the mascot's vertical center below true-center.
    var verticalBiasFraction: CGFloat {
        switch self {
        case .hetzi: 0.01 // almost no headroom left to spare
        default: 0.045
        }
    }

    var pixelColor: (Character) -> RGB? {
        switch self {
        case .appIcon, .hetzi: rustPixel
        case .mono: monoPixel
        case .light: lightPixel
        }
    }

    var backgroundTop: RGB {
        self == .light ? RGB(0xF7, 0xF7, 0xF9) : RGB(0x0A, 0x0A, 0x0C)
    }

    var backgroundBottom: RGB {
        self == .light ? RGB(0xED, 0xED, 0xF0) : RGB(0x14, 0x14, 0x18)
    }

    /// The faint bottom glow color, or `nil` when the variant carries no accent.
    var glowColor: RGB? {
        switch self {
        case .appIcon: RGB(0xF0, 0x48, 0x3E) // HetzlyColors.accent
        case .mono: RGB(0xFF, 0xFF, 0xFF)
        case .light, .hetzi: nil
        }
    }

    var glowAlpha: Double {
        self == .mono ? 0.10 : 0.32
    }

    /// Whether to draw the 1px glass edge-highlight line near the bottom.
    var drawsEdgeLine: Bool {
        self != .light
    }
}

// MARK: - Drawing

let canvasSize: CGFloat = 1024

func makeContext() -> CGContext {
    guard
        let context = CGContext(
            data: nil,
            width: Int(canvasSize),
            height: Int(canvasSize),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            // App icons must be fully opaque (no alpha channel) or the App
            // Store / actool will flag them; the gradient background fills
            // the canvas edge-to-edge, so this is `noneSkipLast`, not
            // premultiplied.
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else {
        print("error: could not create CGContext")
        exit(1)
    }
    // Flip to a conventional top-left-origin, y-down space so the drawing
    // code below reads the same way the frame art and MascotView's own
    // Canvas code do (row 0 = top).
    context.translateBy(x: 0, y: canvasSize)
    context.scaleBy(x: 1, y: -1)
    return context
}

func drawVerticalGradient(ctx: CGContext, top: RGB, bottom: RGB) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(colorSpace: colorSpace, components: [top.r, top.g, top.b, 1]),
        CGColor(colorSpace: colorSpace, components: [bottom.r, bottom.g, bottom.b, 1]),
    ] as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else {
        print("error: could not create background gradient")
        exit(1)
    }
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvasSize / 2, y: 0),
        end: CGPoint(x: canvasSize / 2, y: canvasSize),
        options: []
    )
    ctx.restoreGState()
}

/// A soft glow that intensifies toward the bottom edge, simulating light
/// spilling from behind a glass edge the mascot peeks over.
func drawBottomGlow(ctx: CGContext, color: RGB, alpha: Double) {
    let bandTop = canvasSize * 0.60
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(colorSpace: colorSpace, components: [color.r, color.g, color.b, 0]),
        CGColor(colorSpace: colorSpace, components: [color.r, color.g, color.b, alpha]),
    ] as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else {
        print("error: could not create glow gradient")
        exit(1)
    }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: bandTop, width: canvasSize, height: canvasSize - bandTop))
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvasSize / 2, y: bandTop),
        end: CGPoint(x: canvasSize / 2, y: canvasSize),
        options: []
    )
    ctx.restoreGState()
}

/// A faint 1-glass-edge highlight: a thin near-white horizontal line.
func drawEdgeLine(ctx: CGContext, y: CGFloat) {
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
    ctx.fill(CGRect(x: 0, y: y, width: canvasSize, height: 2))
    ctx.restoreGState()
}

/// Nearest-neighbor upscales the 32x32 frame grid and paints it centered
/// horizontally, vertically offset a little below true-center.
func drawMascot(ctx: CGContext, variant: Variant) {
    let side = variant.scale * CGFloat(gridSize)
    let originX = (canvasSize - side) / 2
    let originY = (canvasSize - side) / 2 + canvasSize * variant.verticalBiasFraction

    for (rowIndex, row) in idleFrame0.enumerated() {
        for (colIndex, character) in row.enumerated() {
            guard let color = variant.pixelColor(character) else { continue }
            let rect = CGRect(
                x: originX + CGFloat(colIndex) * variant.scale,
                y: originY + CGFloat(rowIndex) * variant.scale,
                width: variant.scale,
                height: variant.scale
            )
            ctx.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
            ctx.fill(rect)
        }
    }
}

func render(_ variant: Variant) -> CGImage {
    let ctx = makeContext()
    drawVerticalGradient(ctx: ctx, top: variant.backgroundTop, bottom: variant.backgroundBottom)
    if let glowColor = variant.glowColor {
        drawBottomGlow(ctx: ctx, color: glowColor, alpha: variant.glowAlpha)
    }
    if variant.drawsEdgeLine {
        drawEdgeLine(ctx: ctx, y: canvasSize - 164)
    }
    drawMascot(ctx: ctx, variant: variant)
    guard let image = ctx.makeImage() else {
        print("error: could not rasterize \(variant.rawValue)")
        exit(1)
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("error: could not create PNG destination at \(url.path)")
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        print("error: could not write PNG at \(url.path)")
        exit(1)
    }
}

let contentsJSONTemplate = """
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

// MARK: - Main

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsRoot = repoRoot
    .appendingPathComponent("Hetzly")
    .appendingPathComponent("Resources")
    .appendingPathComponent("Assets.xcassets")

guard FileManager.default.fileExists(atPath: assetsRoot.path) else {
    print("error: expected asset catalog at \(assetsRoot.path)")
    exit(1)
}

for variant in Variant.allCases {
    let appiconsetURL = assetsRoot.appendingPathComponent("\(variant.rawValue).appiconset")
    do {
        try FileManager.default.createDirectory(at: appiconsetURL, withIntermediateDirectories: true)
        let image = render(variant)
        writePNG(image, to: appiconsetURL.appendingPathComponent("icon-1024.png"))
        try contentsJSONTemplate.write(
            to: appiconsetURL.appendingPathComponent("Contents.json"),
            atomically: true,
            encoding: .utf8
        )
        print("wrote \(variant.rawValue).appiconset/icon-1024.png")
    } catch {
        print("error: \(variant.rawValue) failed: \(error)")
        exit(1)
    }
}

print("Done. Generated \(Variant.allCases.count) app icon variants.")
