# Hetzly — Module Contracts & Conventions

This document is the coordination contract between parallel workers. Every worker
owns a disjoint set of paths and MUST NOT create or edit files outside them.
Where modules touch, the public API defined here is binding.

## Global conventions (all workers)

- Swift 6 language mode, strict concurrency. No `@unchecked Sendable` unless justified in a comment.
- iOS 26.0 minimum deployment target. Use real iOS 26 Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`) — no fake blurs.
- Zero third-party dependencies. Apple frameworks + stdlib only.
- No force unwraps (`!`), no `try!`, no `fatalError` in app-target code (allowed in tests).
- No `print`/`os_log` of tokens, Authorization headers, or credential-bearing bodies.
- Every SwiftUI view file ends with a `#Preview` using dark mode: `.preferredColorScheme(.dark)`.
- File header comment: none (no boilerplate headers). MIT license lives in LICENSE only.
- Naming: types `UpperCamelCase`, one primary type per file, file named after it.

## Targets

- **HetznerKit** — SPM package at `Packages/HetznerKit`. UI-free. Platforms: iOS 26, macOS 26 (macOS so `swift test` runs on CI/dev Macs). `Package.swift` is already written — do not modify without instruction.
- **Hetzly** — app target, sources globbed from `Hetzly/` by xcodegen (`project.yml`). Depends on local package HetznerKit. Bundle ID `com.hetzly.app`, display name "Hetzly".

## Binding public APIs (cross-module touchpoints)

### HetznerKit Core (`Packages/HetznerKit/Sources/HetznerKit/Core/`)

```swift
public enum AuthMethod: Sendable {
    case bearer(token: String)
    case basic(username: String, password: String)
}

public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let auth: AuthMethod
    public init(baseURL: URL, auth: AuthMethod)
}

/// Abstraction over URLSession so tests inject a mock transport.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct Endpoint: Sendable {
    public var method: HTTPMethod            // GET/POST/PUT/DELETE enum
    public var path: String                  // e.g. "/servers"
    public var query: [URLQueryItem]
    public var body: Data?
    public init(method: HTTPMethod = .get, path: String, query: [URLQueryItem] = [], body: Data? = nil)
}

public enum HetznerAPIError: Error, Sendable {
    case unauthorized                        // 401
    case forbidden(message: String?)         // 403
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case api(code: String, message: String)  // Hetzner error envelope
    case http(status: Int)
    case decoding(underlying: String)
    case transport(underlying: String)
    public var userMessage: String { get }   // human sentence, never raw JSON
}

public actor HetznerHTTPClient {
    public init(configuration: APIConfiguration, transport: HTTPTransport, rateLimiter: RateLimiter)
    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T
    public func sendExpectingNoContent(_ endpoint: Endpoint) async throws
}

public actor RateLimiter {
    public init(budget: Int, window: TimeInterval)   // conservative defaults per API
    public func waitForSlot() async
    public func record(response: HTTPURLResponse)    // reads RateLimit-* headers; 429 → back off to RateLimit-Reset
}

/// Transparent pagination over Hetzner `meta.pagination`.
public func paginated<T: Decodable & Sendable>(
    client: HetznerHTTPClient, endpoint: Endpoint, itemsKey: String, perPage: Int
) -> AsyncThrowingStream<[T], Error>

public actor ResponseCache {
    public init()
    public func value<T: Sendable>(for key: String, ttl: TimeInterval, as type: T.Type) -> T?
    public func store<T: Sendable>(_ value: T, for key: String)
}
```

### DesignSystem (`Hetzly/DesignSystem/`)

```swift
enum HetzlyColors {  // static Color values
    canvas /*#0A0A0C*/, accent /*#F0483E*/, destructive /*#FF5C5C*/,
    textPrimary /*#F5F5F7*/, textSecondary /*#9A9AA2*/, textTertiary /*#5A5A63*/,
    statusRunning /*#30D158*/, statusOff /*#5A5A63*/, statusTransitioning /*#FFD60A*/, statusError /*#FF453A*/
}
enum Spacing { unit=4, screenMargin=20, cardPadding=16 }
enum Radius  { card=24, control=16 }

struct GlassCard<Content: View>: View          // .glassEffect(.regular, in: .rect(cornerRadius: 24)), interactive variant flag
struct GlassChip: View                          // capsule label chip
struct StatusDot: View                          // status enum → color; pulses only when transitioning; respects Reduce Motion
struct SectionLabel: View                       // uppercase, tracking 1.5, textTertiary
struct CanvasBackground: View                   // near-black + subtle radial depth gradient
extension View { func hetzlyMonoNumbers() -> some View }  // SF Mono + monospacedDigit
```

All glass components MUST provide solid fallbacks when `accessibilityReduceTransparency` is on.

### Security (`Hetzly/Security/`)

```swift
struct KeychainStore: Sendable {
    func save(_ data: Data, service: String, account: String) throws     // ThisDeviceOnly, non-synchronizable
    func read(service: String, account: String) throws -> Data?
    func delete(service: String, account: String) throws                  // verified delete
}
@MainActor final class BiometricGate {
    func authenticate(reason: String) async -> Bool   // biometrics w/ passcode fallback
}
struct PrivacyOverlay: ViewModifier                    // blur overlay on scenePhase != .active
struct SecureTokenField: View                          // secure entry + reveal toggle, no autocorrect/caps
```

### Mascot (`Hetzly/Mascot/`)

```swift
enum MascotState: String, CaseIterable { case idle, walk, run, sleep, alarm, celebrate, work, peek }
struct MascotView: View {
    init(state: MascotState, scale: CGFloat = 2)
    // TimelineView(.animation) + Canvas, nearest-neighbor, static frame when Reduce Motion is on
}
```

Sprite atlases: JSON frame data + 32×32 pixel data generated in Swift (or JSON resources), total budget < 300 KB.

### App shell (`Hetzly/App/`)

```swift
@main struct HetzlyApp: App
@MainActor @Observable final class AppContainer   // DI: builds clients, keychain, stores; injected via .environment
struct RootView: View                             // switches Onboarding vs MainTabView placeholder
```

## Verification expected from each worker

- HetznerKit workers: `cd Packages/HetznerKit && swift build && swift test` must pass.
- App-target workers: each Swift file must parse against the iOS SDK:
  `xcrun swiftc -parse -sdk $(xcrun --show-sdk-path --sdk iphonesimulator) -target arm64-apple-ios26.0-simulator <files>`
  (cross-file references may not resolve in isolation — that's fine; syntax and imports must.)
