import Observation

/// Root dependency-injection container for the app, injected into the
/// environment from `HetzlyApp` and consumed by feature views.
///
/// Wave 1: intentionally empty placeholder so the app shell compiles and
/// `RootView` has something to hold onto via `.environment`.
///
/// Wave 2 wires this up with the real dependencies: `HetznerHTTPClient`
/// instances for Cloud + Robot, `KeychainStore` / `TokenVault` for
/// credential persistence, `BiometricGate` for unlock, and any on-device
/// stores (cost dashboard cache, onboarding state, etc.).
@MainActor
@Observable
final class AppContainer {
    private init() {}

    static func makeDefault() -> AppContainer {
        AppContainer()
    }
}
