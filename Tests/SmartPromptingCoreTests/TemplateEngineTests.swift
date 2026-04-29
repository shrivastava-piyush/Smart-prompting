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

    // MARK: - System variables

    func testSystemVariableAutoResolves() throws {
        let out = try TemplateEngine.render("id: {{uuid}}", with: [:])
        XCTAssertFalse(out.contains("{{uuid}}"))
        XCTAssertTrue(out.hasPrefix("id: "))
        XCTAssertTrue(out.count > 5)
    }

    func testTodaySystemVariable() throws {
        let out = try TemplateEngine.render("date: {{today}}", with: [:])
        XCTAssertFalse(out.contains("{{today}}"))
    }

    func testSystemVarsNotPrompted() {
        let body = "{{today}} and {{name}}"
        let user = TemplateEngine.userPlaceholders(in: body)
        XCTAssertEqual(user, ["name"])
        XCTAssertFalse(user.contains("today"))
    }

    func testMixedSystemAndUserVars() throws {
        let out = try TemplateEngine.render(
            "{{year}}-{{name}}",
            with: ["name": "test"]
        )
        XCTAssertFalse(out.contains("{{year}}"))
        XCTAssertTrue(out.contains("test"))
    }

    func testSystemVarCaseInsensitive() throws {
        let body = "{{TODAY}} and {{Year}}"
        let user = TemplateEngine.userPlaceholders(in: body)
        XCTAssertTrue(user.isEmpty)
    }
}
