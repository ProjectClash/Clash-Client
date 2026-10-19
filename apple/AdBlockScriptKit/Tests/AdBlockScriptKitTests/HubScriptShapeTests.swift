import XCTest
@testable import AdBlockScriptKit

/// The engine against the shapes the hub's scripts are written in.
///
/// Every case here is a line taken from a script the hub publishes, reduced to
/// what it exercises. They are written out rather than vendored because the
/// scripts belong to their authors; what matters is the shape, and the shape is
/// what a runtime has to survive.
final class HubScriptShapeTests: XCTestCase {
    private func run(_ script: String, platform: ScriptPlatform = .loon,
                     phase: ScriptPhase = .request,
                     binaryBody: Bool = false,
                     argument: ScriptArgument = .none,
                     request: ScriptRequest? = nil,
                     response: ScriptResponse? = nil,
                     then check: @escaping @Sendable (ScriptOutcome) -> Void) {
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: 4, grace: 0.3),
                                  services: FakeServices(), makeEngine: { _, _ in try JSCEngine() })
        let done = expectation(description: "outcome")
        runner.run(script: ScriptSource(name: "shape", key: "shape", text: script,
                                        argument: argument, binaryBody: binaryBody),
                   request: request ?? makeRequest(), response: response,
                   identity: ScriptIdentity(platform: platform)) { outcome in
            check(outcome)
            done.fulfill()
        }
        wait(for: [done], timeout: 9)
    }

    /// `new URL($request.url).pathname` — the most common line in the corpus.
    /// JavaScriptCore has no `URL`, so this used to throw in 54 of the runs.
    func testURLIsAvailable() {
        run("""
        const parsed = new URL($request.url);
        $done({ response: { status: 200, body: parsed.hostname + '|' + parsed.pathname + '|' + parsed.searchParams.get('q') } });
        """, request: ScriptRequest(id: "r", method: "GET",
                                   url: "https://api.example.com:8443/v1/list?q=1&r=2",
                                   headers: ScriptHeaders(), body: nil)) { outcome in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(String(decoding: mock.body ?? Data(), as: UTF8.self),
                           "api.example.com|/v1/list|1")
        }
    }

    /// A relative URL resolves against the in-flight request, which is what a
    /// script means by one.
    func testURLResolvesRelativeReferences() {
        run("""
        $done({ response: { status: 200, body: new URL('../other', $request.url).href } });
        """, request: ScriptRequest(id: "r", method: "GET",
                                   url: "https://example.com/a/b/c",
                                   headers: ScriptHeaders(), body: nil)) { outcome in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(String(decoding: mock.body ?? Data(), as: UTF8.self),
                           "https://example.com/a/other")
        }
    }

    /// `TextEncoder` and `atob` are ECMAScript-adjacent globals the engine does
    /// not ship either, and scripts hash and decode with them.
    func testTextAndBase64GlobalsAreAvailable() {
        run("""
        const bytes = new TextEncoder().encode('héllo');
        const round = new TextDecoder().decode(bytes);
        const b64 = btoa(round);
        $done({ response: { status: 200, body: bytes.length + '|' + round + '|' + atob(b64) } });
        """) { outcome in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(String(decoding: mock.body ?? Data(), as: UTF8.self), "6|héllo|héllo")
        }
    }

    /// The hub has scripts that answer with a status *line* rather than a
    /// number — `$done({status: "HTTP/1.1 404 Not Found"})`.
    func testStatusLineStringIsUnderstood() {
        run("""
        $done({ status: 'HTTP/1.1 404 Not Found', body: 'no' });
        """, phase: .response, response: makeResponse()) { outcome in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(mock.status, 404, "a status line must be read as its code")
        }
    }

    /// `bodyBytes` in binary mode: eleven of the hub's sixteen binary scripts
    /// read it, and a runtime that only fills `body` leaves them with nothing.
    func testBinaryBodyFillsBodyBytes() {
        run("""
        if (!($response.bodyBytes instanceof Uint8Array)) { throw new Error('bodyBytes is ' + typeof $response.bodyBytes); }
        if ($response.bodyBytes.length !== 5) { throw new Error('wrong length: ' + $response.bodyBytes.length); }
        $done({ bodyBytes: $response.bodyBytes });
        """, phase: .response, binaryBody: true,
            response: ScriptResponse(status: 200, headers: ScriptHeaders(),
                                     body: Data([1, 2, 3, 4, 5]))) { outcome in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(next.body, Data([1, 2, 3, 4, 5]),
                           "the bytes the script wrote back must survive the round trip")
        }
    }

    /// The string form of `$argument`, which scripts split immediately.
    func testStringArgumentSplits() {
        run("""
        const arg = Object.fromEntries($argument.split('&').map((item) => item.split('=')));
        $done({ response: { status: 200, body: arg.region + '/' + arg.level } });
        """, argument: .text("region=CN&level=2")) { outcome in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(String(decoding: mock.body ?? Data(), as: UTF8.self), "CN/2")
        }
    }

    /// `$done` with nothing at all, which the hub's small removers end with
    /// after mutating the body in place.
    func testInPlaceBodyRewrite() {
        run("""
        const obj = JSON.parse($response.body);
        delete obj.data.banner;
        $done({ body: JSON.stringify(obj) });
        """, phase: .response,
            response: ScriptResponse(status: 200, headers: ScriptHeaders(),
                                     body: Data(#"{"code":0,"data":{"banner":{"a":1},"list":[1]}}"#.utf8))) { outcome in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            let body = String(decoding: next.body ?? Data(), as: UTF8.self)
            XCTAssertFalse(body.contains("banner"), "the removed key must be gone: \(body)")
            XCTAssertTrue(body.contains("list"), "everything else must survive: \(body)")
        }
    }
}
