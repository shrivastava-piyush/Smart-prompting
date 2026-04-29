import Foundation

/// High-level prompt assembly: resolves a user query into a fully-assembled prompt
/// by searching the store, building a dependency DAG, and rendering all fragments.
///
/// Usage modes:
/// - **Direct**: `assemble(slug:)` — resolve a known slug and its @{ref} tree
/// - **Query**: `assemble(query:)` — semantic search → pick top hit → assemble
/// - **Decompose**: `decompose(slug:)` — return the DAG structure for UI visualization
public final class AssemblyEngine: @unchecked Sendable {

    public enum Mode: String, Sendable, CaseIterable {
        case direct       // render prompt as-is with placeholder fill
        case assemble     // resolve @{ref} fragments into single buffer
        case decompose    // return DAG breakdown for step-by-step review
        case reprompt     // edit-and-re-render cycle
    }

    /// Result of decomposition — the DAG exposed for UI rendering.
    public struct Decomposition: Sendable {
        public let rootSlug: String
        public let nodes: [NodeInfo]
        public let edges: [(from: String, to: String)]
        public let executionOrder: [String]

        public struct NodeInfo: Sendable, Identifiable {
            public let id: String         // slug
            public let title: String
            public let bodyPreview: String // first 120 chars
            public let dependencyCount: Int
            public let hasPlaceholders: Bool
        }
    }

    private let store: PromptStore
    private let search: Search
    private let graph: GraphExecutor

    public init(store: PromptStore, search: Search) {
        self.store = store
        self.search = search
        self.graph = GraphExecutor(store: store, search: search)
    }

    // MARK: - Assembly by slug

    /// Resolve a prompt and all its @{ref} dependencies into a single text buffer.
    public func assemble(
        slug: String,
        values: [String: String] = [:]
    ) throws -> GraphExecutor.ExecutionResult {
        try graph.execute(rootSlug: slug, userValues: values)
    }

    // MARK: - Assembly by query

    /// Semantic search for the best match, then assemble it.
    public func assemble(
        query: String,
        values: [String: String] = [:]
    ) throws -> GraphExecutor.ExecutionResult {
        let hits = try search.query(query, limit: 1)
        guard let top = hits.first else {
            throw SmartPromptingError.promptNotFound(query)
        }
        return try graph.execute(rootSlug: top.prompt.slug, userValues: values)
    }

    // MARK: - DAG decomposition (for UI)

    /// Return the full DAG structure without executing, for visualization.
    public func decompose(slug: String) throws -> Decomposition {
        let nodes = try graph.buildGraph(from: slug)
        let order = try graph.topologicalSort(nodes)

        var infos: [Decomposition.NodeInfo] = []
        var edges: [(String, String)] = []

        for (nodeSlug, node) in nodes {
            let info = Decomposition.NodeInfo(
                id: nodeSlug,
                title: node.prompt.title,
                bodyPreview: String(node.prompt.body.prefix(120)),
                dependencyCount: node.dependencies.count,
                hasPlaceholders: !TemplateEngine.userPlaceholders(in: node.prompt.body).isEmpty
            )
            infos.append(info)

            for dep in node.dependencies where nodes[dep] != nil {
                edges.append((dep, nodeSlug))
            }
        }

        return Decomposition(
            rootSlug: slug,
            nodes: infos,
            edges: edges,
            executionOrder: order
        )
    }

    // MARK: - Collect all placeholders across the DAG

    /// Walk the DAG and return every user placeholder that needs filling,
    /// tagged with which node it belongs to.
    public func allPlaceholders(for slug: String) throws -> [(node: String, placeholder: String)] {
        let nodes = try graph.buildGraph(from: slug)
        let order = try graph.topologicalSort(nodes)
        var result: [(String, String)] = []
        var seen = Set<String>()

        for nodeSlug in order {
            guard let node = nodes[nodeSlug] else { continue }
            for name in TemplateEngine.userPlaceholders(in: node.prompt.body) {
                if seen.insert(name).inserted {
                    result.append((nodeSlug, name))
                }
            }
        }
        return result
    }

    // MARK: - Suggest fragments for a partial reference

    /// When a user types `@{partial...}`, suggest matching prompts.
    public func suggestFragments(
        partialSlug: String,
        limit: Int = 5
    ) throws -> [ScoredPrompt] {
        let query = partialSlug.replacingOccurrences(of: "-", with: " ")
        return try search.query(query, limit: limit)
    }
}
