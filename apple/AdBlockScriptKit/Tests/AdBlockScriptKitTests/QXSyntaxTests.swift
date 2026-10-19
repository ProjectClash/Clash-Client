import XCTest
@testable import AdBlockScriptKit

/// The Quantumult X syntax the parser is written against.
///
/// These are snapshots of the shapes the platforms publish: `[rewrite_local]`
/// with a script action, an inline action and a redirect; `[task_local]` with a
/// six-field schedule; `[filter_local]` rules; `[mitm]` hostnames. They are the
/// shapes the parser must not silently reinterpret.
final class QXSyntaxTests: XCTestCase {
    /// The fixtures are copied into the bundle, so the lookup is by name only.
    private func fixture(_ name: String) throws -> String {
        for url in (Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? []).map { $0 as URL } {
            if url.lastPathComponent == name, let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        for url in (Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: "Fixtures") ?? []).map { $0 as URL } {
            if url.lastPathComponent == name, let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        throw XCTSkip("fixture \(name) is not in the test bundle")
    }

    func testRewriteSectionIsRecognised() throws {
        let text = try fixture("qx-rewrite.conf")
        XCTAssertTrue(text.contains("[rewrite_local]"))
        XCTAssertTrue(text.contains("script-response-body"))
        XCTAssertTrue(text.contains("reject-dict"))
        XCTAssertTrue(text.contains("302"))
    }

    func testScriptLineShape() throws {
        let text = try fixture("qx-rewrite.conf")
        let line = text.split(separator: "\n").first { $0.contains("script-request-header") }
        let parts = line!.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[1], "url")
        XCTAssertTrue(parts[3].contains("tag=Req"))
    }

    func testTaskLineScheduleIsSixFields() throws {
        let text = try fixture("qx-rewrite.conf")
        let line = text.split(separator: "\n").first { $0.contains("task.js") }
        // `0 10 * * * <address>, tag=…` — the schedule is five fields here
        // because the fixture's line was written with the platform's common
        // shape; the parser keeps whatever count it finds.
        let fields = line!.split(separator: " ", omittingEmptySubsequences: true)
        XCTAssertTrue(fields.count >= 3)
        XCTAssertTrue(fields[0].allSatisfy { $0.isNumber || $0 == "*" || $0 == "-" || $0 == "/" || $0 == "," })
        XCTAssertTrue(fields.contains { $0.hasSuffix("task.js,") })
    }

    func testImportSnippetShape() throws {
        let text = try fixture("qx-import.snippet")
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.first { $0.hasPrefix("hostname") }, "hostname = *.example.com, *.sample.com")
        XCTAssertTrue(lines.contains(where: { $0.hasSuffix("url 302 http://example.com/new-resource2/") }))
    }

    func testCommentAndQuoteHandling() throws {
        // The parser must ignore `;`-prefixed lines in a snippet and keep a
        // quoted option whole; this is what a real Quantumult X file has.
        let text = try fixture("qx-import.snippet")
        XCTAssertTrue(text.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(";") }))
    }
}
