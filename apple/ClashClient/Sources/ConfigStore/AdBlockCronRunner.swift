#if os(iOS) || os(macOS)
import AdBlockScriptKit
import Foundation
import os

/// Runs the `cron` and `generic` scripts the installed modules declare.
///
/// The tunnel cannot do this. It is only up while the VPN is, and a task that
/// runs at 10:00 has to run whether or not the user was browsing; Surge, Loon
/// and Quantumult X all run scheduled scripts from the app for the same reason.
/// So the app owns the schedule, and the tunnel owns nothing but the HTTP
/// scripts it is handed per exchange.
///
/// The work is driven by the refresh the app already does — `BackgroundRefresh`
/// wakes it and this runs what is due before it returns — so there is no second
/// background task competing for the same budget.
enum AdBlockCronRunner {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clash", category: "AdBlockCron")

    /// How long a single wake-up may spend on scheduled scripts. The refresh
    /// task it runs under has about thirty seconds in total and other work to
    /// do, so this is a share of it rather than all of it.
    static let budget: TimeInterval = 12

    /// A task is identified by its module and script, and remembered by the
    /// minute it was due, so a restart does not re-run what just ran.
    static func bookkeeping(locations: AdBlockModuleLocations) -> AdBlockCronFile {
        AdBlockCronFile(url: locations.container.appendingPathComponent("working/adblock/cron-runs.json"))
    }

    /// The JSON the publisher writes for a module.
    ///
    /// Only the fields the scheduler needs are named; the rest is another
    /// target's business, and a shape here that drifts from the publisher's
    /// would be a decode failure rather than a crash, which is what a module
    /// that is mid-update needs.
    private struct PublishedModule: Decodable {
        struct Manifest: Decodable { var format: AdBlockModuleFormat }
        var manifest: Manifest
        var scripts: [AdBlockScript]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A module published by an older build has no manifest object; its
            // dialect is then unknown and Loon is assumed, as the tunnel does.
            manifest = (try? container.decode(Manifest.self, forKey: .manifest)) ?? Manifest(format: .loon)
            scripts = (try? container.decode([AdBlockScript].self, forKey: .scripts)) ?? []
        }

        enum CodingKeys: String, CodingKey { case manifest, scripts }
    }

    /// The scheduled scripts of the installed, enabled modules, read from what
    /// the store already published for the tunnel.
    static func tasks(locations: AdBlockModuleLocations? = .production) -> [AdBlockCronTask] {
        guard let locations else { return [] }
        let store = AdBlockModuleStore.shared(locations.container)
        guard let state = try? store.state() else { return [] }
        var out: [AdBlockCronTask] = []
        for record in state.modules where record.enabled {
            guard let data = try? Data(contentsOf: locations.moduleManifest(record.id)),
                  let module = try? JSONDecoder().decode(PublishedModule.self, from: data) else { continue }
            for script in module.scripts where script.phase == .cron || script.phase == .generic {
                guard let task = task(script: script, module: record.id, format: module.manifest.format,
                                      locations: locations) else { continue }
                out.append(task)
            }
        }
        return out
    }

    private static func task(script: AdBlockScript, module: String, format: AdBlockModuleFormat,
                             locations: AdBlockModuleLocations) -> AdBlockCronTask? {
        // A cron needs a schedule; a generic script has none and is run by the
        // app's own menu, which this build does not have yet, so it is left out
        // rather than run on a made-up cadence.
        guard script.phase == .cron,
              let text = script.cronFields?.first,
              let schedule = AdBlockCronSchedule.parse(text),
              let sha = script.bodySHA256,
              let data = try? Data(contentsOf: locations.script(module, sha256: sha)),
              let source = String(data: data, encoding: .utf8) else { return nil }
        let key = script.scriptURL.isEmpty ? script.pattern : script.scriptURL
        let scriptSource = ScriptSource(name: script.name, key: key, text: source,
                                        timeout: script.timeout.map(TimeInterval.init),
                                        sourceURL: script.scriptURL,
                                        argument: AdBlockScriptFace.arguments(for: script,
                                                                            choices: AdBlockScriptSettings.choices()))
        return AdBlockCronTask(script: scriptSource, module: module,
                               identity: AdBlockScriptFace.identity(for: format),
                               schedule: schedule, timeout: script.timeout.map(TimeInterval.init))
    }

    /// Runs what is due, within `budget`. Called from the refresh the app
    /// already performs; returns how many ran, for the log line.
    @discardableResult
    static func runDue(now: Date = Date(), budget: TimeInterval = budget,
                       locations: AdBlockModuleLocations? = .production) -> Int {
        guard let locations else { return 0 }
        let tasks = tasks(locations: locations)
        guard !tasks.isEmpty else { return 0 }
        let scheduler = AdBlockCronScheduler(bookkeeping: bookkeeping(locations: locations))
        // Storage is the same file the tunnel's scripts use, so a task and an
        // HTTP script see one `$persistentStore`; HTTP itself is unavailable
        // here, because the app has no connector of its own and a scheduled
        // run has no exchange to borrow one from.
        let storage = locations.container.appendingPathComponent("adblock-scripts.json")
        let runner = ScriptRunner(limits: ScriptRunLimits(defaultTimeout: 60, grace: 5),
                                  services: AdBlockCronServices(storageURL: storage),
                                  makeEngine: { _, _ in try JSCEngine() })
        let ran = scheduler.drain(tasks, now: now, budget: budget) { task in
            let done = DispatchSemaphore(value: 0)
            runner.runScheduled(script: task.script, identity: task.identity) { outcome in
                if case .unavailable(let reason) = outcome {
                    log.notice("scheduled script \(task.script.name, privacy: .public) unavailable: \(reason, privacy: .public)")
                }
                done.signal()
            }
            // A scheduled script has no traffic to hold up, but the wake-up is
            // short. Waiting here keeps the drain honest about its budget
            // instead of spawning work it never accounts for.
            _ = done.wait(timeout: .now() + min(task.timeout ?? 60, budget) + 5)
        }
        if ran > 0 { log.notice("ran \(ran) scheduled script(s)") }
        return ran
    }
}
#endif

#if os(iOS) || os(macOS)
/// What a scheduled script can reach.
///
/// Storage, because a task that cannot remember anything between runs is not
/// worth scheduling — a check-in script's whole job is remembering. Everything
/// else answers "unavailable" rather than pretending: HTTP would need the
/// tunnel's connector, and the app has none; notifications and DNS have no
/// business being woken by a background task the user did not just open.
final class AdBlockCronServices: ScriptHostServices, ScriptSynchronousServices, @unchecked Sendable {
    private let store: ScriptStore

    init(storageURL: URL?) { self.store = ScriptStore(url: storageURL) }

    func perform(_ call: ScriptHostCall, completion: @escaping @Sendable (ScriptHostAnswer) -> Void) {
        completion(.failure("a scheduled script cannot use \(call.name)"))
    }

    func synchronousAnswer(name: String, payload: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        switch name {
        case "store.read":
            guard let value = store.read(object["key"] as? String) else { return "null" }
            return (try? JSONSerialization.data(withJSONObject: value))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        case "store.write":
            if object["all"] as? Bool == true {
                store.removeAll()
                return "true"
            }
            store.write(object["value"] as? String, for: object["key"] as? String)
            return "true"
        default:
            // A scheduled script that asks the configuration group a question
            // gets no answer, which is what the platforms do for a group that
            // does not exist: the script falls back to its own default.
            return "null"
        }
    }
}
#endif
