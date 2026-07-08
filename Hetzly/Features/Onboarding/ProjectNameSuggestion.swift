import Foundation

/// Derives a human-recognizable project name from a project's server names.
///
/// Hetzner's API deliberately exposes no project metadata for a token —
/// verified empirically against `/project(s)`, `/account`, `/token`, and
/// response headers on both api.hetzner.cloud and api.hetzner.com — so the
/// real Console name can never be fetched. The next best signal is the
/// naming convention people actually use: servers prefixed with the project
/// they belong to ("giga-prod", "giga-db" → "Giga").
enum ProjectNameSuggestion {
    private static let separators = CharacterSet(charactersIn: "-._ ")

    /// - Returns: a capitalized suggestion derived from `serverNames`, or
    ///   `fallback` when nothing recognizable can be derived (no servers, or
    ///   names share no meaningful prefix).
    static func suggest(fromServerNames serverNames: [String], fallback: String) -> String {
        let names = serverNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return fallback }

        if names.count == 1 {
            return stem(of: names[0]) ?? fallback
        }

        // Longest common prefix across all names, then cut back to the last
        // full separator boundary so "web-01"/"web-02" yields "web", never
        // the accidental "web-0".
        var prefix = names[0]
        for name in names.dropFirst() {
            while !prefix.isEmpty && !name.hasPrefix(prefix) {
                prefix.removeLast()
            }
        }
        let common = cutAtSeparatorBoundary(prefix, fullNames: names)
        if let common, common.count >= 3 {
            return common.capitalized
        }
        // No shared convention — fall back to the first server's stem.
        return stem(of: names[0]) ?? fallback
    }

    /// "giga-prod" → "Giga"; "db2" → "Db2"; single-character stems are
    /// too ambiguous to suggest.
    private static func stem(of name: String) -> String? {
        let first = name.components(separatedBy: separators).first ?? name
        guard first.count >= 2 else { return nil }
        return first.capitalized
    }

    /// Trims a raw common prefix back to the last position where every name
    /// continues with a separator (or ends) — i.e. a whole-component prefix.
    private static func cutAtSeparatorBoundary(_ rawPrefix: String, fullNames: [String]) -> String? {
        var candidate = rawPrefix
        while !candidate.isEmpty {
            let isWholeComponent = fullNames.allSatisfy { name in
                guard name.count > candidate.count else { return name == candidate }
                let next = name[name.index(name.startIndex, offsetBy: candidate.count)]
                return String(next).rangeOfCharacter(from: separators) != nil
            }
            if isWholeComponent {
                let trimmed = candidate.trimmingCharacters(in: separators)
                return trimmed.isEmpty ? nil : trimmed
            }
            candidate.removeLast()
        }
        return nil
    }
}
