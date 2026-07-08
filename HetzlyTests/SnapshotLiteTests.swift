import HetznerKit
import SwiftUI
import XCTest
@testable import Hetzly

/// "Snapshot-lite" render tests: no golden-file infrastructure (zero deps,
/// nothing to keep in sync across simulator/OS versions) — instead each key
/// view is rendered off-screen via `ImageRenderer` at a fixed size/scale and
/// checked for the class of regression that infrastructure would actually
/// catch in practice: a crash, a zero/garbage-sized image, or a view that
/// renders fully blank where it very much shouldn't (canvas background gone
/// black-on-black, or an accent-tinted control losing its tint entirely).
@MainActor
final class SnapshotLiteTests: XCTestCase {
    private let scale: CGFloat = 2

    // MARK: - BurnCardView

    func test_burnCardView_renders() throws {
        let size = CGSize(width: 340, height: 170)
        let view = ZStack {
            CanvasBackground()
            BurnCardView(monthToDate: 42.18, projected: 96.40, currency: "EUR", idleMascotState: .idle)
                .padding(Spacing.screenMargin)
        }

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertNearBlackCorner(of: image)
    }

    // MARK: - ServerRowView

    func test_serverRowView_renders() throws {
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

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertNearBlackCorner(of: image)
    }

    // MARK: - GlassCard

    func test_glassCard_renders() throws {
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

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertNearBlackCorner(of: image)
    }

    // MARK: - CostsHeroCard

    func test_costsHeroCard_renders() throws {
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

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))

        assertNearBlackCorner(of: image)
    }

    // MARK: - MascotView — every state

    func test_mascotView_allStates_render() throws {
        let side: CGFloat = 128 // 32×32 grid at scale 4.
        for state in MascotState.allCases {
            let view = MascotView(state: state, scale: 4)
            let image = try XCTUnwrap(
                RenderTestSupport.renderCGImage(view, size: CGSize(width: side, height: side), scale: scale),
                "MascotView(state: .\(state)) failed to render"
            )
            XCTAssertEqual(image.width, Int(side * scale), "unexpected width for .\(state)")
            XCTAssertEqual(image.height, Int(side * scale), "unexpected height for .\(state)")
        }
    }

    // MARK: - Accent CTA pixel

    /// A control tinted with `HetzlyColors.accent` (#F0483E) should read
    /// clearly red-dominant somewhere in its bounds — catches the whole
    /// button silently losing its tint (rendering as plain glass/gray).
    /// Samples a grid of points rather than the single center pixel: the
    /// center often lands on the white button label, where r ≈ g ≈ b.
    func test_primaryCTA_accentPixel_isReddish() throws {
        let size = CGSize(width: 220, height: 60)
        let view = ZStack {
            CanvasBackground()
            PrimaryCTA(title: "Create Server") {}
        }

        let image = try XCTUnwrap(RenderTestSupport.renderCGImage(view, size: size, scale: scale))

        var samples: [RenderTestSupport.RGBA] = []
        var foundReddish = false
        for xFraction in stride(from: 0.2, through: 0.8, by: 0.1) {
            for yFraction in stride(from: 0.3, through: 0.7, by: 0.1) {
                let x = Int(Double(image.width) * xFraction)
                let y = Int(Double(image.height) * yFraction)
                guard let pixel = RenderTestSupport.pixel(of: image, x: x, y: y) else { continue }
                samples.append(pixel)
                if Int(pixel.r) > Int(pixel.g) + 20, Int(pixel.r) > Int(pixel.b) + 20 {
                    foundReddish = true
                }
            }
        }

        XCTAssertTrue(
            foundReddish,
            "expected at least one red-dominant pixel across the button's bounds; sampled \(samples)"
        )
    }

    // MARK: - Shared assertions

    /// `CanvasBackground` is a near-black (#0A0A0C) fill with a subtle
    /// radial glow — any corner, away from centered card content, should
    /// read as dark. Doesn't assume a particular pixel-coordinate origin
    /// convention (top-left vs bottom-left): both corners of a
    /// `CanvasBackground`-filled frame are dark, so this is robust either
    /// way.
    private func assertNearBlackCorner(of image: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        guard let pixel = RenderTestSupport.pixel(of: image, x: 2, y: 2) else {
            XCTFail("couldn't sample corner pixel", file: file, line: line)
            return
        }
        XCTAssertLessThan(Int(pixel.r), 60, "expected a near-black corner, got \(pixel)", file: file, line: line)
        XCTAssertLessThan(Int(pixel.g), 60, "expected a near-black corner, got \(pixel)", file: file, line: line)
        XCTAssertLessThan(Int(pixel.b), 60, "expected a near-black corner, got \(pixel)", file: file, line: line)
    }
}
