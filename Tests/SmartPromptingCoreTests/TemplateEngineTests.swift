import XCTest
@testable import SmartPromptingCore

final class TemplateEngineTests: XCTestCase {
    func testPlaceholdersFirstSeenOrderUnique() {
        let body = "Hi {{name}}, meet {{friend}} — regards, {{name}}."
        XCTAssertEqual(TemplateEngine.placeholders(in: body), ["name", "friend"])
    }

    func testRenderSubstitutes() throws {
        let out = try TemplateEngine.render(
            "Review {{repo}} for {{goal}}.",
            with: ["repo": "my/proj", "goal": "perf"]
        )
        XCTAssertEqual(out, "Review my/proj for perf.")
    }

    func testRenderMissingPlaceholderThrows() {
        XCTAssertThrowsError(try TemplateEngine.render("{{x}}", with: [:])) { err in
            guard case SmartPromptingError.missingPlaceholder(let name) = err else {
                return XCTFail("wrong error")
            }
            XCTAssertEqual(name, "x")
        }
    }

    func testRenderNoPlaceholdersPassThrough() throws {
        XCTAssertEqual(try TemplateEngine.render("hello", with: [:]), "hello")
    }

    func testWhitespaceAroundNames() throws {
        let out = try TemplateEngine.render("{{ name }}", with: ["name": "Ada"])
        XCTAssertEqual(out, "Ada")
    }
}
