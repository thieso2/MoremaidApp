import Foundation

/// Per-project search history stored in UserDefaults.
/// Shared between Find in Page and Find in Files.
enum SearchHistory {
    private static let maxEntries = 20
    private static let defaultsKey = "searchHistory"

    /// Get recent search terms for a project directory.
    static func terms(for directoryPath: String) -> [String] {
        let all = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] ?? [:]
        return all[directoryPath] ?? []
    }

    /// Add a search term to the project's history.
    static func add(_ term: String, for directoryPath: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }

        var all = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] ?? [:]
        var history = all[directoryPath] ?? []

        // Remove duplicates, prepend new term
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)

        // Cap size
        if history.count > maxEntries {
            history = Array(history.prefix(maxEntries))
        }

        all[directoryPath] = history
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }
}
