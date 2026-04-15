import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(CoreML)
import CoreML
#endif

/// Produces fixed-size sentence embeddings.
///
/// Lookup order:
/// 1. A CoreML `.mlmodelc` named `MiniLM` in the host bundle (best quality,
///    produced by `scripts/build-coreml.py`).
/// 2. Apple's built-in `NLEmbedding.sentenceEmbedding(for: .english)`
///    (100-dim, works out of the box on macOS 11+/iOS 14+).
/// 3. A deterministic hashing fallback so the library never crashes in
///    environments (like Linux CI) where neither is available.
public final class Embeddings: @unchecked Sendable {
    public enum Backend: String, Sendable {
        case coreml
        case naturalLanguage
        case hashing
    }

    public static let shared = Embeddings()

    public let backend: Backend
    public let dimension: Int

    #if canImport(NaturalLanguage)
    private let nl: NLEmbedding?
    #endif

    private init() {
        #if canImport(NaturalLanguage)
        // TODO(phase 2): load MiniLM CoreML package here when bundled.
        if let emb = NLEmbedding.sentenceEmbedding(for: .english) {
            self.nl = emb
            self.backend = .naturalLanguage
            self.dimension = emb.dimension
            return
        }
        self.nl = nil
        #endif
        self.backend = .hashing
        self.dimension = 128
    }

    /// Returns an embedding for the given text, always length `dimension`.
    public func embed(_ text: String) -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = trimmed.isEmpty ? "empty" : trimmed

        #if canImport(NaturalLanguage)
        if backend == .naturalLanguage, let nl = nl {
            if let vec = nl.vector(for: input) {
                return vec.map { Float($0) }
            }
            // NLEmbedding works sentence-level; for longer inputs, average token vectors.
            let tokens = tokenize(input)
            var sum = [Double](repeating: 0, count: dimension)
            var n = 0
            for t in tokens {
                if let v = nl.vector(for: t) {
                    for i in 0..<dimension { sum[i] += v[i] }
                    n += 1
                }
            }
            if n > 0 {
                return sum.map { Float($0 / Double(n)) }
            }
        }
        #endif

        return hashingEmbed(input)
    }

    /// Cosine similarity in `[-1, 1]`.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0, na: Double = 0, nb: Double = 0
        for i in 0..<a.count {
            let ai = Double(a[i]), bi = Double(b[i])
            dot += ai * bi
            na += ai * ai
            nb += bi * bi
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }

    // MARK: - Helpers

    private func tokenize(_ s: String) -> [String] {
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = s
        var out: [String] = []
        tokenizer.enumerateTokens(in: s.startIndex..<s.endIndex) { range, _ in
            out.append(String(s[range]))
            return true
        }
        return out
        #else
        return s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        #endif
    }

    /// Deterministic bag-of-words hash → dense vector (sign-trick). Works anywhere.
    private func hashingEmbed(_ s: String) -> [Float] {
        var vec = [Float](repeating: 0, count: dimension)
        let tokens = s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        for t in tokens {
            let h = stableHash(t)
            let idx = Int(h % UInt64(dimension))
            let sign: Float = (h >> 32) & 1 == 0 ? 1 : -1
            vec[idx] += sign
        }
        // Normalize to unit length
        let norm = sqrt(vec.reduce(0) { $0 + Double($1 * $1) })
        if norm > 0 {
            for i in 0..<vec.count { vec[i] = Float(Double(vec[i]) / norm) }
        }
        return vec
    }

    private func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603 // FNV-1a offset
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return h
    }
}

public extension Embeddings {
    /// Pack `[Float]` into `Data` (little-endian).
    static func pack(_ vec: [Float]) -> Data {
        var v = vec
        return Data(bytes: &v, count: vec.count * MemoryLayout<Float>.size)
    }

    /// Unpack `Data` into `[Float]`.
    static func unpack(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw -> [Float] in
            let buf = raw.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: buf.baseAddress, count: count))
        }
    }
}
