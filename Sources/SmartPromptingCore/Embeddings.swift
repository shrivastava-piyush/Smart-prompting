import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(CoreML)
import CoreML
#endif

/// Produces fixed-size sentence embeddings.
public final class Embeddings: @unchecked Sendable {
    public enum Backend: String, Sendable {
        case coreml
        case naturalLanguage
        case hashing
    }

    public static let shared = Embeddings()

    public let backend: Backend
    public let dimension: Int
    private let lock = NSLock()

    #if canImport(NaturalLanguage)
    private let nl: NLEmbedding?
    #endif

    private init() {
        #if canImport(NaturalLanguage)
        // Switch to wordEmbedding as it is significantly more stable than 
        // sentenceEmbedding (which is prone to EXC_BAD_ACCESS on iOS 17/18).
        if let emb = NLEmbedding.wordEmbedding(for: .english) {
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
        if trimmed.isEmpty { return [Float](repeating: 0, count: dimension) }

        #if canImport(NaturalLanguage)
        if backend == .naturalLanguage, let nl = nl {
            lock.lock()
            defer { lock.unlock() }

            // Average word vectors to create a sentence/block embedding.
            // This avoids the buggy internal sentence-level model.
            let tokens = tokenize(trimmed)
            var sum = [Double](repeating: 0, count: dimension)
            var count = 0
            
            for token in tokens {
                if let vec = nl.vector(for: token) {
                    for i in 0..<dimension {
                        sum[i] += vec[i]
                    }
                    count += 1
                }
            }
            
            if count > 0 {
                return sum.map { Float($0 / Double(count)) }
            }
        }
        #endif

        return hashingEmbed(trimmed)
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
        if count == 0 { return [] }
        return data.withUnsafeBytes { raw -> [Float] in
            guard let baseAddress = raw.baseAddress else { return [] }
            let buf = baseAddress.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: buf, count: count))
        }
    }
}
