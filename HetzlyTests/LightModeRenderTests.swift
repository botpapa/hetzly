import HetznerKit
import SwiftUI
import UIKit
import XCTest
@testable import Hetzly

/// Light-mode counterpart to `SnapshotLiteTests`: the same "snapshot-lite"
/// render-and-sample-pixels approach (see `RenderTestSupport`), but with
/// `.environment(\.colorScheme, .light)` forced on each view so
/// `HetzlyColors`' trait-adaptive colors resolve to their light variants.
/// Dark-mode tests in `SnapshotLiteTests` are untouched — this file only
/// adds coverage, it never changes existing (dark) assertions.
///
/// Each test checks two things a broken light-mode adaptation would visibly
/// fail:
/// 1. The canvas corner is *light* (not the near-black dark-mode fill).
/// 2. Text/content still renders with dark-enough pixels somewhere in
///    frame — i.e. text didn't stay `textPrimary`'s *dark-mode* near-white
///    value and vanish against the new light canvas.
@MainActor
final class LightModeRenderTests: XCTestCase {
    private let scale: CGFloat = 2

    // MARK: - BurnCardView

    func test_burnCardView_rendersInLightMode() throws {
        let size = CGSize(width: 340, height: 170)
        let view = ZStack {
            CanvasBackground()
            BurnCardView(monthToDate: 42.18, projected: 96.40, currency: "EUR", idleMascotState: .idle)
                .padding(Spacing.screenMargin)
        }
        .environment(\.colorScheme, .light)

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertLightCorner(of: image)
        assertHasDarkContent(in: image)
    }

    // MARK: - ServerRowView

    func test_serverRowView_rendersInLightMode() throws {
        let size = CGSize(width: 340, height: 110)
        let item = ServerListItem(
            projectID: UUID(),
            serverID: 1,
            name: "web-01",
            status: .running,
            typeName: "cx22",
            city: "Falkenstein",
            countryCode: "DE"
        )
        let view = ZStack {
            CanvasBackground()
            ServerRowView(item: item, cpuSamples: [12, 20, 18, 34, 40, 30, 22])
                .padding(Spacing.screenMargin)
        }
        .environment(\.colorScheme, .light)

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertLightCorner(of: image)
        assertHasDarkContent(in: image)
    }

    // MARK: - GlassCard

    func test_glassCard_rendersInLightMode() throws {
        let size = CGSize(width: 220, height: 120)
        let view = ZStack {
            CanvasBackground()
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text("cx22 · nbg1-dc3").bodyPrimary()
                    Text("2 vCPU · 4 GB RAM · 40 GB").bodySecondary()
                }
            }
            .padding(Spacing.screenMargin)
        }
        .environment(\.colorScheme, .light)

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertLightCorner(of: image)
        assertHasDarkContent(in: image)
    }

    // MARK: - GlassCard/GlassChip/GlassSurface reduce-transparency fallback fill

    /// `accessibilityReduceTransparency` is a system-driven, read-only
    /// `EnvironmentValues` key on this SDK (no `.environment(\...,  _:)`
    /// override exists to force it in a render test), so this exercises the
    /// exact color `GlassCard`/`GlassChip`/`GlassSurface`'s reduce-transparency
    /// fallback path renders — `HetzlyColors.glassFallbackFill` — directly
    /// against a light `UITraitCollection`, the same mechanism SwiftUI uses
    /// under the hood to resolve a `UIColor`-backed `Color` at render time.
    /// This is the one place a stray hard-coded `Color(white: 0.12)` would
    /// most visibly reappear as a dark blob on the new light canvas.
    func test_glassFallbackFill_resolvesLightUnderLightTraitCollection() {
        let uiColor = UIColor(HetzlyColors.glassFallbackFill)

        let lightResolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        lightResolved.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        XCTAssertGreaterThan(
            lr + lg + lb, 2.0,
            "expected the reduce-transparency fallback fill to resolve light under a light trait collection, got r=\(lr) g=\(lg) b=\(lb)"
        )

        // Dark stays pixel-identical to the original hard-coded `Color(white: 0.12)`.
        let darkResolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        darkResolved.getRed(&dr, green: &dg, blue: &db, alpha: &da)
        XCTAssertEqual(dr, 0.12, accuracy: 0.01)
        XCTAssertEqual(dg, 0.12, accuracy: 0.01)
        XCTAssertEqual(db, 0.12, accuracy: 0.01)
    }

    // MARK: - CostsHeroCard

    func test_costsHeroCard_rendersInLightMode() throws {
        let size = CGSize(width: 340, height: 230)
        let view = ZStack {
            CanvasBackground()
            CostsHeroCard(
                monthToDate: Decimal(string: "38.62"),
                projected: Decimal(string: "154.90"),
                currency: "EUR",
                monthElapsedFraction: 0.26
            )
            .padding(Spacing.screenMargin)
        }
        .environment(\.colorScheme, .light)

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertLightCorner(of: image)
        assertHasDarkContent(in: image)
    }

    // MARK: - Shared assertions

    /// `CanvasBackground` in light mode is a soft off-white (#F5F5F7) fill
    /// with a barely-there radial depth gradient — any corner, away from
    /// centered card content, should read as light. Mirrors
    /// `SnapshotLiteTests.assertNearBlackCorner`'s corner-sampling approach,
    /// inverted for the light threshold.
    private func assertLightCorner(of image: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        guard let pixel = RenderTestSupport.pixel(of: image, x: 2, y: 2) else {
            XCTFail("couldn't sample corner pixel", file: file, line: line)
            return
        }
        let sum = Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
        XCTAssertGreaterThan(sum, 600, "expected a light corner, got \(pixel)", file: file, line: line)
    }

    /// Scans a coarse grid across the image for at least one dark-enough
    /// pixel — evidence that `textPrimary`/`textSecondary` actually
    /// resolved to their *light-mode* (dark ink) values and rendered
    /// legible text/content, rather than silently staying near-white and
    /// vanishing against the light canvas.
    private func assertHasDarkContent(in image: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        var foundDark = false
        let steps = 24
        for xi in 0...steps {
            for yi in 0...steps {
                let x = Int(Double(image.width) * Double(xi) / Double(steps))
                let y = Int(Double(image.height) * Double(yi) / Double(steps))
                guard let pixel = RenderTestSupport.pixel(of: image, x: x, y: y) else { continue }
                let sum = Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
                if sum < 400, pixel.a > 0 {
                    foundDark = true
                    break
                }
            }
            if foundDark { break }
        }
        XCTAssertTrue(
            foundDark,
            "expected at least one dark-enough pixel (legible text/content) in light mode",
            file: file, line: line
        )
    }
}
