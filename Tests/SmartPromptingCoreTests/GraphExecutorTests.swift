import XCTest
@testable import SmartPromptingCore

final class GraphExecutorTests: XCTestCase {
    var tmpDir: URL!
    var indexDir: URL!
    var sp: SmartPrompting!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sp-graph-\(UUID().uuidString)")
        indexDir = tmpDir.appendingPathComponent("index")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        sp = try SmartPrompting(promptsDir: tmpDir, indexDir: indexDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Reference parsing

    func testReferencesExtracted() {
        let body = "Use @{checklist} and then apply @{perf-rules} to the code."
        let refs = GraphExecutor.references(in: body)
        XCTAssertEqual(refs, ["checklist", "perf-rules"])
    }

    func testReferencesDeduped() {
        let body = "@{a} then @{b} then @{a} again"
        XCTAssertEqual(GraphExecutor.references(in: body), ["a", "b"])
    }

    func testReferencesDoNotMatchPlaceholders() {
        let body = "{{placeholder}} and @{fragment}"
        let refs = GraphExecutor.references(in: body)
        XCTAssertEqual(refs, ["fragment"])
        XCTAssertFalse(refs.contains("placeholder"))
    }

    func testEmptyBodyNoReferences() {
        XCTAssertEqual(GraphExecutor.references(in: ""), [])
    }

    // MARK: - DAG building and execution

    func testSingleNodeGraph() throws {
        _ = try sp.store.add(Prompt(slug: "solo", title: "Solo", body: "Just a prompt."))
        let result = try sp.assembly.assemble(slug: "solo")
        XCTAssertEqual(result.assembledText, "Just a prompt.")
        XCTAssertEqual(result.nodeCount, 1)
        XCTAssertEqual(result.executionOrder, ["solo"])
    }

    func testTwoNodeAssembly() throws {
        _ = try sp.store.add(Prompt(slug: "fragment", title: "Fragment", body: "check correctness"))
        _ = try sp.store.add(Prompt(slug: "root", title: "Root", body: "Review: @{fragment}. Done."))

        let result = try sp.assembly.assemble(slug: "root")
        XCTAssertEqual(result.assembledText, "Review: check correctness. Done.")
        XCTAssertEqual(result.nodeCount, 2)
        XCTAssertEqual(result.executionOrder.first, "fragment")
        XCTAssertEqual(result.executionOrder.last, "root")
    }

    func testThreeNodeChain() throws {
        _ = try sp.store.add(Prompt(slug: "leaf", title: "Leaf", body: "leaf-value"))
        _ = try sp.store.add(Prompt(slug: "mid", title: "Mid", body: "mid(@{leaf})"))
        _ = try sp.store.add(Prompt(slug: "top", title: "Top", body: "top(@{mid})"))

        let result = try sp.assembly.assemble(slug: "top")
        XCTAssertEqual(result.assembledText, "top(mid(leaf-value))")
        XCTAssertEqual(result.nodeCount, 3)
    }

    func testDiamondDAG() throws {
        _ = try sp.store.add(Prompt(slug: "base", title: "Base", body: "BASE"))
        _ = try sp.store.add(Prompt(slug: "left", title: "Left", body: "L-@{base}"))
        _ = try sp.store.add(Prompt(slug: "right", title: "Right", body: "R-@{base}"))
        _ = try sp.store.add(Prompt(slug: "top", title: "Top", body: "@{left} + @{right}"))

        let result = try sp.assembly.assemble(slug: "top")
        XCTAssertEqual(result.assembledText, "L-BASE + R-BASE")
        XCTAssertEqual(result.nodeCount, 4)
    }

    // MARK: - Placeholders + assembly combined

    func testAssemblyWithPlaceholders() throws {
        _ = try sp.store.add(Prompt(slug: "frag", title: "Frag", body: "check {{focus}}"))
        _ = try sp.store.add(Prompt(slug: "main", title: "Main", body: "Review @{frag} in {{repo}}."))

        let result = try sp.assembly.assemble(slug: "main", values: ["focus": "perf", "repo": "my/proj"])
        XCTAssertEqual(result.assembledText, "Review check perf in my/proj.")
    }

    func testAllPlaceholdersAcrossDAG() throws {
        _ = try sp.store.add(Prompt(slug: "child", title: "Child", body: "{{x}} and {{y}}"))
        _ = try sp.store.add(Prompt(slug: "parent", title: "Parent", body: "@{child} plus {{z}}"))

        let phs = try sp.assembly.allPlaceholders(for: "parent")
        let names = phs.map(\.placeholder)
        XCTAssertTrue(names.contains("x"))
        XCTAssertTrue(names.contains("y"))
        XCTAssertTrue(names.contains("z"))
    }

    // MARK: - Cycle detection

    func testCycleThrows() throws {
        _ = try sp.store.add(Prompt(slug: "a", title: "A", body: "see @{b}"))
        _ = try sp.store.add(Prompt(slug: "b", title: "B", body: "see @{a}"))

        XCTAssertThrowsError(try sp.assembly.assemble(slug: "a")) { error in
            guard case GraphExecutor.GraphError.cycleDetected = error else {
                return XCTFail("Expected cycleDetected, got \(error)")
            }
        }
    }

    func testSelfReferenceThrows() throws {
        _ = try sp.store.add(Prompt(slug: "self-ref", title: "Self", body: "loop @{self-ref}"))

        XCTAssertThrowsError(try sp.assembly.assemble(slug: "self-ref")) { error in
            guard case GraphExecutor.GraphError.cycleDetected = error else {
                return XCTFail("Expected cycleDetected, got \(error)")
            }
        }
    }

    // MARK: - Decomposition

    func testDecompose() throws {
        _ = try sp.store.add(Prompt(slug: "dep", title: "Dep", body: "dep body"))
        _ = try sp.store.add(Prompt(slug: "root-d", title: "Root", body: "using @{dep}"))

        let d = try sp.assembly.decompose(slug: "root-d")
        XCTAssertEqual(d.rootSlug, "root-d")
        XCTAssertEqual(d.nodes.count, 2)
        XCTAssertEqual(d.edges.count, 1)
        XCTAssertEqual(d.executionOrder.first, "dep")
    }

    // MARK: - Frontmatter requires

    func testFrontmatterRequiresResolves() throws {
        _ = try sp.store.add(Prompt(slug: "prereq", title: "Prereq", body: "prereq content"))
        _ = try sp.store.add(Prompt(
            slug: "with-req", title: "WithReq",
            body: "main body referencing @{prereq}",
            requires: ["prereq"]
        ))

        let result = try sp.assembly.assemble(slug: "with-req")
        XCTAssertEqual(result.assembledText, "main body referencing prereq content")
    }
}
