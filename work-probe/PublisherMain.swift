// The App half of the probe. It is compiled together with the ClashmacOS App target's own sources
// (see sources.list) and drives the App's real code into a container directory of its own:
//   ModuleStore.setEnabled / add(url:)  - draws ports and credentials, parses the module, publishes
//   ModuleCertificateStore.ensureCertificate - makes the modules' CA
//   ModuleActivationStep.prepare         - turns the published modules into an engine assignment
//   ModuleEnginePlan.record              - writes the plan the tunnel reads
// What is not the App's: the module bytes come from ProbeFetcher instead of an HTTPS download, the
// two ports are picked by run.sh, the CA key is kept in a file (as on iOS) instead of the macOS
// keychain, and the engine status handed to the activation is .ready (the CA trusted on the device).
import Foundation

func argument(_ name: String) -> String {
    let all = CommandLine.arguments
    guard let index = all.firstIndex(of: name), index + 1 < all.count else {
        FileHandle.standardError.write(Data("missing \(name)\n".utf8))
        exit(2)
    }
    return all[index + 1]
}

func say(_ line: String) { print("[app] " + line); fflush(stdout) }

let container = URL(fileURLWithPath: argument("--container"), isDirectory: true)
let moduleFile = URL(fileURLWithPath: argument("--module"))
let moduleURL = URL(string: argument("--module-url"))!
let enginePort = UInt16(argument("--engine-port"))!
let reinjectPort = UInt16(argument("--reinject-port"))!
let summaryFile = URL(fileURLWithPath: argument("--summary"))
let moduleBytes = try Data(contentsOf: moduleFile)

// The download the App would make: the module's bytes for its own address, nothing else.
struct ProbeFetcher: HTTPFetching {
    let url: URL
    let body: Data
    func fetch(_ request: URLRequest, maxBytes: Int, redirectPolicy: DownloadRedirectPolicy) async throws -> DownloadResult {
        guard request.url == url else { throw DownloadError.badStatus(404) }
        say("download \(url.absoluteString) answered with the module file (\(body.count) bytes), User-Agent \(request.value(forHTTPHeaderField: "User-Agent") ?? "-")")
        return DownloadResult(data: body, etag: nil, lastModified: nil, subscriptionUserInfo: nil, notModified: false)
    }
}

// ModuleStore draws the engine port first and the re-inject port second (drawPorts).
final class PortPick: @unchecked Sendable {
    private let lock = NSLock()
    private var left: [UInt16]
    init(_ ports: [UInt16]) { left = ports }
    func next() -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        precondition(!left.isEmpty, "ModuleStore asked for more ports than the probe gave it")
        return left.removeFirst()
    }
}
let ports = PortPick([enginePort, reinjectPort])

let locations = ModuleLocations(container: container)
let engineLocations = ModuleEngineLocations(container: container, caKeyPlace: .file)
let store = ModuleStore(locations: locations, fetcher: ProbeFetcher(url: moduleURL, body: moduleBytes),
                        randomPort: { ports.next() }, log: { say($0) })
let certificates = ModuleCertificateStore(locations: engineLocations, locale: { Locale(identifier: "zh_CN") },
                                          log: { say($0) })

try await store.setEnabled(true)
let ca = try await certificates.ensureCertificate(republishing: store)
say("CA \(ca.commonName) sha256 \(ca.fingerprintSHA256)")
let record = try await store.add(url: moduleURL.absoluteString)
say("module \(record.id) \"\(record.displayName)\" added from \(moduleURL.absoluteString)")

// What the parser made of the module, as published for the tunnel.
let irData = try Data(contentsOf: locations.moduleManifest(record.id))
if let ir = try JSONSerialization.jsonObject(with: irData) as? [String: Any] {
    let manifest = ir["manifest"] as? [String: Any] ?? [:]
    say("parsed as format \(manifest["format"] ?? "?"), name \(manifest["name"] ?? "?")")
    for key in ["rewriteRules", "mitmHostLines", "ignored"] {
        guard let value = ir[key] else { continue }
        let text = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        say("ir.\(key) = \(text)")
    }
}
let manifest = try ModuleJSON.decoder().decode(ModuleGlobalManifest.self, from: Data(contentsOf: locations.globalManifest))
say("published: \(manifest.modules.count) module(s), mitm hosts \(manifest.mitmHosts.items.map { "\($0.entry.pattern)" }), ports \(manifest.ports.map { "engine \($0.engine) re-inject \($0.reinject)" } ?? "none"), CA \(manifest.caFingerprintSHA256 ?? "none")")

// The activation the App runs when it publishes a configuration with modules on.
let runtimeYAML = """
mixed-port: 7890
mode: rule
log-level: info
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT

"""
var input = ModuleActivationInput(manifest: manifest, engine: .ready)
input.geodataDirectory = container.appendingPathComponent("working", isDirectory: true)
input.ruleSetCopiesDirectory = locations.ruleSetCopiesDirectory
let outcome = await ModuleActivationStep.prepare(runtimeYAML, input: input)
say(outcome.logLine ?? "the activation wrote no log line")
guard let assignment = outcome.engineAssignment else {
    say("the activation gave no engine assignment: \(outcome.degradedBecause)")
    exit(1)
}
for line in outcome.text.split(separator: "\n", omittingEmptySubsequences: false)
where line.contains("MODULE") || line.contains("127.0.0.1") || line.contains(String(reinjectPort)) || line.contains(String(enginePort)) {
    say("mihomo config: \(line)")
}
let revision = ModuleRunningRevision(profileID: "probe", revision: "r1")
try ModuleEnginePlan.record(assignment, for: revision, at: Date(), keeping: [revision], locations: engineLocations)
say("engine plan recorded for \(revision.profileID)/\(revision.revision): decrypting \(assignment.decryptsTLS), mitm \(assignment.mitmHosts.items.map { "\($0.entry.pattern)" }), \(assignment.modules.count) module(s)")

let caDER = try Data(contentsOf: engineLocations.caCertificate)
let pem = "-----BEGIN CERTIFICATE-----\n" + caDER.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    + "\n-----END CERTIFICATE-----\n"
try Data(pem.utf8).write(to: container.appendingPathComponent("module-ca.pem"))
let summary: [String: Any] = [
    "enginePort": assignment.ports.engine, "reinjectPort": assignment.ports.reinject,
    "engineUser": assignment.engineProxyCredentials?.username ?? "", "enginePassword": assignment.engineProxyCredentials?.password ?? "",
    "reinjectUser": assignment.reinjectCredentials?.username ?? "", "reinjectPassword": assignment.reinjectCredentials?.password ?? "",
    "caPEM": container.appendingPathComponent("module-ca.pem").path,
    "profileID": revision.profileID, "revision": revision.revision,
]
try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted]).write(to: summaryFile)
say("summary written to \(summaryFile.path)")
