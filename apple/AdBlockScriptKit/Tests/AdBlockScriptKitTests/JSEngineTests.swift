import XCTest
@testable import AdBlockScriptKit

/// The real engine, running the real prelude.
///
/// These are the tests that would catch a prelude that cannot be evaluated, a
/// platform global installed under the wrong name, or a `$done` that never
/// reaches the host — none of which a stub can show.
final class JSEngineTests: XCTestCase {
    private func run(_ script: String, platform: ScriptPlatform = .loon, phase: ScriptPhase = .request,
                     binaryBody: Bool = false,
                     request: ScriptRequest = makeRequest(),
                     response: ScriptResponse? = nil,
                     argument: [String: ScriptArgumentValue] = [:],
                     services: FakeServices = FakeServices(),
                     timeout: TimeInterval = 3,
                     file: StaticString = #filePath, line: UInt = #line,
                     then check: @escaping @Sendable (ScriptOutcome, FakeServices) -> Void) {
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: timeout, grace: 0.2),
                                  services: services, makeEngine: { _, _ in try JSCEngine() })
        let done = expectation(description: "outcome")
        runner.run(script: ScriptSource(name: "test", key: "test", text: script, argument: argument,
                                        binaryBody: binaryBody),
                   request: request, response: response,
                   identity: ScriptIdentity(platform: platform)) { outcome in
            check(outcome, services)
            done.fulfill()
        }
        wait(for: [done], timeout: timeout + 3)
    }

    func testPreludeEvaluatesAndDoneIsHonoured() {
        run("$done({});") { outcome, _ in
            XCTAssertEqual(outcome, .unchanged, "an empty $done leaves the request alone")
        }
    }

    func testRequestChange() {
        run("""
        const headers = Object.assign({}, $request.headers);
        headers['X-Added'] = 'yes';
        $done({ url: $request.url + '?x=1', headers: headers });
        """) { outcome, _ in
            guard case .request(let next) = outcome else { return XCTFail("expected a changed request, got \(outcome)") }
            XCTAssertEqual(next.url, "https://example.com/a?x=1")
            XCTAssertEqual(next.headers.first("X-Added"), "yes")
            XCTAssertEqual(next.headers.first("Accept"), "*/*", "the original headers survive a copy")
        }
    }

    func testMockResponse() {
        run("""
        $done({ response: { status: 200, headers: { 'Content-Type': 'application/json' }, body: '{"ok":true}' } });
        """) { outcome, _ in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(mock.status, 200)
            XCTAssertEqual(mock.body, Data("{\"ok\":true}".utf8))
        }
    }

    func testQuantumultXMockUsesStatusLineAndBodyBytes() {
        run("""
        $done({ status: 'HTTP/1.1 200 OK', body: JSON.stringify({ ok: 1 }) });
        """, platform: .quantumultX) { outcome, _ in
            guard case .response(let mock) = outcome else { return XCTFail("expected a mock, got \(outcome)") }
            XCTAssertEqual(mock.status, 200)
            XCTAssertEqual(mock.body, Data("{\"ok\":1}".utf8))
        }
    }

    func testResponseBodyIsEditableAsText() {
        run("""
        const body = JSON.parse($response.body);
        body.ads = [];
        $done({ body: JSON.stringify(body) });
        """, phase: .response,
            response: ScriptResponse(status: 200, headers: ScriptHeaders(),
                                     body: Data("{\"ads\":[1,2],\"keep\":true}".utf8))) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "{\"ads\":[],\"keep\":true}")
        }
    }

    func testBinaryBodyRoundTrip() {
        // A body that is not valid UTF-8 must survive a binary-mode round trip
        // byte for byte; this is the Protobuf case.
        let bytes = Data([0x08, 0x96, 0x01, 0x12, 0xff, 0x00, 0x80])
        run("""
        const input = $response.body;
        if (!(input instanceof Uint8Array)) { throw new Error('body is not a Uint8Array: ' + Object.prototype.toString.call(input)); }
        const out = new Uint8Array(input.length);
        for (let i = 0; i < input.length; i++) { out[i] = input[i]; }
        $done({ body: out });
        """, phase: .response, binaryBody: true,
            response: ScriptResponse(status: 200, headers: ScriptHeaders(), body: bytes)) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(next.body, bytes)
        }
    }

    func testBinaryBodyWithoutTheFlagIsNotBytes() {
        // Without `binary-body-mode` the same body is text, as on the real hosts.
        run("""
        if ($response.body instanceof Uint8Array) { throw new Error('text mode handed out bytes'); }
        $done({});
        """, phase: .response, response: ScriptResponse(status: 200, headers: ScriptHeaders(), body: Data("plain".utf8))) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    func testEnvironmentIdentityIsLoonAndNotEmpty() {
        run("""
        if (typeof $loon === 'undefined') { throw new Error('no $loon'); }
        if (typeof $task !== 'undefined') { throw new Error('Loon must not define $task'); }
        if (typeof $environment !== 'undefined' && $environment['surge-version']) { throw new Error('Loon must not look like Surge'); }
        if (typeof module !== 'undefined') { throw new Error('module must not exist'); }
        $done({ body: $loon });
        """, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "iPhone15,2 18.0 3.2.0(1000)")
        }
    }

    func testEnvironmentIdentityIsSurge() {
        run("""
        if (typeof $environment === 'undefined') { throw new Error('no $environment'); }
        if (!$environment['surge-version']) { throw new Error('no surge-version'); }
        if (typeof $httpClient === 'undefined') { throw new Error('no $httpClient'); }
        $done({ body: $environment['surge-version'] });
        """, platform: .surge, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "3.2.0(1000)")
        }
    }

    func testEnvironmentIdentityIsQuantumultX() {
        run("""
        if (typeof $task === 'undefined') { throw new Error('no $task'); }
        if (typeof $loon !== 'undefined') { throw new Error('QX must not define $loon'); }
        if (typeof $prefs === 'undefined') { throw new Error('no $prefs'); }
        $prefs.setValueForKey('v', 'k');
        $done({ body: String($prefs.valueForKey('k')) });
        """, platform: .quantumultX, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "v")
        }
    }

    func testArgumentObjectCarriesTypes() {
        run("""
        if ($argument.per_filter_video_thread !== false) { throw new Error('switch default did not arrive as a boolean'); }
        if ($argument.name !== 'x') { throw new Error('text default did not arrive as text'); }
        $done({});
        """, argument: ["per_filter_video_thread": .boolean(false), "name": .text("x")]) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    func testEnvironmentProbeMatchesEnvJsOrder() {
        // The exact probe from chavyleung/scripts Env.js, run verbatim.
        let probe = """
        function getEnv() {
          if ('undefined' !== typeof $environment && $environment['surge-version']) return 'Surge';
          if ('undefined' !== typeof $environment && $environment['stash-version']) return 'Stash';
          if ('undefined' !== typeof module && !!module.exports) return 'Node.js';
          if ('undefined' !== typeof $task) return 'Quantumult X';
          if ('undefined' !== typeof $loon) return 'Loon';
          if ('undefined' !== typeof $rocket) return 'Shadowrocket';
          return undefined;
        }
        """
        run(probe + "$done({ body: String(getEnv()) });", phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "Loon")
        }
        run(probe + "$done({ body: String(getEnv()) });", platform: .quantumultX, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "Quantumult X")
        }
    }

    func testStorageRoundTripAndDelete() {
        run("""
        $persistentStore.write('1', 'counter');
        if ($persistentStore.read('counter') !== '1') { throw new Error('read did not see the write'); }
        $persistentStore.write(null, 'counter');
        if ($persistentStore.read('counter') !== null) { throw new Error('a null write does not delete'); }
        $done({});
        """) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    func testNotificationIsForwarded() {
        let services = FakeServices()
        run("$notification.post('title', 'sub', 'body', { openUrl: 'https://example.com' }); $done({});",
            services: services) { _, services in
            XCTAssertEqual(services.notified.first?.title, "title")
            XCTAssertEqual(services.notified.first?.openURL, "https://example.com")
        }
    }

    func testHTTPClientCallback() {
        let services = FakeServices()
        services.httpAnswer = .json(["status": 201, "headers": ["X-A": "1"], "body": "hi"])
        run("""
        $httpClient.get({ url: 'https://example.com/x' }, function (error, response, data) {
          if (error) { throw new Error(error); }
          $done({ body: response.status + ':' + data });
        });
        """, phase: .response, response: makeResponse(), services: services) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "201:hi")
        }
    }

    func testTaskFetchPromise() {
        let services = FakeServices()
        services.httpAnswer = .json(["status": 200, "headers": [:], "body": "{\"a\":1}"])
        run("""
        $task.fetch('https://example.com/y').then(function (response) {
          $done({ body: String(response.status) + ':' + response.body });
        }, function (error) {
          $done({ body: 'failed' });
        });
        """, platform: .quantumultX, phase: .response, response: makeResponse(), services: services) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "200:{\"a\":1}")
        }
    }

    func testTimerKeepsTheRunAlive() {
        run("""
        setTimeout(function () { $done({ body: 'later' }); }, 20);
        """, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let next) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: next.body ?? Data(), as: UTF8.self), "later")
        }
    }

    func testThrowingScriptIsAbortedNotFatal() {
        run("throw new Error('boom');") { outcome, _ in
            guard case .aborted(let why) = outcome else { return XCTFail("expected an abort, got \(outcome)") }
            XCTAssertTrue(why.contains("boom"))
        }
    }

    func testTopLevelConstFromTwoScriptsDoesNotCollide() {
        // Each run gets its own context; two scripts that declare the same name
        // must both work. A shared context would throw on the second.
        for _ in 0..<2 {
            run("const API = 'x'; $done({});") { outcome, _ in
                XCTAssertEqual(outcome, .unchanged)
            }
        }
    }

    func testConsoleIsCaptured() {
        let services = FakeServices()
        run("console.log('hello', { a: 1 }); $done({});", services: services) { _, services in
            XCTAssertTrue(services.logged.contains { $0.contains("hello") })
        }
    }
}
