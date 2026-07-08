import Foundation

/// Suggests short, memorable server names in the `adjective-noun-NN` shape
/// (e.g. `"brave-otter-04"`) so the name field is never blank on first paint.
/// "Deterministic-ish": picks uniformly from small, fixed word lists rather
/// than generating free-form text, so suggestions stay short and pronounceable
/// without needing any external dependency.
enum NameGenerator {
    private static let adjectives = [
        "brave", "calm", "swift", "quiet", "bold", "eager", "fuzzy", "gentle",
        "happy", "jolly", "keen", "lively", "mighty", "nimble", "proud", "quick",
        "sunny", "tidy", "vivid", "witty",
    ]

    private static let nouns = [
        "otter", "falcon", "badger", "heron", "marten", "lynx", "raven", "puffin",
        "beaver", "wolf", "sparrow", "fox", "hare", "owl", "seal", "stoat",
        "crane", "ibex", "moth", "wren",
    ]

    static func suggest() -> String {
        let adjective = adjectives.randomElement() ?? "brave"
        let noun = nouns.randomElement() ?? "otter"
        let suffix = String(format: "%02d", Int.random(in: 1...99))
        return "\(adjective)-\(noun)-\(suffix)"
    }
}
