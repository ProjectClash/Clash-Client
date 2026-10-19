import XCTest
@testable import AdBlockScriptKit

/// The parts of `$argument` that decide what a script sees.
final class ScriptArgumentTests: XCTestCase {
    func testSwitchDefaultsArriveAsBooleans() {
        XCTAssertEqual(ScriptArgumentValue("true", kind: "switch"), .boolean(true))
        XCTAssertEqual(ScriptArgumentValue("false", kind: "switch"), .boolean(false))
        XCTAssertEqual(ScriptArgumentValue("yes", kind: "toggle"), .boolean(true))
    }

    func testNumberDefaultsArriveAsNumbers() {
        XCTAssertEqual(ScriptArgumentValue("10", kind: "number"), .number(10))
        XCTAssertEqual(ScriptArgumentValue("2.5", kind: "number"), .number(2.5))
        XCTAssertEqual(ScriptArgumentValue("ten", kind: "number"), .text("ten"), "a bad number stays text rather than becoming NaN")
    }

    func testTextDefaultsStayTextEvenWhenTheyLookBoolean() {
        // A `select` whose options are "true"/"false" is still a choice of
        // strings: scripts compare it with `=== 'true'`.
        XCTAssertEqual(ScriptArgumentValue("true", kind: "select"), .text("true"))
        XCTAssertEqual(ScriptArgumentValue("true", kind: nil), .text("true"))
        XCTAssertEqual(ScriptArgumentValue("1", kind: "input"), .text("1"))
    }

    func testJSONShapeMatchesTheDeclaredType() {
        XCTAssertTrue(ScriptArgumentValue.boolean(false).jsonObject is Bool)
        XCTAssertTrue(ScriptArgumentValue.number(3).jsonObject is Double)
        XCTAssertTrue(ScriptArgumentValue.text("x").jsonObject is String)
    }

    func testModuleDialectDecidesThePlatform() {
        XCTAssertEqual(ScriptPlatform(moduleFormat: "loon"), .loon)
        XCTAssertEqual(ScriptPlatform(moduleFormat: "lpx"), .loon)
        XCTAssertEqual(ScriptPlatform(moduleFormat: "surge"), .surge)
        XCTAssertEqual(ScriptPlatform(moduleFormat: "sgmodule"), .surge)
        XCTAssertEqual(ScriptPlatform(moduleFormat: "stash"), .stash)
        XCTAssertEqual(ScriptPlatform(moduleFormat: "quantumultX"), .quantumultX)
        XCTAssertNil(ScriptPlatform(moduleFormat: "something else"))
    }

    func testLoonStringIsThreeFields() {
        // @nsnanocat/util splits `$loon` on spaces and reads positions 0..2.
        let identity = ScriptIdentity(platform: .loon)
        XCTAssertEqual(identity.loonString.split(separator: " ").count, 3)
        let mac = ScriptIdentity(platform: .loon, device: "Mac")
        XCTAssertEqual(mac.loonString.split(separator: " ").count, 2, "the Mac form has no system version")
    }
}
