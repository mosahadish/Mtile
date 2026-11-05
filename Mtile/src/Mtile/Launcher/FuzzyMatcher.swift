/// dmenu-style fuzzy matching: the query must appear as a (case-insensitive) subsequence of the
/// candidate, in order but not necessarily contiguous -- "ffx" matches "FireFoX". Scoring rewards
/// matches that start earlier in the candidate and run together. Exact port of Wtile's
/// FuzzyMatcher, so the launcher ranks identically on both platforms.
public enum FuzzyMatcher {
    /// Higher is a better match; nil means the query isn't a subsequence of candidate at all. An
    /// empty query matches everything with a score of 0.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.uppercased())
        let c = Array(candidate.uppercased())
        if q.isEmpty { return 0 }
        if c.count < q.count { return nil }

        var score = 0
        var candidateIndex = 0
        var previousMatchIndex = -1
        for want in q {
            var found = -1
            var i = candidateIndex
            while i < c.count {
                if c[i] == want {
                    found = i
                    break
                }
                i += 1
            }
            if found < 0 { return nil }

            if found == 0 { score += 10 } // matches at the very start of the candidate
            if previousMatchIndex >= 0 && found == previousMatchIndex + 1 { score += 5 } // contiguous run
            score += max(0, 10 - found) // earlier matches score higher than later ones

            previousMatchIndex = found
            candidateIndex = found + 1
        }
        return score
    }
}
