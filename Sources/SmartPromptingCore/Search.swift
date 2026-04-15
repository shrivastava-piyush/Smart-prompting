import Foundation

/// Hybrid search: FTS5 BM25 rank + cosine similarity over embeddings.
///
/// Final score is a weighted blend. Both channels are normalized to `[0, 1]`
/// across the candidate set so the weights behave intuitively.
public final class Search: @unchecked Sendable {
    public struct Weights: Sendable {
        public var fts: Double = 0.4
        public var vector: Double = 0.6
        public init(fts: Double = 0.4, vector: Double = 0.6) {
            self.fts = fts
            self.vector = vector
        }
    }

    private let store: PromptStore
    private let embeddings: Embeddings
    public var weights: Weights

    public init(store: PromptStore, embeddings: Embeddings = .shared, weights: Weights = .init()) {
        self.store = store
        self.embeddings = embeddings
        self.weights = weights
    }

    public func query(_ q: String, limit: Int = 10) throws -> [ScoredPrompt] {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // No query: return most-recently-used.
            return try store.all().prefix(limit).map {
                ScoredPrompt(prompt: $0, score: 0, ftsScore: 0, vectorScore: 0)
            }
        }

        // Channel 1: FTS5
        let ftsHits = (try? store.ftsSearch(trimmed, limit: 100)) ?? []
        var ftsBySlug: [String: Double] = [:]
        // BM25 returns a cost (lower is better, often negative). Invert.
        if !ftsHits.isEmpty {
            let ranks = ftsHits.map { -$0.rank }
            let minR = ranks.min() ?? 0
            let maxR = ranks.max() ?? 0
            let spread = max(maxR - minR, 0.0001)
            for hit in ftsHits {
                let inv = -hit.rank
                ftsBySlug[hit.slug] = (inv - minR) / spread
            }
        }

        // Channel 2: vector cosine
        let qVec = embeddings.embed(trimmed)
        var vecBySlug: [String: Double] = [:]
        let all = try store.allEmbeddings()
        for (slug, vec) in all {
            let sim = Embeddings.cosine(qVec, vec)
            // map [-1,1] → [0,1]
            vecBySlug[slug] = (sim + 1) / 2
        }

        // Blend
        var blended: [(slug: String, score: Double, fts: Double, vec: Double)] = []
        let slugs = Set(ftsBySlug.keys).union(vecBySlug.keys)
        for slug in slugs {
            let f = ftsBySlug[slug] ?? 0
            let v = vecBySlug[slug] ?? 0
            let s = weights.fts * f + weights.vector * v
            blended.append((slug, s, f, v))
        }
        blended.sort { $0.score > $1.score }

        var out: [ScoredPrompt] = []
        for hit in blended.prefix(limit) {
            if let p = try? store.get(slug: hit.slug) {
                out.append(ScoredPrompt(prompt: p, score: hit.score, ftsScore: hit.fts, vectorScore: hit.vec))
            }
        }
        return out
    }
}
