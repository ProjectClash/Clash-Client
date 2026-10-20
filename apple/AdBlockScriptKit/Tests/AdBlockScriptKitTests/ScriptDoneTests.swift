import XCTest
@testable import AdBlockScriptKit

/// `$done` is where the four platforms disagree most, and where a mistake is
/// silent: a status read as a body, a mock ignored, an abort treated as a
/// no-op. These tests pin every spelling seen in published scripts.
final class ScriptDoneTests: XCTestCase {
    func testStatusSpellings() {
        for (raw, expected) in [("200", 200), ("HTTP/1.1 200 OK", 200), ("HTTP/1.1 204", 204),
                                ("HTTP/2 404 Not Found", 404), (" 418 ", 418)] {
            var payload = ScriptDonePayload()
            payload.status = raw
            XCTAssertEqual(ScriptDoneParsing.statusCode(payload), expected, raw)
        }
        for raw in ["", "OK", "HTTP/1.1", "HTTP/1.1 99", "999", "HTTP/1.1 200 OK extra"] {
            var payload = ScriptDonePayload()
            payload.status = raw
            if raw == "HTTP/1.1 200 OK extra" {
                XCTAssertEqual(ScriptDoneParsing.statusCode(payload), 200, "a reason phrase may contain spaces")
            } else {
                XCTAssertNil(ScriptDoneParsing.statusCode(payload), raw)
            }
        }
    }

    func testStatusPrefersStatusCode() {
        var payload = ScriptDonePayload()
        payload.status = "HTTP/1.1 500 Server Error"
        payload.statusCode = "404"
        XCTAssertEqual(ScriptDoneParsing.statusCode(payload), 404)
    }

    func testRequestPhaseChangedRequest() {
        let base = makeRequest()
        var payload = ScriptDonePayload()
        payload.url = "https://example.com/b"
        payload.headers = ScriptHeaders([(name: "X-Test", value: "1")])
        guard case .request(let next) = ScriptDoneParsing.requestOutcome(payload, base: base) else {
            return XCTFail("expected a changed request")
        }
        XCTAssertEqual(next.url, "https://example.com/b")
        XCTAssertEqual(next.headers.first("x-test"), "1")
        XCTAssertEqual(next.method, "GET", "a changed request keeps the method")
    }

    func testRequestPhaseMockIsAResponse() {
        let base = makeRequest()
        var payload = ScriptDonePayload()
        payload.nestedResponse = ScriptResponse(status: 200,
                                                headers: ScriptHeaders([(name: "Content-Type", value: "application/json")]),
                                                body: Data("{\"ok\":true}".utf8))
        guard case .response(let mock) = ScriptDoneParsing.requestOutcome(payload, base: base) else {
            return XCTFail("a nested response is a mock")
        }
        XCTAssertEqual(mock.status, 200)
        XCTAssertEqual(mock.body, Data("{\"ok\":true}".utf8))
    }

    func testRequestPhaseBareStatusIsAMock() {
        // Surge documents a request script answering with a status directly.
        let base = makeRequest()
        var payload = ScriptDonePayload()
        payload.status = "403"
        guard case .response(let mock) = ScriptDoneParsing.requestOutcome(payload, base: base) else {
            return XCTFail("a bare status is a mock")
        }
        XCTAssertEqual(mock.status, 403)
    }

    func testRequestPhaseStatusWithHeadersIsAlsoAMock() {
        let base = makeRequest()
        var payload = ScriptDonePayload()
        payload.status = "200"
        payload.headers = ScriptHeaders([(name: "Content-Type", value: "text/plain")])
        payload.text = "hello"
        payload.hasBody = true
        guard case .response(let mock) = ScriptDoneParsing.requestOutcome(payload, base: base) else {
            return XCTFail("status + headers + body is a mock response")
        }
        XCTAssertEqual(mock.body, Data("hello".utf8))
    }

    func testSilentDoneLeavesTrafficAlone() {
        XCTAssertEqual(ScriptDoneParsing.requestOutcome(ScriptDonePayload(), base: makeRequest()), .unchanged)
        XCTAssertEqual(ScriptDoneParsing.responseOutcome(ScriptDonePayload(), base: makeResponse()), .unchanged)
    }

    func testAbort() {
        var payload = ScriptDonePayload()
        payload.abort = true
        guard case .aborted = ScriptDoneParsing.requestOutcome(payload, base: makeRequest()) else {
            return XCTFail("abort is an abort")
        }
        // The response phase has the same contract, and for a while it did not
        // reach the transport: both phases now close the connection, so the
        // enum case has to be produced on either side.
        guard case .aborted = ScriptDoneParsing.responseOutcome(payload, base: makeResponse()) else {
            return XCTFail("abort is an abort in the response phase too")
        }
    }

    func testResponsePhaseKeepsUnmentionedFields() {
        let base = makeResponse(body: Data("original".utf8))
        var payload = ScriptDonePayload()
        payload.text = "changed"
        payload.hasBody = true
        guard case .response(let next) = ScriptDoneParsing.responseOutcome(payload, base: base) else {
            return XCTFail("expected a response")
        }
        XCTAssertEqual(next.status, 200)
        XCTAssertEqual(next.headers.first("Content-Type"), "application/json")
        XCTAssertEqual(next.body, Data("changed".utf8))
    }

    func testEmptyBodyIsABody() {
        // `body: ''` means "make it empty"; `body: null` means "unchanged".
        let base = makeResponse(body: Data("original".utf8))
        var payload = ScriptDonePayload()
        payload.text = ""
        payload.hasBody = true
        guard case .response(let next) = ScriptDoneParsing.responseOutcome(payload, base: base) else {
            return XCTFail("expected a response")
        }
        XCTAssertEqual(next.body, Data())
    }

    func testHeadersKeepTheirCase() {
        var headers = ScriptHeaders([(name: "Content-Type", value: "text/plain")])
        headers.set("content-type", "application/json")
        XCTAssertEqual(headers.fields.count, 1, "a case-insensitive set must not duplicate")
        XCTAssertEqual(headers.fields.first?.name, "Content-Type", "the original casing wins")
    }
}
