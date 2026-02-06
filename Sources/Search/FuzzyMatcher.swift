import Foundation

/// Fuzzy string matching with scoring, replicating MiniSearch-like behavior.
enum FuzzyMatcher {

    struct Match: Comparable {
        let item: FileEntry
        let score: Double

        static func == (lhs: Match, rhs: Match) -> Bool {
            lhs.score == rhs.score
        }

        static func < (lhs: Match, rhs: Match) -> Bool {
            lhs.score < rhs.score
        }
    }

    /// Fuzzy match files against a query, returning sorted results.
    /// Replicates MiniSearch config: boost fileName 2x, fuzzy 0.2, prefix matching.
    static func search(query: String, files: [FileEntry]) -> [FileEntry] {
        let lowQuery = query.lowercased()
        guard !lowQuery.isEmpty else { return files }

        var matches: [Match] = []

        for file in files {
            let fileName = file.name.lowercased()
            let filePath = file.relativePath.lowercased()

            var score = 0.0

            // Exact substring match in filename (highest priority)
            if fileName.contains(lowQuery) {
                score += 10.0
                // Bonus for match at start
                if fileName.hasPrefix(lowQuery) {
                    score += 5.0
                }
                // Bonus for exact match
                if fileName == lowQuery || fileName == lowQuery + ".md" {
                    score += 10.0
                }
            }

            // Exact substring match in path
            if score == 0 && filePath.contains(lowQuery) {
                score += 3.0
            }

            // Prefix matching: each word in query prefix-matches a word in filename
            if score == 0 {
                let queryWords = lowQuery.split(separator: " ")
                let separators: Set<Character> = ["-", "_", " ", "."]
                let fileWords = fileName.split(whereSeparator: { separators.contains($0) })
                let prefixMatches = queryWords.filter { qw in
                    fileWords.contains { fw in fw.hasPrefix(qw) }
                }
                if !prefixMatches.isEmpty {
                    score += Double(prefixMatches.count) * 2.0
                }
            }

            // Fuzzy matching (Levenshtein-based, tolerance = 0.2 * query length)
            if score == 0 {
                let maxDistance = max(1, Int(Double(lowQuery.count) * 0.2))
                let fileNameWithoutExt = (fileName as NSString).deletingPathExtension.lowercased()
                let distance = levenshteinDistance(lowQuery, fileNameWithoutExt)
                if distance <= maxDistance {
                    score += max(0.1, 1.0 - Double(distance) / Double(lowQuery.count))
                }
            }

            if score > 0 {
                // Boost filename matches by 2x (MiniSearch config)
                let fileNameBoost = fileName.contains(lowQuery) ? 2.0 : 1.0
                matches.append(Match(item: file, score: score * fileNameBoost))
            }
        }

        return matches.sorted(by: >).map(\.item)
    }

    /// Compute Levenshtein edit distance between two strings.
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,     // insertion
                    prev[j] + 1,         // deletion
                    prev[j - 1] + cost   // substitution
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
