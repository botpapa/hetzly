import XCTest
@testable import Hetzly

/// Covers `DashboardViewModel.burn(for:)` — the combined-vs-scoped cost math
/// backing the multi-project `ProjectFilterBar`. Uses the view model's
/// test/preview init (see `DashboardViewModel.init(projectSections:...)`) to
/// seed `monthToDate`/`projected`/`perProjectBurn` directly, with no
/// `AppContainer`, network, or `CostEngine` computation involved — this
/// isolates the lookup logic itself (nil-selection → combined, non-nil
/// selection → that project's entry or `(nil, nil)` if absent).
@MainActor
final class DashboardViewModelBurnTests: XCTestCase {
    func test_burn_withNilProjectID_returnsCombinedTotals() {
        let production = UUID()
        let staging = UUID()

        let viewModel = DashboardViewModel(
            monthToDate: 68.42,
            projected: 154.90,
            currency: "EUR",
            perProjectBurn: [
                production: (monthToDate: 51.20, projected: 118.40),
                staging: (monthToDate: 17.22, projected: 36.50),
            ]
        )

        let combined = viewModel.burn(for: nil)
        XCTAssertEqual(combined.monthToDate, 68.42)
        XCTAssertEqual(combined.projected, 154.90)
    }

    func test_burn_withProjectID_returnsScopedTotals_notCombined() {
        let production = UUID()
        let staging = UUID()

        let viewModel = DashboardViewModel(
            monthToDate: 68.42,
            projected: 154.90,
            currency: "EUR",
            perProjectBurn: [
                production: (monthToDate: 51.20, projected: 118.40),
                staging: (monthToDate: 17.22, projected: 36.50),
            ]
        )

        let productionBurn = viewModel.burn(for: production)
        XCTAssertEqual(productionBurn.monthToDate, 51.20)
        XCTAssertEqual(productionBurn.projected, 118.40)

        let stagingBurn = viewModel.burn(for: staging)
        XCTAssertEqual(stagingBurn.monthToDate, 17.22)
        XCTAssertEqual(stagingBurn.projected, 36.50)

        // Scoped figures are genuinely per-project, not just echoing the
        // combined totals.
        XCTAssertNotEqual(productionBurn.monthToDate, combinedMonthToDate(viewModel))
    }

    /// A project with no cost items yet (e.g. zero servers, or still
    /// loading) has no `perProjectBurn` entry at all — `burn(for:)` must
    /// report `(nil, nil)` for it rather than falling back to the combined
    /// totals or crashing on a missing key.
    func test_burn_forProjectWithNoCostData_returnsNilNil() {
        let production = UUID()
        let sandbox = UUID()

        let viewModel = DashboardViewModel(
            monthToDate: 51.20,
            projected: 118.40,
            currency: "EUR",
            perProjectBurn: [
                production: (monthToDate: 51.20, projected: 118.40),
            ]
        )

        let sandboxBurn = viewModel.burn(for: sandbox)
        XCTAssertNil(sandboxBurn.monthToDate)
        XCTAssertNil(sandboxBurn.projected)
    }

    /// With no cost data loaded at all, both the combined ("All") and any
    /// per-project lookup are `(nil, nil)`.
    func test_burn_withNoCostDataAnywhere_returnsNilNilForAllAndAnyProject() {
        let viewModel = DashboardViewModel()

        let combined = viewModel.burn(for: nil)
        XCTAssertNil(combined.monthToDate)
        XCTAssertNil(combined.projected)

        let scoped = viewModel.burn(for: UUID())
        XCTAssertNil(scoped.monthToDate)
        XCTAssertNil(scoped.projected)
    }

    private func combinedMonthToDate(_ viewModel: DashboardViewModel) -> Decimal? {
        viewModel.burn(for: nil).monthToDate
    }
}
