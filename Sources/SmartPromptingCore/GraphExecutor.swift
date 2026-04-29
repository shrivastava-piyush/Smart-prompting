import Foundation

/// Directed Acyclic Graph executor for prompt assembly.
///
/// Nodes are prompt slugs. Edges are `@{slug}` references found in prompt bodies.
/// The executor performs topological sort, detects cycles, and resolves nodes
/// in dependency order so downstream fragments see upstream results.
public final class GraphExecutor: @unchecked Sendable {

    /// A single node in the prompt DAG.
    public struct Node: Sendable, Identifiable {
        public let id: String          // slug
        public let prompt: Prompt
        public var dependencies: [String]  // slugs this node references
        public var resolved: String?       // body after assembly

        public init(prompt: Prompt, dependencies: [String]) {
            self.id = prompt.slug
            self.prompt = prompt
            self.dependencies = dependencies
            self.resolved = nil
        }
    }

    /// Complete execution result.
    public struct ExecutionResult: Sendable {
        public let root: String                // root slug
        public let assembledText: String       // final rendered output
        public let executionOrder: [String]    // topological order (leaves first)
        public let nodeCount: Int
        public let resolvedFragments: [String: String]  // slug → resolved text
    }

    public enum GraphError: Error, LocalizedError {
        case cycleDetected([String])
        case unresolvedReference(String, in: String)
        case maxDepthExceeded(Int)

        public var errorDescription: String? {
            switch self {
            case .cycleDetected(let cycle):
                return "Dependency cycle: \(cycle.joined(separator: " → "))"
            case .unresolvedReference(let ref, let parent):
                return "Unresolved reference @{\(ref)} in \(parent)"
            case .maxDepthExceeded(let depth):
                return "Maximum dependency depth (\(depth)) exceeded"
            }
        }
    }

    private let store: PromptStore
    private let search: Search
    private let maxDepth: Int

    public init(store: PromptStore, search: Search, maxDepth: Int = 16) {
        self.store = store
        self.search = search
        self.maxDepth = maxDepth
    }

    // MARK: - Reference parsing

    /// Pattern: `@{some-slug}` — distinct from `{{placeholder}}`.
    private static let refPattern = #"@\{\s*([a-zA-Z][a-zA-Z0-9_-]*)\s*\}"#

    /// Extract all `@{slug}` references from a body string.
    public static func references(in body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: refPattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var seen = Set<String>()
        var ordered: [String] = []
        regex.enumerateMatches(in: body, range: range) { match, _, _ in
            guard let match = match,
                  match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: body) else { return }
            let slug = String(body[r])
            if seen.insert(slug).inserted {
                ordered.append(slug)
            }
        }
        return ordered
    }

    // MARK: - DAG construction

    /// Build the full dependency graph starting from a root prompt.
    /// Uses BFS to discover all reachable nodes.
    public func buildGraph(from rootSlug: String) throws -> [String: Node] {
        var nodes: [String: Node] = [:]
        var queue: [String] = [rootSlug]
        var depth: [String: Int] = [rootSlug: 0]

        while !queue.isEmpty {
            let slug = queue.removeFirst()
            if nodes[slug] != nil { continue }

            guard let prompt = try resolveSlug(slug) else {
                throw GraphError.unresolvedReference(slug, in: "root")
            }

            let d = depth[slug] ?? 0
            if d > maxDepth {
                throw GraphError.maxDepthExceeded(maxDepth)
            }

            let bodyRefs = Self.references(in: prompt.body)
            let frontmatterRefs = prompt.requires
            let allRefs = Array(Set(bodyRefs + frontmatterRefs))

            let node = Node(prompt: prompt, dependencies: allRefs)
            nodes[slug] = node

            for ref in allRefs where nodes[ref] == nil {
                depth[ref] = d + 1
                queue.append(ref)
            }
        }

        return nodes
    }

    // MARK: - Topological sort + cycle detection

    /// Kahn's algorithm. Returns slugs in execution order (leaves first).
    /// Throws `cycleDetected` if the graph has cycles.
    public func topologicalSort(_ nodes: [String: Node]) throws -> [String] {
        var inDegree: [String: Int] = [:]
        var adjacency: [String: [String]] = [:]

        for (slug, _) in nodes {
            inDegree[slug] = 0
            adjacency[slug] = []
        }
        for (slug, node) in nodes {
            for dep in node.dependencies where nodes[dep] != nil {
                adjacency[dep, default: []].append(slug)
                inDegree[slug, default: 0] += 1
            }
        }

        var queue: [String] = inDegree.filter { $0.value == 0 }.map(\.key).sorted()
        var order: [String] = []

        while !queue.isEmpty {
            let slug = queue.removeFirst()
            order.append(slug)
            for dependent in (adjacency[slug] ?? []) {
                inDegree[dependent, default: 0] -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                }
            }
        }

        if order.count != nodes.count {
            let cycleNodes = Set(nodes.keys).subtracting(order)
            throw GraphError.cycleDetected(Array(cycleNodes))
        }

        return order
    }

    // MARK: - Execute

    /// Build DAG, sort, resolve all fragments, return assembled text.
    public func execute(
        rootSlug: String,
        userValues: [String: String] = [:]
    ) throws -> ExecutionResult {
        var nodes = try buildGraph(from: rootSlug)
        let order = try topologicalSort(nodes)

        var resolved: [String: String] = [:]

        for slug in order {
            guard let node = nodes[slug] else { continue }
            var body = node.prompt.body

            // Substitute @{ref} with resolved fragment text
            body = Self.substituteReferences(in: body, resolved: resolved)

            resolved[slug] = body
            nodes[slug]?.resolved = body
        }

        guard let rootBody = resolved[rootSlug] else {
            throw GraphError.unresolvedReference(rootSlug, in: "execution")
        }

        // Final pass: render {{placeholder}} variables via TemplateEngine
        let rendered = try TemplateEngine.render(rootBody, with: userValues)

        return ExecutionResult(
            root: rootSlug,
            assembledText: rendered,
            executionOrder: order,
            nodeCount: nodes.count,
            resolvedFragments: resolved
        )
    }

    /// Substitute all `@{slug}` in a body with the resolved text for that slug.
    private static func substituteReferences(
        in body: String,
        resolved: [String: String]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: refPattern) else { return body }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = ""
        var cursor = 0

        regex.enumerateMatches(in: body, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let whole = match.range(at: 0)
            let nameRange = match.range(at: 1)
            let slug = ns.substring(with: nameRange)

            result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            result += resolved[slug] ?? "@{\(slug)}"
            cursor = whole.location + whole.length
        }

        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }

    // MARK: - Slug resolution with vector fallback

    /// Try exact slug match first; if not found, use semantic search
    /// to find the closest prompt (score > 0.5 threshold).
    private func resolveSlug(_ slug: String) throws -> Prompt? {
        if let exact = try store.get(slug: slug) {
            return exact
        }
        // Vector fallback: treat slug as a search query (hyphens → spaces)
        let query = slug.replacingOccurrences(of: "-", with: " ")
        let hits = try search.query(query, limit: 1)
        guard let top = hits.first, top.score > 0.5 else { return nil }
        return top.prompt
    }
}
