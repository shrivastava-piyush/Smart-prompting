import XCTest
@testable import SmartPromptingCore

final class MarkdownCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let p = Prompt(
            id: "abc",
            slug: "my-prompt",
            title: "My Prompt",
            body: "Hello {{name}}\nBody line 2",
            tags: ["work", "ai"],
            placeholders: ["name"],
            useCount: 3,
            lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let text = try MarkdownCodec.encode(p)
        XCTAssertTrue(text.hasPrefix("---\n"))
        XCTAssertTrue(text.contains("\n---\n"))

        let back = try MarkdownCodec.decode(text, slug: "my-prompt")
        XCTAssertEqual(back.id, p.id)
        XCTAssertEqual(back.title, p.title)
        XCTAssertEqual(back.body, p.body)
        XCTAssertEqual(back.tags, p.tags)
        XCTAssertEqual(back.placeholders, p.placeholders)
        XCTAssertEqual(back.useCount, p.useCount)
        XCTAssertEqual(back.lastUsed?.timeIntervalSince1970, 1_700_000_000)
    }

    func testMissingFrontmatterThrows() {
        XCTAssertThrowsError(try MarkdownCodec.decode("just text", slug: "x"))
    }
}
