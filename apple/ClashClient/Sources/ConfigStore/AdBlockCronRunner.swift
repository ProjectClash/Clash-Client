#if os(iOS) || os(macOS)
import AdBlockScriptKit
import Foundation
import UserNotifications
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
                             locations: AdBlockModuleLocations, scheduled: Bool = true) -> AdBlockCronTask? {
        // A cron needs a schedule; a generic script has none and is run when the
        // user asks for it, which `runGeneric` does. A schedule is required for
        // one and absent for the other rather than invented for either.
        let schedule: AdBlockCronSchedule.Schedule?
        if scheduled {
            guard script.phase == .cron,
                  let text = script.cronFields?.first,
                  let parsed = AdBlockCronSchedule.parse(text) else { return nil }
            schedule = parsed
        } else {
            guard script.phase == .generic else { return nil }
            schedule = nil
        }
        guard let sha = script.bodySHA256,
              let data = try? Data(contentsOf: locations.script(module, sha256: sha)),
              let source = String(data: data, encoding: .utf8) else { return nil }
        let key = script.scriptURL.isEmpty ? script.pattern : script.scriptURL
        let scriptSource = ScriptSource(name: script.name, key: key, text: source,
                                        timeout: script.timeout.map(TimeInterval.init),
                                        sourceURL: script.scriptURL,
                                        argument: AdBlockScriptFace.argument(for: script,
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
        let ran = scheduler.drain(tasks, now: now, budget: budget) { [entryParameters = AdBlockRunEntry.parameters()] task in
            let done = DispatchSemaphore(value: 0)
            runner.runScheduled(script: task.script, identity: task.identity, parameters: entryParameters) { outcome in
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

    /// The `generic` scripts of one installed module, newest first.
    ///
    /// A generic script has no schedule and no URL: Loon's own words are "as a
    /// script that can be run manually from the app", and Surge's are the same.
    /// The hub publishes two plugins that are nothing but generic scripts, so
    /// without this they install and then do nothing at all.
    static func genericScripts(module moduleID: String, locations: AdBlockModuleLocations? = .production) -> [AdBlockCronTask] {
        guard let locations else { return [] }
        guard let data = try? Data(contentsOf: locations.moduleManifest(moduleID)),
              let module = try? JSONDecoder().decode(PublishedModule.self, from: data) else { return [] }
        return module.scripts
            .filter { $0.phase == .generic }
            .compactMap { task(script: $0, module: moduleID, format: module.manifest.format, locations: locations, scheduled: false) }
    }

    /// The generic script of an installed module whose body hashes to `sha256`.
    ///
    /// The detail page identifies a script by its hash — that is what `Item`'s
    /// action carries — because the page does not know which module it is
    /// looking at beyond the one it is showing. Searching the installed,
    /// enabled modules for the hash finds it either way.
    static func genericScript(bodySHA256 sha: String, locations: AdBlockModuleLocations? = .production) -> AdBlockCronTask? {
        guard let locations else { return nil }
        let store = AdBlockModuleStore.shared(locations.container)
        guard let state = try? store.state() else { return nil }
        for record in state.modules where record.enabled {
            guard let data = try? Data(contentsOf: locations.moduleManifest(record.id)),
                  let module = try? JSONDecoder().decode(PublishedModule.self, from: data) else { continue }
            guard let script = module.scripts.first(where: { $0.phase == .generic && $0.bodySHA256 == sha }) else { continue }
            if let task = task(script: script, module: record.id, format: module.manifest.format,
                               locations: locations, scheduled: false) {
                return task
            }
        }
        return nil
    }

    /// Runs one generic script now and calls back on the main queue.
    ///
    /// There is no scheduler here and no due time: the user asked for it. The
    /// callback carries what the script answered so the page can say something
    /// other than "ran", which for a script the user is watching is the whole
    /// point — these are node checks and unlock tests, not silent maintenance.
    static func runGeneric(_ task: AdBlockCronTask, locations: AdBlockModuleLocations? = .production,
                           completion: @escaping @Sendable (ScriptOutcome) -> Void) {
        guard let locations else {
            completion(.unavailable("the module container is not available"))
            return
        }
        let storage = locations.container.appendingPathComponent("adblock-scripts.json")
        let limits = ScriptRunLimits(defaultTimeout: 300, grace: 5)
        let runner = ScriptRunner(limits: limits,
                                  services: AdBlockCronServices(storageURL: storage),
                                  makeEngine: { _, _ in try JSCEngine() })
        // The run happens on its own thread; the answer is carried back through
        // a box because the completion is `@Sendable` and `runScheduled` may
        // call it from anywhere. The semaphore is only about waiting, and what
        // it waits for is the timeout the script already declared.
        final class Answer: @unchecked Sendable {
            private let lock = NSLock()
            private var value: ScriptOutcome?
            func store(_ outcome: ScriptOutcome) {
                lock.lock(); value = outcome; lock.unlock()
            }
            var outcome: ScriptOutcome? {
                lock.lock(); defer { lock.unlock() }
                return value
            }
        }
        let answer = Answer()
        let finished = DispatchSemaphore(value: 0)
        runner.runScheduled(script: task.script, identity: task.identity, parameters: AdBlockRunEntry.parameters()) { outcome in
            answer.store(outcome)
            finished.signal()
        }
        // Wait for the runner's own budget, grace included, so a script that
        // runs out of time is reported by the runner as a timeout rather than
        // by this wait as a missing answer. A second on top covers the callback
        // hopping back to this thread; it is not more time for the script.
        _ = finished.wait(timeout: .now() + limits.budget(for: task.timeout) + 1)
        let outcome = answer.outcome ?? .timedOut
        switch outcome {
        case .timedOut:
            log.notice("generic script \(task.script.name, privacy: .public) ran out of time")
        case .unavailable(let reason):
            log.notice("generic script \(task.script.name, privacy: .public) unavailable: \(reason, privacy: .public)")
        default:
            log.notice("ran generic script \(task.script.name, privacy: .public)")
        }
        DispatchQueue.main.async { completion(outcome) }
    }
}
#endif

#if os(iOS) || os(macOS)
/// The node and policy a `cron`/`generic` script is run from.
///
/// Loon documents `$environment.params` as the entry parameters a script run
/// "从节点、策略等入口" receives, and the hub's `NodeLinkCheck` and
/// `NodeUnlockDetection` exist only to read them. The app already knows the
/// answer: the user's picks are `Profile.selectedMap` (group → node) and the
/// group they last looked at is `currentGroupName`. No engine call is involved,
/// which is why this can run from a background wake-up as well as the UI.
///
/// Nothing invented: when the profile has no selection, or the selection names
/// a group this build does not have a member for, the parameters are empty and
/// `$environment` is left off rather than filled with a plausible guess — a
/// node check that reports the wrong node is worse than one that reports none.
enum AdBlockRunEntry {
    static func parameters() -> ScriptRunParameters {
        guard let state = NodeProfilePreferencesStore.live()?.load() else {
            return ScriptRunParameters()
        }
        // The group the user last opened decides which pick is "the" node. A
        // profile with a single group has only one answer anyway.
        let group = state.currentGroupName.flatMap { name in
            state.selectedMap[name] == nil ? nil : name
        } ?? state.selectedMap.keys.sorted().first
        guard let group, let node = state.selectedMap[group] else {
            return ScriptRunParameters()
        }
        return ScriptRunParameters(node: node, policyGroup: group)
    }
}

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

    /// A scheduled script's `console.log` goes to the app's log.
    ///
    /// It has nowhere else to go: there is no page and no tunnel journal
    /// attached, and a script that logged into the void would be undebuggable
    /// exactly when the user is trying to find out why their check-in script
    /// said nothing. The logger is a static of its own so this method does not
    /// shadow it.
    private static let journal = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clash",
                                        category: "AdBlockCronScript")

    func log(_ line: String, level: String) {
        switch level {
        case "error": Self.journal.error("\(line, privacy: .public)")
        case "warning": Self.journal.warning("\(line, privacy: .public)")
        default: Self.journal.info("\(line, privacy: .public)")
        }
    }

    /// A notification from a scheduled script is posted as a local one.
    ///
    /// This is often the whole reason a scheduled script exists — a check-in
    /// that reports its result, a ticket or stock watcher — so it is delivered
    /// rather than dropped. The app can present its own notifications, unlike
    /// the tunnel, which may only schedule them.
    func notify(_ notification: ScriptNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        if let url = notification.openURL { content.userInfo["openUrl"] = url }
        if let clipboard = notification.clipboard { content.userInfo["clipboard"] = clipboard }
        if notification.sound == true { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
