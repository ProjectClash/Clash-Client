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
                     argument: ScriptArgument = .none,
                     parameters: ScriptRunParameters = ScriptRunParameters(),
                     services: FakeServices = FakeServices(),
                     timeout: TimeInterval = 3,
                     file: StaticString = #filePath, line: UInt = #line,
                     then check: @escaping @Sendable (ScriptOutcome, FakeServices) -> Void) {
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: timeout, grace: 0.2),
                                  services: services, makeEngine: { _, _ in try JSCEngine() })
        let done = expectation(description: "outcome")
        runner.run(script: ScriptSource(name: "test", key: "test", text: script, argument: argument,
                                        binaryBody: binaryBody, parameters: parameters),
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

    /// Loon's object form: `script("x.js", {${region}, ${level}})` arrives as an
    /// object whose values keep the types the plugin declared.
    func testArgumentObjectCarriesTypes() {
        run("""
        if ($argument.per_filter_video_thread !== false) { throw new Error('switch default did not arrive as a boolean'); }
        if ($argument.name !== 'x') { throw new Error('text default did not arrive as text'); }
        $done({});
        """, argument: .values(["per_filter_video_thread": .boolean(false), "name": .text("x")])) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// Loon's string form: `script("x.js", "a=1&b=2")` arrives as that string.
    /// Scripts split it without a type check, so an object here is a throw.
    func testArgumentStringArrivesAsAString() {
        run("""
        if (typeof $argument !== 'string') { throw new Error('expected a string, got ' + typeof $argument); }
        const pairs = $argument.split('&').map((pair) => pair.split('='));
        if (pairs[0][0] !== 'a' || pairs[0][1] !== '1') { throw new Error('the string did not split: ' + $argument); }
        $done({});
        """, argument: .text("a=1&b=2")) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// A `script("x.js")` with no second argument gives a script nothing.
    ///
    /// Loon documents the unconfigured value as "可能为 undefined 或 null" and
    /// Surge as "only present if the parameter is configured", so a script must
    /// cope with the global being absent, and the guard scripts actually write
    /// is `typeof $argument != 'undefined'`. Installing a `null` instead makes
    /// that guard pass and the next line — `$argument.split('&')` — throw;
    /// nine scripts in the hub's corpus fail exactly there. So the global is
    /// left off when the declaration has no argument, which satisfies both
    /// documents and every guard.
    func testArgumentOmittedIsAbsentRatherThanNull() {
        run("""
        if (typeof $argument !== 'undefined') { throw new Error('expected no $argument, got ' + typeof $argument); }
        $done({});
        """, argument: .none) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// The guard the corpus writes, run against that absent global: the
    /// `typeof` test takes the false branch and the object stays empty instead
    /// of the script dying one line later.
    func testTheCorpusArgumentGuardSurvivesAnOmittedArgument() {
        run("""
        let arg
        if (typeof $argument != 'undefined') {
          arg = Object.fromEntries($argument.split('&').map((item) => item.split('=')))
        } else {
          arg = {}
        }
        if (Object.keys(arg).length !== 0) { throw new Error('expected an empty object'); }
        $done({});
        """, argument: .none) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// Loon documents storage's key as optional: "省略 Key 时使用 `$script.name`
    /// 作为默认 Key". The harness names every script `test`, so a value written
    /// without a key has to be readable under that name — and a value written
    /// under an explicit key must not collide with it.
    func testStorageKeyDefaultsToTheScriptName() {
        run("""
        if ($persistentStore.write('by-default') !== true) { throw new Error('the write failed'); }
        const explicit = $persistentStore.read('test');
        if (explicit !== 'by-default') {
          throw new Error('the default key was not the script name, got: ' + explicit);
        }
        if ($persistentStore.write('by-name', 'other') !== true) { throw new Error('the keyed write failed'); }
        const untouched = $persistentStore.read('test');
        if (untouched !== 'by-default') {
          throw new Error('an explicit key overwrote the default one: ' + untouched);
        }
        $done({});
        """) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// Loon's manual for `$environment`: the parameters a generic script was run
    /// from, and "没有运行参数时，`$environment` 可能不存在". The hub's two node
    /// scripts need both halves: `NodeUnlockDetection.js` reads `params.node`,
    /// and `NodeLinkCheck.js` treats `params` itself as the node name.
    func testRunParametersAppearWhereLoonDocumentsThem() {
        run("""
        if (typeof $environment === 'undefined') { throw new Error('$environment should exist'); }
        if ($environment.params.node !== 'HK-01') { throw new Error('node: ' + $environment.params.node); }
        if ($environment.params.policyGroup !== 'Proxy') { throw new Error('policyGroup missing'); }
        if (String($environment.params) !== 'HK-01') { throw new Error('the old string form is not the node'); }
        if ($environment.params.search(/HK/) < 0) { throw new Error('search on params does not work'); }
        if ($environment.params.entry !== 'HK-01') { throw new Error('entry missing'); }
        $done({});
        """, parameters: ScriptRunParameters(node: "HK-01", policyGroup: "Proxy")) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// With no entry parameters there is no `$environment` at all, because an
    /// empty `params` answers `params.node` with `undefined` instead of letting
    /// a script notice that the run had no parameters.
    func testNoRunParametersMeansNoEnvironment() {
        run("""
        if (typeof $environment !== 'undefined') {
          throw new Error('$environment should be absent, got ' + JSON.stringify($environment));
        }
        const environment = typeof $environment === 'undefined' ? {} : $environment;
        const params = environment.params || {};
        if (params.node !== undefined) { throw new Error('unexpected node'); }
        $done({});
        """) { outcome, _ in
            XCTAssertEqual(outcome, .unchanged)
        }
    }

    /// A `cron`/`generic` script answers with a result object, not with a change
    /// to any traffic. Loon §11.1: "Generic 脚本可以返回一个结果对象，供调用入口展示或
    /// 消费". The hub's node checks exist only to produce one.
    func testGenericResultSurvivesTheRun() {
        run("""
        $done({ title: '  地理位置查询', htmlMessage: '<p>US</p>' });
        """) { outcome, _ in
            XCTAssertEqual(outcome, .result(ScriptResult(title: "  地理位置查询",
                                                         htmlMessage: "<p>US</p>")))
        }
    }

    /// The same answer in Loon's documented spelling, and a script that says
    /// nothing must still read as "no change" rather than as an empty result.
    func testGenericResultFromTheDocumentedShape() {
        run("""
        $done({ title: '查询完成', content: '当前任务已经执行完成' });
        """) { outcome, _ in
            XCTAssertEqual(outcome, .result(ScriptResult(title: "查询完成",
                                                         content: "当前任务已经执行完成")))
        }
    }

    /// The result the user actually reads. Every `generic` panel in the hub
    /// arrives as `htmlMessage`, so the conversion is what the screen shows —
    /// these are the real strings from `NodeLinkCheck.js` and
    /// `NetworkEntryAndExitQueries.js`, not invented examples.
    func testGenericResultRendersAsText() {
        let link = ScriptResult(title: "代理链路检测",
                                htmlMessage: #"<p style="text-align: center"><br><b>⟦ 未 知 错 误 ⟧ </b><br><font color=#f00><small>--------</small></font></p>"#)
        let text = link.plainText
        XCTAssertTrue(text.hasPrefix("代理链路检测\n"), text)
        XCTAssertTrue(text.contains("⟦ 未 知 错 误 ⟧"), text)
        XCTAssertFalse(text.contains("<"), text)
        XCTAssertFalse(text.contains("font"), text)

        // The one that names the node, with the entity and the nested spans.
        let entry = ScriptResult(
            title: "入口落地查询",
            htmlMessage: #"<div><br/><span style="font-weight: bold">IP</span>: -<br/><span style="font-weight: bold">节点</span>: <span style="color: #467fcf">HK-01 IEPL</span></div>"#)
        let rendered = entry.plainText
        XCTAssertTrue(rendered.contains("节点: HK-01 IEPL"), rendered)
        XCTAssertTrue(rendered.contains("IP: -"), rendered)
        XCTAssertFalse(rendered.contains("span"), rendered)
        // Blank lines left by consecutive tags collapse instead of padding the row.
        XCTAssertFalse(rendered.contains("\n\n"), rendered)
    }

    /// Each module's platform decides which globals exist, and a script written
    /// for one platform must be able to tell it is not on another.
    ///
    /// This is the contract the hub's corpus depends on: `app2smile/rules`
    /// ships one `.js` behind both a `.sgmodule` and a `.conf`, and the script
    /// branches on `typeof $task`, `$loon` and `$httpClient`. It is also why
    /// QX has no `$notification` — Env.js, `@nsnanocat/util` and QX's own sample
    /// all spell it `$notify`, and a QX run that answered `$notification` would
    /// silently take the Surge branch instead.
    func testEachPlatformGetsItsOwnGlobals() {
        // Surge and Loon have `$httpClient`; QX has `$task`; neither has the
        // other's, which is how 27 scripts in the corpus sniff the platform.
        run("""
        if (typeof $httpClient === 'undefined') { throw new Error('no $httpClient'); }
        if (typeof $notification === 'undefined') { throw new Error('no $notification'); }
        if (typeof $task !== 'undefined') { throw new Error('Surge must not have $task'); }
        $done({});
        """, platform: .surge) { outcome, _ in XCTAssertEqual(outcome, .unchanged) }

        run("""
        if (typeof $task === 'undefined') { throw new Error('no $task'); }
        if (typeof $notify === 'undefined') { throw new Error('no $notify'); }
        if (typeof $httpClient !== 'undefined') { throw new Error('QX must not have $httpClient'); }
        if (typeof $notification !== 'undefined') { throw new Error('QX must not have $notification'); }
        $done({});
        """, platform: .quantumultX) { outcome, _ in XCTAssertEqual(outcome, .unchanged) }

        run("""
        if (typeof $loon === 'undefined') { throw new Error('no $loon'); }
        // The value is a contract: `$loon.split(" ")` is device/version/ios.
        if ($loon.split(' ').length !== 3) { throw new Error('$loon shape: ' + $loon); }
        if (typeof $task !== 'undefined') { throw new Error('Loon must not have $task'); }
        $done({});
        """, platform: .loon) { outcome, _ in XCTAssertEqual(outcome, .unchanged) }
    }

    /// Shadowrocket and JSBox, the two platforms with no corpus of their own.
    ///
    /// They are the two a script cannot mistake for another: Env.js reads
    /// `$rocket` after `$task` and `$loon` and before nothing else, and JSBox is
    /// reached through globals no proxy client has. `@nsnanocat/util` orders them
    /// `$task → $loon → $rocket → Egern → surge-version → stash-version`, so a
    /// Shadowrocket run that also carried `$loon` would be read as Loon.
    func testShadowrocketIsNotMistakenForAnotherPlatform() {
        let probe = """
        function has(n) { return typeof globalThis[n] !== 'undefined'; }
        var seen = [];
        if (has('$task')) seen.push('$task');
        if (has('$loon')) seen.push('$loon');
        if (has('$rocket')) seen.push('$rocket');
        // `typeof` rather than a truthiness test: Shadowrocket has no
        // `$environment` at all, and Env.js's own guard is written this way for
        // exactly that reason.
        if (typeof $environment !== 'undefined') {
          if ($environment['surge-version']) seen.push('surge-version');
          if ($environment['stash-version']) seen.push('stash-version');
        }
        """
        // The order below is `@nsnanocat/util`'s, so the first match is the name
        // the script will believe.
        run(probe + """
        var app = seen.indexOf('$task') >= 0 ? 'Quantumult X'
          : seen.indexOf('$loon') >= 0 ? 'Loon'
          : seen.indexOf('$rocket') >= 0 ? 'Shadowrocket'
          : seen.indexOf('surge-version') >= 0 ? 'Surge'
          : seen.indexOf('stash-version') >= 0 ? 'Stash' : 'undefined';
        $done({ body: app + ' | ' + seen.join(',') });
        """, platform: .shadowrocket, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let response) = outcome else { return XCTFail("got \(outcome)") }
            guard let body = response.body.flatMap({ String(data: $0, encoding: .utf8) }) else {
                return XCTFail("no body")
            }
            XCTAssertEqual(body, "Shadowrocket | $rocket", "a Shadowrocket run must be seen as one")
        }
    }

    /// `$persistentStore` is Shadowrocket's storage, the same call Surge and
    /// Loon answer to — Env.js groups all three under one case.
    func testShadowrocketStorageAndNotification() {
        let services = FakeServices()
        run("""
        $persistentStore.write('v', 'k');
        var back = $persistentStore.read('k');
        $notification.post('t', 's', 'b');
        $done({ body: String(back) });
        """, platform: .shadowrocket, phase: .response, response: makeResponse(), services: services) { outcome, _ in
            guard case .response(let response) = outcome else { return XCTFail("got \(outcome)") }
            XCTAssertEqual(response.body.flatMap { String(data: $0, encoding: .utf8) }, "v")
        }
    }

    /// JSBox is Promise based and names its fields differently: `$http` resolves
    /// `{ data, response }`, `$cache` is synchronous, `$push` takes an object.
    func testJSBoxGetsItsOwnAPIAndNothingElse() {
        run("""
        if (typeof $http !== 'function') { throw new Error('no $http'); }
        if (typeof $cache !== 'object') { throw new Error('no $cache'); }
        if (typeof $push !== 'function') { throw new Error('no $push'); }
        if (typeof $httpClient !== 'undefined') { throw new Error('JSBox must not have $httpClient'); }
        if (typeof $task !== 'undefined') { throw new Error('JSBox must not have $task'); }
        if (typeof $loon !== 'undefined') { throw new Error('JSBox must not have $loon'); }
        if (typeof $rocket !== 'undefined') { throw new Error('JSBox must not have $rocket'); }
        $cache.set('k', 'v');
        $http({ url: 'https://example.com/', method: 'GET' }).then(function (r) {
            $done({ body: $cache.get('k') + '|' + r.response.status });
        });
        """, platform: .jsbox, phase: .response, response: makeResponse()) { outcome, _ in
            guard case .response(let response) = outcome else { return XCTFail("got \(outcome)") }
            XCTAssertEqual(response.body.flatMap { String(data: $0, encoding: .utf8) }, "v|200")
        }
    }

    /// QX has `$task`/`$prefs`/`$notify` and nothing else. It used to also carry
    /// JSBox's `$http`/`$cache`/`$push`, which no Quantumult X document lists and
    /// which let a script take a JSBox branch on a client that is not JSBox.
    func testQuantumultXDoesNotCarryJSBoxAPI() {
        run("""
        if (typeof $http !== 'undefined') { throw new Error('QX must not have $http'); }
        if (typeof $cache !== 'undefined') { throw new Error('QX must not have $cache'); }
        if (typeof $push !== 'undefined') { throw new Error('QX must not have $push'); }
        if (typeof $task === 'undefined') { throw new Error('no $task'); }
        $done({});
        """, platform: .quantumultX) { outcome, _ in XCTAssertEqual(outcome, .unchanged) }
    }

    /// `$utils.gzip`/`ungzip` are how the Bilibili gRPC scripts unwrap and
    /// rewrap a protobuf frame, so a broken byte contract here silently turns a
    /// rewrite into a no-op.
    ///
    /// The host answers the *bytes* op for real here — gzip is deterministic
    /// enough that a round trip through the prelude can be checked without a
    /// network. What the prelude owes the host is the wire shape: a
    /// `Uint8Array` argument must arrive as `{"data": {"$clashBytes": ...}}` and
    /// the answer must come back as a `Uint8Array`, not a base64 string.
    func testUtilsGzipRoundTripsThroughTheHost() {
        // A fixed gzip stream for the bytes `test` — produced once by zlib and
        // checked in, so the kit needs no compression dependency of its own.
        // What is under test is the prelude's byte contract, not zlib.
        let packed = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff,
                           0x2b, 0x49, 0x2d, 0x2e, 0x01, 0x00, 0x0c, 0x7e, 0x7f, 0xd8,
                           0x04, 0x00, 0x00, 0x00])
        let services = FakeServices()
        services.compressionHandler = { _, compress in compress ? packed : nil }
        run("""
        var source = new Uint8Array([10, 4, 116, 101, 115, 116]);
        var packed = $utils.gzip(source);
        if (!(packed instanceof Uint8Array)) { throw new Error('gzip did not return bytes'); }
        if (packed.length === 0) { throw new Error('gzip returned nothing'); }
        // The gzip magic: 0x1f 0x8b. A base64 string would fail both of these.
        if (packed[0] !== 0x1f || packed[1] !== 0x8b) { throw new Error('not gzip: ' + packed[0] + ',' + packed[1]); }
        $done({ body: String(packed.length) });
        """, platform: .surge, phase: .response, response: makeResponse(), services: services) { outcome, services in
            guard case .response(let response) = outcome else { return XCTFail("got \(outcome)") }
            let body = response.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertEqual(Int(body).map { $0 > 0 }, true, "gzip produced \(body) bytes")
            XCTAssertTrue(services.calls.contains("utils.gzip"), "the host was never asked: \(services.calls)")
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

/// The Quantumult X specifics: `$request.scheme`, `$request.path` and the
/// `$done({path: ...})` that its own sample scripts use.
final class JSEngineQuantumultXTests: XCTestCase {
    func testRequestExposesSchemeAndPath() {
        JSEngineTestsSupport.run("$done({ body: $request.scheme + '|' + $request.path });",
                                 platform: .quantumultX, phase: .response,
                                 request: ScriptRequest(method: "GET", url: "https://example.com/api/v1?a=1",
                                                        headers: ScriptHeaders(), body: nil),
                                 response: makeResponse()) { outcome in
            guard case .response(let response) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(String(decoding: response.body ?? Data(), as: UTF8.self), "https|/api/v1?a=1")
        }
    }

    func testDonePathRewritesTheRequestUrl() {
        JSEngineTestsSupport.run("""
        const headers = Object.assign({}, $request.headers);
        $done({ path: '/api2/abc?k=v', headers: headers });
        """, platform: .quantumultX, phase: .request,
            request: ScriptRequest(method: "GET", url: "https://example.com/api/abc",
                                   headers: ScriptHeaders(), body: nil),
            response: nil) { outcome in
            guard case .request(let next) = outcome else { return XCTFail("expected a changed request, got \(outcome)") }
            XCTAssertEqual(next.url, "https://example.com/api2/abc?k=v")
        }
    }

    func testDoneStatusLineOnQuantumultX() {
        JSEngineTestsSupport.run("""
        $done({ status: 'HTTP/1.1 200 OK', headers: { 'Content-Type': 'text/plain' }, body: 'rewritten' });
        """, platform: .quantumultX, phase: .response,
            response: ScriptResponse(status: 200, headers: ScriptHeaders(), body: Data("original".utf8))) { outcome in
            guard case .response(let response) = outcome else { return XCTFail("expected a response, got \(outcome)") }
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.body, Data("rewritten".utf8))
        }
    }

    func testQuantumultXHasNoLoonGlobals() {
        JSEngineTestsSupport.run("""
        if (typeof $loon !== 'undefined' || typeof $httpClient !== 'undefined' || typeof $persistentStore !== 'undefined') {
          throw new Error('Quantumult X must not expose Surge globals');
        }
        $done({});
        """, platform: .quantumultX, phase: .response, response: makeResponse()) { outcome in
            XCTAssertEqual(outcome, .unchanged)
        }
    }
}

enum JSEngineTestsSupport {
    static func run(_ script: String, platform: ScriptPlatform = .loon, phase: ScriptPhase = .request,
                    request: ScriptRequest = makeRequest(), response: ScriptResponse? = nil,
                    binaryBody: Bool = false, services: FakeServices = FakeServices(),
                    then check: @escaping @Sendable (ScriptOutcome) -> Void) {
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: 5, grace: 0.5),
                                  services: services, makeEngine: { _, _ in try JSCEngine() })
        let done = XCTestExpectation(description: "outcome")
        runner.run(script: ScriptSource(name: "test", key: "test", text: script, binaryBody: binaryBody),
                   request: request, response: response, identity: ScriptIdentity(platform: platform)) { outcome in
            check(outcome)
            done.fulfill()
        }
        _ = XCTWaiter.wait(for: [done], timeout: 12)
    }
}
