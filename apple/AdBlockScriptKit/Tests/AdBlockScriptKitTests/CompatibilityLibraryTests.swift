import XCTest
@testable import AdBlockScriptKit

/// The real engine, the real prelude, and the compatibility library scripts
/// actually ship with.
///
/// Almost every rewrite script published for these platforms opens with
/// `chavyleung/scripts`' `Env.js`, `sub-store-org/Sub-Store`'s `OpenAPI.js` or
/// `@nsnanocat/util`. Those libraries decide what host they are running on by
/// looking for a handful of globals **in a fixed order**, so a prelude that
/// installs one global too many is read as the wrong platform by every script
/// that uses them — the whole compatibility layer then takes the wrong branch
/// for storage, HTTP and notifications.
///
/// Nothing but the real library can prove that, so this test runs the real
/// `Env.js` (checked in under `Fixtures/`, GPL-3.0, unmodified) against the
/// real engine and reads its own answer back.
final class CompatibilityLibraryTests: XCTestCase {
    /// The library, as published.
    private static let envJS: String = {
        // The whole `Fixtures` directory is copied into the test bundle, so the
        // resource keeps its subdirectory.
        let url = Bundle.module.url(forResource: "Env", withExtension: "js", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "Env", withExtension: "js")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("the Env.js fixture is missing from the test bundle")
        }
        return text
    }()

    /// A production script with a second environment library embedded.
    ///
    /// `Env.js` is not the only one in circulation: `VirgilClyne/GetSomeFries`
    /// ships `@nsnanocat/util` inside every script it publishes, and that
    /// library orders its globals differently — `surge-version`/`stash-version`
    /// first, then `$task`, `$loon`, `$rocket`, `Egern`. A host that satisfies
    /// one library can still be misread by the other, so the real script is run
    /// and asked to name its own platform. Checked in under `Fixtures/`,
    /// GPL-3.0, unmodified.
    private static let friesScript: String = {
        let url = Bundle.module.url(forResource: "TikTok.request", withExtension: "js", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "TikTok.request", withExtension: "js")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("the TikTok.request.js fixture is missing from the test bundle")
        }
        return text
    }()

    private func run(_ script: String, platform: ScriptPlatform,
                     services: FakeServices, argument: ScriptArgument = .none,
                     timeout: TimeInterval = 5,
                     then check: @escaping @Sendable (ScriptOutcome, FakeServices) -> Void) {
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: timeout, grace: 0.5),
                                  services: services, makeEngine: { _, _ in try JSCEngine() })
        let done = expectation(description: "outcome")
        runner.run(script: ScriptSource(name: "compat", key: "compat",
                                        text: Self.envJS + "\n" + script,
                                        argument: argument, binaryBody: false),
                   request: makeRequest(), response: nil,
                   identity: ScriptIdentity(platform: platform)) { outcome in
            check(outcome, services)
            done.fulfill()
        }
        wait(for: [done], timeout: timeout + 5)
    }

    /// The real script names its own platform, on every platform this host
    /// offers. This is the check that one compatibility library could not make:
    /// `@nsnanocat/util`'s order differs from `Env.js`'s, and it is the library
    /// the ES6 rewrite scripts actually ship.
    func testAFriesScriptNamesItsOwnPlatform() {
        let expected: [(ScriptPlatform, String)] = [
            (.loon, "Loon"),
            (.surge, "Surge"),
            (.stash, "Stash"),
            (.quantumultX, "Quantumult X"),
            (.shadowrocket, "Shadowrocket"),
            // JSBox is not in this library's chain at all: its sequence ends at
            // `$rocket` and falls through to `undefined`. The host must not
            // invent a branch the library cannot read.
            (.jsbox, "undefined"),
        ]
        for (platform, name) in expected {
            let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: 5, grace: 0.5),
                                      services: FakeServices(), makeEngine: { _, _ in try JSCEngine() })
            let done = expectation(description: "\(platform)")
            // `ENV` is the class the script defines; its `platform()` is the
            // same probe the script uses on itself, called directly so the
            // script's own network work never runs.
            let probe = Self.friesScript + "\n$done({ response: { status: 200, body: String(ENV.prototype.platform.call({})) } });"
            runner.run(script: ScriptSource(name: "fries", key: "fries", text: probe),
                       request: makeRequest(), response: nil,
                       identity: ScriptIdentity(platform: platform)) { outcome in
                guard case .response(let mock) = outcome else {
                    XCTFail("\(platform): expected an answer, got \(outcome)")
                    return done.fulfill()
                }
                let body = String(decoding: mock.body ?? Data(), as: UTF8.self)
                XCTAssertEqual(body, name, "a \(platform) run must be reported as \(name)")
                done.fulfill()
            }
            wait(for: [done], timeout: 10)
        }
    }

    /// JSBox is its own ecosystem and has no Env.js branch — the library does
    /// not mention it at all — so its three interfaces are checked directly.
    /// A JSBox script reaches for `$http`, `$cache` and `$push`, none of which
    /// any of the proxy platforms define.
    func testJSBoxInterfaces() {
        let services = FakeServices()
        run("""
        if (typeof $http !== 'function') { throw new Error('no $http'); }
        if (!($cache && typeof $cache.get === 'function' && typeof $cache.set === 'function')) { throw new Error('no $cache'); }
        if (typeof $push !== 'function') { throw new Error('no $push'); }
        $cache.set('k', 'v');
        if ($cache.get('k') !== 'v') { throw new Error('$cache did not round-trip: ' + $cache.get('k')); }
        $push({ title: 'T', body: 'B' });
        $done({});
        """, platform: .jsbox, services: services) { outcome, services in
            XCTAssertEqual(outcome, .unchanged)
            XCTAssertTrue(services.notified.contains { $0.title == "T" },
                          "a JSBox `$push` must reach the notification surface")
        }
    }

    /// Each platform must be recognised as itself, not as whichever platform's
    /// global the prelude happens to install first.
    func testEnvJSSniffsEveryPlatform() {
        let expected: [(ScriptPlatform, String)] = [
            (.loon, "Loon"),
            (.surge, "Surge"),
            (.stash, "Stash"),
            (.quantumultX, "Quantumult X"),
            (.shadowrocket, "Shadowrocket"),
        ]
        for (platform, name) in expected {
            let services = FakeServices()
            run("""
            const $ = new Env('sniff');
            $done({ response: { status: 200, body: $.getEnv() } });
            """, platform: platform, services: services) { outcome, _ in
                guard case .response(let mock) = outcome else {
                    return XCTFail("\(platform): expected a mock, got \(outcome)")
                }
                let body = String(decoding: mock.body ?? Data(), as: UTF8.self)
                XCTAssertEqual(body, name, "Env.js must read a \(platform) run as \(name)")
            }
        }
    }

    /// Storage is the one API whose shape differs most between platforms —
    /// `$persistentStore` against `$prefs` — and Env.js picks between them by
    /// the same sniff, so a wrong answer shows up here as a lost value.
    func testEnvJSStorageRoundTripsOnEveryPlatform() {
        for platform in [ScriptPlatform.loon, .surge, .stash, .quantumultX, .shadowrocket] {
            let services = FakeServices()
            run("""
            const $ = new Env('storage');
            $.setval('kept-value', 'kept-key');
            $done({ response: { status: 200, body: String($.getval('kept-key')) } });
            """, platform: platform, services: services) { outcome, _ in
                guard case .response(let mock) = outcome else {
                    return XCTFail("\(platform): expected a mock, got \(outcome)")
                }
                XCTAssertEqual(String(decoding: mock.body ?? Data(), as: UTF8.self), "kept-value",
                               "\(platform): the value written through Env.js must read back")
            }
        }
    }

    /// `$done` inside an asynchronous callback, which is how real scripts end.
    /// The run must not be considered finished until the callback has run.
    func testEnvJSHttpThenDoneInTheCallback() {
        let services = FakeServices()
        services.httpAnswer = .json(["status": 200,
                                     "headers": ["Content-Type": "application/json"],
                                     "body": "{\"from\":\"the host\"}"])
        run("""
        const $ = new Env('http');
        $.get({ url: 'https://example.com/api' }, (err, resp, data) => {
          $done({ response: { status: 200, body: JSON.stringify({ env: $.getEnv(), data: data }) } });
        });
        """, platform: .loon, services: services) { outcome, services in
            guard case .response(let mock) = outcome else {
                return XCTFail("expected a mock, got \(outcome)")
            }
            let body = String(decoding: mock.body ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("\"env\":\"Loon\""), "Env.js must still know its platform: \(body)")
            XCTAssertTrue(body.contains("the host"), "the host's answer must reach the script: \(body)")
            XCTAssertTrue(services.calls.contains("http"), "the host must have been asked for the URL")
        }
    }
}
