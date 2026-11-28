// The tunnel half of the probe: the engine sources of the ClashmacOSExtension target, hosted the way
// PacketTunnelProvider hosts them (ModuleEngineHost + ModuleEngineAssembly.configure), in a plain
// command-line process. It reads only what the App half published into the container.
// What is not the extension's:
//   - no packet tunnel and no mihomo: run.sh's stand-in answers the re-inject port, and curl plays
//     the MODULE-ENGINE proxy, signing in with the engine credentials the App published;
//   - upstream trust is ModuleServerTrust.anchors([the local origin's CA]), the engine's own test
//     seam (MODULES_ENGINE_TESTS), instead of .system; the SSL policy for the host name still applies;
//   - no script runner (ModuleNoScripts, as the host uses when it is given none): the module has no scripts;
//   - leaves and spilled bodies go to directories under $TMPDIR, and the host signals nothing.
import Foundation
import Security

func argument(_ name: String) -> String {
    let all = CommandLine.arguments
    guard let index = all.firstIndex(of: name), index + 1 < all.count else {
        FileHandle.standardError.write(Data("missing \(name)\n".utf8))
        exit(2)
    }
    return all[index + 1]
}

let stamp = ISO8601DateFormatter()
stamp.formatOptions = [.withTime, .withFractionalSeconds, .withColonSeparatorInTime]
let printLock = NSLock()
func say(_ line: String) {
    printLock.lock(); defer { printLock.unlock() }
    print("\(stamp.string(from: Date())) \(line)")
    fflush(stdout)
}

// Leaf identities must stay out of the keychain. On macOS 15 and later ModuleIdentity imports them
// in memory only (kSecImportToMemoryOnly); before 15 it would add them to the keychain.
guard #available(macOS 15, *) else {
    say("refusing to run: before macOS 15 the engine keeps leaf identities in the keychain")
    exit(3)
}
// ModuleEngineAssembly's leaf store sweeps keychain leftovers of earlier macOS 14 runs at start, but
// only while this process has leased no identity (ModuleKeychainLedger). Marking the ledger leased
// skips that sweep, the one keychain call on this path; it has no part in decrypting or rewriting.
ModuleKeychainLedger.process.noteLease()

let container = URL(fileURLWithPath: argument("--container"), isDirectory: true)
let storage = ModuleEngineStorage(leaves: URL(fileURLWithPath: argument("--leaves"), isDirectory: true),
                                  bodies: URL(fileURLWithPath: argument("--bodies"), isDirectory: true))
let originCADER = try Data(contentsOf: URL(fileURLWithPath: argument("--origin-ca-der")))
guard let originCA = SecCertificateCreateWithData(nil, originCADER as CFData) else {
    say("the origin CA is not a DER certificate")
    exit(2)
}
let revision = ModuleRunningRevision(profileID: argument("--profile"), revision: argument("--revision"))
let locations = ModuleEngineLocations(container: container, caKeyPlace: .file)

say("[probe] ModuleBodyLimits.current: default \(ModuleBodyLimits.current.defaultBytes) bytes, spill above \(ModuleBodyLimits.current.spillAbove.map(String.init) ?? "never"), memory guard \(ModuleBodyLimits.current.memoryGuard == nil ? "off" : "on")")

let host = ModuleEngineHost(
    locations: locations, log: ModuleEngineLog { say($0) }, signal: {},
    modulesSignal: "work-probe.modules.\(getpid())",
    rulesOnDemand: ModuleEngineHost.rulesOnDemandHere, idleRelease: ModuleEngineHost.idleReleaseHere,
    checkWithoutRules: { engine, entry, reporter in
        ModuleEngineAssembly.checkCertificate(engine, entry, reporter, locations: locations, storage: storage)
    },
    configure: { engine, inputs, reporter, scripts in
        ModuleEngineAssembly.configure(engine, inputs, reporter, locations: locations, scripts: scripts,
                                       thresholds: .current, storage: storage, trust: .anchors([originCA]))
    })

// What the packet tunnel tells the host around a configuration it starts.
host.willRun(revision)
host.didRun(revision)

let readyFile = argument("--ready")
DispatchQueue.global().async {
    for _ in 0..<200 {
        if let engine = host.engine, engine.isListening, engine.queue.sync(execute: { engine.interceptor != nil }) {
            try? Data("ready\n".utf8).write(to: URL(fileURLWithPath: readyFile))
            say("[probe] engine is listening and its rules are built")
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    say("[probe] the engine did not come up within 10 s")
    exit(4)
}

// The engine's counters, as the reporter would write them to engine-status.json (SIGUSR1, and at stop).
func sayCounters(_ why: String) {
    guard let engine = host.engine else { return say("[probe] counters (\(why)): no engine") }
    let counters = engine.queue.sync { engine.metrics.counters }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(counters) else { return }
    say("[probe] counters (\(why)) " + String(decoding: data, as: UTF8.self))
}
signal(SIGUSR1, SIG_IGN)
let ask = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
ask.setEventHandler { sayCounters("asked") }
ask.resume()

signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
stop.setEventHandler {
    sayCounters("stopping")
    host.tunnelStopped()
    say("[probe] stopped")
    exit(0)
}
stop.resume()
dispatchMain()
