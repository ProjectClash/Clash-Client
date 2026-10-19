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

    private func run(_ script: String, platform: ScriptPlatform,
                     services: FakeServices, argument: [String: ScriptArgumentValue] = [:],
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
