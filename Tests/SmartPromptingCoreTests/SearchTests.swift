import XCTest
@testable import SmartPromptingCore

final class SearchTests: XCTestCase {
    var tmpDir: URL!
    var indexDir: URL!
    var sp: SmartPrompting!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sp-tests-\(UUID().uuidString)")
        indexDir = tmpDir.appendingPathComponent("index")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)

        sp = try SmartPrompting(promptsDir: tmpDir, indexDir: indexDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testAddAndFind() throws {
        let p = try sp.store.add(Prompt(slug: "", title: "Code Review", body: "Review this PR for correctness and perf."))
        XCTAssertFalse(p.slug.isEmpty)
        let hits = try sp.search.query("review pull request", limit: 5)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.prompt.slug, p.slug)
    }

    func testKeywordMatchRanksAbove() throws {
        _ = try sp.store.add(Prompt(slug: "", title: "Bread Recipe", body: "Mix flour, water, yeast."))
        _ = try sp.store.add(Prompt(slug: "", title: "Rust Refactor", body: "Refactor the rust function for clarity."))
        let hits = try sp.search.query("rust refactor", limit: 5)
        XCTAssertEqual(hits.first?.prompt.title, "Rust Refactor")
    }

    func testEmptyQueryReturnsRecents() throws {
        _ = try sp.store.add(Prompt(slug: "", title: "A", body: "a"))
        _ = try sp.store.add(Prompt(slug: "", title: "B", body: "b"))
        let hits = try sp.search.query("", limit: 5)
        XCTAssertEqual(hits.count, 2)
    }

    func testDeleteRemovesFromSearch() throws {
        let p = try sp.store.add(Prompt(slug: "", title: "Gone", body: "ephemeral text unique-token-xyz"))
        try sp.store.delete(slug: p.slug)
        let hits = try sp.search.query("unique-token-xyz", limit: 5)
        XCTAssertTrue(hits.isEmpty)
    }

    func testUseIncrementsCounter() throws {
        var p = try sp.store.add(Prompt(slug: "", title: "X", body: "body"))
        try sp.store.recordUse(p)
        p = try XCTUnwrap(sp.store.get(slug: p.slug))
        XCTAssertEqual(p.useCount, 1)
        XCTAssertNotNil(p.lastUsed)
    }

    func testRebuildIndexFromDisk() throws {
        let p = try sp.store.add(Prompt(slug: "", title: "Persisted", body: "some body"))
        // Build a fresh PromptStore pointing at the same directory; the index
        // should be rebuilt from the markdown files.
        let fresh = try SmartPrompting(
            promptsDir: tmpDir,
            indexDir: tmpDir.appendingPathComponent("fresh-index")
        )
        try fresh.store.syncIndexFromDisk()
        let found = try fresh.store.get(slug: p.slug)
        XCTAssertEqual(found?.title, "Persisted")
    }
}
