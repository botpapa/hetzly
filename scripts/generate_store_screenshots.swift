#!/usr/bin/env swift
//
// Composites raw device screenshots (docs/screenshots/*.png, 1320x2868) into
// App Store marketing images with a branded dark background + headline text.
// Output: docs/store/*.png at the 6.9" required size. CoreGraphics + CoreText,
// no third-party tools.
//
import AppKit
import CoreText
import Foundation

let W = 1320, H = 2868
let inDir = "docs/screenshots"
let outDir = "docs/store"

// (source file, headline lines, accent subline)
let shots: [(String, [String], String)] = [
    ("01-dashboard",        ["Your whole Hetzner", "cloud, at a glance"],  "Unlimited projects · live status"),
    ("02-server-control",   ["Full control of", "every server"],          "Power, rescale, rescue, backups"),
    ("03-server-analytics", ["Live metrics,", "beautifully rendered"],     "CPU · network · disk, scrubbable"),
    ("04-costs",            ["Know exactly", "what you spend"],            "On-device cost dashboard"),
    ("05-resources",        ["Volumes, firewalls,", "DNS & more"],         "Full Cloud resource management"),
    ("06-settings",         ["Private by design"],                         "Tokens never leave your device"),
]

func hex(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// Draw centered multi-line text; `topY` is distance from the TOP of the canvas.
func drawHeadline(_ ctx: CGContext, lines: [String], font: NSFont, color: CGColor, topY: CGFloat, lineHeight: CGFloat) {
    for (i, line) in lines.enumerated() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color)!,
            .kern: -0.5,
        ]
        let attr = NSAttributedString(string: line, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attr)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
        let x = (CGFloat(W) - width) / 2
        let yFromTop = topY + CGFloat(i) * lineHeight
        ctx.textPosition = CGPoint(x: x, y: CGFloat(H) - yFromTop - ascent)
        CTLineDraw(ctLine, ctx)
    }
}

func roundedClip(_ ctx: CGContext, rect: CGRect, radius: CGFloat) {
    let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(p); ctx.clip()
}

func render(_ name: String, headline: [String], subline: String) {
    guard let shot = loadImage("\(inDir)/\(name).png") else { print("missing \(name)"); return }
    let ctx = makeContext()

    // Background: vertical gradient, near-black to a slightly warmer dark.
    let cs = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: cs, colors: [hex(0x0A,0x0A,0x0C), hex(0x18,0x14,0x16)] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: 0), options: [])

    // Soft red accent glow behind the headline.
    let glow = CGGradient(colorsSpace: cs, colors: [hex(0xF0,0x48,0x3E,0.28), hex(0xF0,0x48,0x3E,0)] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: CGFloat(W)/2, y: CGFloat(H) - 300), startRadius: 0,
                           endCenter: CGPoint(x: CGFloat(W)/2, y: CGFloat(H) - 300), endRadius: 760, options: [])

    // Headline + subline.
    let titleFont = NSFont.systemFont(ofSize: 108, weight: .bold)
    drawHeadline(ctx, lines: headline, font: titleFont, color: hex(0xF5,0xF5,0xF7), topY: 200, lineHeight: 122)
    let subTop = 200 + CGFloat(headline.count) * 122 + 24
    let subFont = NSFont.systemFont(ofSize: 46, weight: .medium)
    drawHeadline(ctx, lines: [subline], font: subFont, color: hex(0xF0,0x48,0x3E), topY: subTop, lineHeight: 56)

    // Device screenshot: scaled, rounded, top-aligned below the header,
    // bleeding off the bottom edge for a premium look.
    let margin: CGFloat = 132
    let shotW = CGFloat(W) - margin * 2
    let scale = shotW / CGFloat(shot.width)
    let shotH = CGFloat(shot.height) * scale
    let shotTopFromTop: CGFloat = subTop + 130
    let rect = CGRect(x: margin, y: CGFloat(H) - shotTopFromTop - shotH, width: shotW, height: shotH)

    // Subtle border glow under the frame.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: hex(0,0,0,0.55))
    let border = CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.addPath(border); ctx.setFillColor(hex(0x0A,0x0A,0x0C)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    roundedClip(ctx, rect: rect, radius: 56)
    ctx.draw(shot, in: rect)
    ctx.restoreGState()

    // Hairline rounded border.
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil))
    ctx.setStrokeColor(hex(0xFF,0xFF,0xFF,0.10)); ctx.setLineWidth(2); ctx.strokePath()

    guard let img = ctx.makeImage() else { return }
    let outURL = URL(fileURLWithPath: "\(outDir)/\(name).png")
    let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(outURL.path)")
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, headline, sub) in shots { render(name, headline: headline, subline: sub) }
print("Done. \(shots.count) store screenshots.")
