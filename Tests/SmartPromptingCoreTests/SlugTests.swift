import XCTest
@testable import SmartPromptingCore

final class SlugTests: XCTestCase {
    func testBasic() {
        XCTAssertEqual(Slug.make(from: "Hello, World!"), "hello-world")
    }

    func testDiacritics() {
        XCTAssertEqual(Slug.make(from: "Café Münchner"), "cafe-munchner")
    }

    func testCollapsesMultipleSeparators() {
        XCTAssertEqual(Slug.make(from: "foo -- bar/baz"), "foo-bar-baz")
    }

    func testEmpty() {
        XCTAssertEqual(Slug.make(from: "  "), "prompt")
    }

    func testTruncation() {
        let out = Slug.make(from: String(repeating: "a", count: 80))
        XCTAssertLessThanOrEqual(out.count, 60)
    }
}
