import CryptoKit
import Foundation
import Clash

 
 
 
 
 
 
 
enum ClashTVCore {
    static func ensureSetup(container: URL) throws {
        try AppCoreSetup.ensure(container: container)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ClashTVConfigPipeline {
    enum Phase: Equatable {
        case downloading
        case preparing
        case publishing
    }

    struct Activation: Equatable {
        let profileID: String
        let revision: String
        let finalYAML: String
        let providerCount: Int
        let warnings: [String]
        let userInfo: String?
         
         
        let panelName: String?
         
        let catalog: ClashTVProviderCatalog
         
         
        var ruleFacts: ClashTVRuleFacts? = nil
         
         
        var publishedPath: String? = nil
         
         
        var changed = true
    }

    enum PipelineError: LocalizedError {
        case invalidConfiguration(String)
        case planRejected([String])
        case publishFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let reason):
                return String(localized: "Clash can't read this profile: \(reason)")
            case .planRejected(let reasons):
                let joined = reasons.joined(separator: "; ")
                return String(localized: "The configuration was refused: \(joined)")
            case .publishFailed(let reason):
                return String(localized: "The configuration could not be saved on this Apple TV: \(reason)")
            }
        }
    }

    let container: URL
    let session: URLSession

     
     
     
     
     
    let defaults: UserDefaults
    private let setupCore: ((URL) throws -> Void)?
    private let frozenSettings: IPStackSettings?
     
     
     
    private let inBackground: Bool
    private let ruleFetchDeadline: Duration
     
     
    typealias Stage = (_ finalYAML: String, _ providerCount: Int, _ compileRuleSets: Bool) -> Void
    private let stage: Stage
     
     
    private let beforePublish: (() throws -> Void)?

    init(
        container: URL,
        session: URLSession = ClashTVNetwork.session,
        defaults: UserDefaults = ClientUserAgent.appGroupDefaults,
        settings: IPStackSettings? = nil,
        setupCore: ((URL) throws -> Void)? = nil,
        inBackground: Bool = false,
        stage: Stage? = nil,
        beforePublish: (() throws -> Void)? = nil,
        ruleFetchDeadline: Duration = ClashTVProviderMaterializer.ruleFetchDeadline
    ) {
        self.ruleFetchDeadline = ruleFetchDeadline
        self.inBackground = inBackground
        self.beforePublish = beforePublish
        self.stage = stage ?? { ProviderStagingPublisher.publish(finalYAML: $0, providerCount: $1, compileRuleSets: $2) }
        self.defaults = defaults
        self.setupCore = setupCore
        self.frozenSettings = settings
        self.container = container
        self.session = session
    }

     
     
     
    static func nodeLibraryDirectory(container: URL) -> URL {
        container.appendingPathComponent("node-libraries", isDirectory: true)
    }

     
     
     
     
     
     
     
     
     
    @discardableResult
    static func eachStoredConfiguration(container: URL, _ visit: (Data) -> Bool) -> Bool {
        let profiles = container.appendingPathComponent("working/store/profiles", isDirectory: true)
        let files = FileManager.default
        func entries(_ url: URL) -> [String]? {
            do { return try files.contentsOfDirectory(atPath: url.path) } catch {
                return (error as NSError).code == NSFileReadNoSuchFileError ? [] : nil
            }
        }
         
         
        var whole = true
        guard let ids = entries(profiles) else { return false }
        for id in ids where !id.hasPrefix(".") {
            let revisions = profiles.appendingPathComponent(id).appendingPathComponent("revisions", isDirectory: true)
            guard let names = entries(revisions) else { whole = false; continue }
            for revision in names where !revision.hasPrefix(".") {
                let directory = revisions.appendingPathComponent(revision, isDirectory: true)
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("config.resolved.yaml")) else {
                     
                     
                     
                    let manifest = directory.appendingPathComponent("manifest.json").path
                    if FileManager.default.fileExists(atPath: manifest) { whole = false }
                    continue
                }
                guard visit(data) else { return whole }
            }
        }
        return whole
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func pruneNodeLibraries(container: URL) {
         
         
         
         
        NodeLibraries.prune(container: container)
    }

     
     
     
     
     
     
     
     
     
     
    static func refusal(_ error: Error) -> Error {
        Task.isCancelled || error is CancellationError ? CancellationError() : PipelineError.invalidConfiguration(error.localizedDescription)
    }

    static func profileID(for subscription: ClashTVSubscription) -> String {
        var identity = subscription.requestURL.absoluteString
        if subscription.effectiveRules != .own { identity += "\n" + subscription.effectiveRules.rawValue }
         
         
        if let script = subscription.scriptURL { identity += "\nscript:" + script.absoluteString }
        let digest = SHA256.hash(data: Data(identity.utf8))
        let bytes = Array(digest.prefix(16))
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid.uuidString.lowercased()
    }

    var userAgent: String {
        ClashTVSubscriptionFetcher.userAgent(defaults: defaults)
    }

    private func prepareEnvironment(settings: IPStackSettings) throws {
        let working = container.appendingPathComponent("working", isDirectory: true)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        if let setupCore { try setupCore(container) }
        else { try AppCoreSetup.ensure(container: container, settings: settings) }
        try BundledGeodataProvisioner.seedAllMissing(into: working)
    }

     
     
     
    func updateScript(for subscription: ClashTVSubscription) async throws -> Int {
        guard subscription.scriptURL != nil else {
            throw PipelineError.invalidConfiguration(ClashTVOverrideScript.noScript)
        }
        let source = try await fetchScript(for: subscription, profileID: Self.profileID(for: subscription))
        ClashLogStore.shared.append("tv override script updated  bytes=\(source.utf8.count)", stream: .app)
        return source.utf8.count
    }

    private func fetchScript(for subscription: ClashTVSubscription, profileID: String) async throws -> String {
        guard let scriptURL = subscription.scriptURL else {
            throw PipelineError.invalidConfiguration(ClashTVOverrideScript.noScript)
        }
        let script = try await ClashTVSubscriptionFetcher.fetchBody(scriptURL, session: session, userAgent: userAgent,
                                                                   maximumBytes: ClashTVSubscriptionFetcher.maximumScriptBytes)
        guard let source = String(data: script.body, encoding: .utf8) else {
            throw PipelineError.invalidConfiguration(ClashTVOverrideScript.notText)
        }
        try ClashTVOverrideScriptStore.write(source, container: container, profileID: profileID)
        return source
    }

    func activate(
        subscription: ClashTVSubscription,
         
         
        tunnelRunning: Bool = false,
        progress: @escaping (Phase) -> Void
    ) async throws -> Activation {
        let settings = try frozenSettings ?? IPStackSettings.load(from: defaults)
        try prepareEnvironment(settings: settings)

        let profileID = Self.profileID(for: subscription)
         
         
         
        let work = try Self.workFiles(container: container)
        defer { work.remove() }
        let sourceFile: URL
        var checked = false
        let userInfo: String?
        let panelName: String?
        let restored = ClashTVRestoredDocuments.url(container: container, profileID: profileID)
        if FileManager.default.fileExists(atPath: restored.path) {
             
             
             
             
            try FileManager.default.copyItem(at: restored, to: work.source)
            sourceFile = work.source
            userInfo = nil
            panelName = nil
        } else {
            progress(.downloading)
            let fetched = try await ClashTVSubscriptionFetcher.fetchFile(
                subscription.requestURL, session: session, userAgent: userAgent, to: work.source)
             
             
             
             
             
            var composed: URL
            do {
                (composed, checked) = try ClashTVComposedProfile.compose(
                    at: work.source, rules: subscription.effectiveRules, into: work.composed)
            } catch let error as ClashTVSubscriptionFetcher.FetchError {
                throw error
            } catch {
                throw Self.refusal(error)
            }
             
             
             
             
             
            if subscription.scriptURL != nil {
                 
                 
                 
                guard !ClashTVComposedProfile.isTooLargeToReadWhole(composed) else {
                    throw ClashTVOverrideScript.TooLarge()
                }
                 
                 
                let source: String
                if let kept = ClashTVOverrideScriptStore.read(container: container, profileID: profileID) {
                    source = kept
                } else {
                    source = try await fetchScript(for: subscription, profileID: profileID)
                }
                do {
                    let text = try String(contentsOf: composed, encoding: .utf8)
                    let scripted = try ClashTVOverrideScript.apply(script: source, toYAML: text, profileName: subscription.title)
                    try Data(scripted.utf8).write(to: work.scripted, options: .atomic)
                } catch {
                    throw Self.refusal(error)
                }
                composed = work.scripted
                checked = false
                ClashLogStore.shared.append("tv override script applied  bytes=\(source.utf8.count)", stream: .app)
            }
            sourceFile = composed
            userInfo = fetched.userInfo
            panelName = fetched.panelName
        }
         
         
         
        try Task.checkCancellation()

        return try await prepare(source: sourceFile, checked: checked, work: work, profileID: profileID,
                                 userInfo: userInfo, panelName: panelName, tunnelRunning: tunnelRunning,
                                 progress: progress)
    }

     
     
     
     
    struct WorkFiles {
        let directory: URL
        var source: URL { directory.appendingPathComponent("source.yaml") }
        var composed: URL { directory.appendingPathComponent("composed.yaml") }
        var scripted: URL { directory.appendingPathComponent("scripted.yaml") }
        var runtime: URL { directory.appendingPathComponent("runtime.yaml") }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    static func workFiles(container: URL) throws -> WorkFiles {
        let sources = container.appendingPathComponent("working/tv-sources", isDirectory: true)
        sweepLeftWork(sources)
        let directory = sources.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return WorkFiles(directory: directory)
    }

    private static let sweepLock = NSLock()
    nonisolated(unsafe) private static var swept: Set<String> = []

     
     
     
     
    private static func sweepLeftWork(_ sources: URL) {
        sweepLock.lock()
        defer { sweepLock.unlock() }
        guard swept.insert(sources.standardizedFileURL.path).inserted else { return }
        let left = (try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? []
        for directory in left { try? FileManager.default.removeItem(at: directory) }
    }

     
    private func prepare(sourceYAML: String, profileID: String, userInfo: String?, panelName: String?,
                         expected: ActiveConfigurationPointer? = nil, existingProxyDirectory: URL? = nil,
                         fetchesRuleSets: Bool? = nil, snapshots: [String: Data]? = nil,
                         progress: @escaping (Phase) -> Void) async throws -> Activation {
        let work = try Self.workFiles(container: container)
        defer { work.remove() }
        try Data(sourceYAML.utf8).write(to: work.source, options: .atomic)
        return try await prepare(source: work.source, checked: false, work: work, profileID: profileID,
                                 userInfo: userInfo, panelName: panelName, expected: expected,
                                 existingProxyDirectory: existingProxyDirectory, fetchesRuleSets: fetchesRuleSets,
                                 snapshots: snapshots, progress: progress)
    }

     
     
     
     
     
    func recoverRules(expected: ActiveConfigurationPointer,
                      tunnelHashes: [String: Set<String>]? = nil,
                      verify: (@MainActor ([String: String]) async throws -> Bool)? = nil) async throws -> Activation? {
        let store = try ConfigResourceStore(containerURL: container)
        guard try store.activeIdentity() == expected,
              let directory = store.providersDirectory(profileID: expected.profileID, revision: expected.revision),
              let record = ClashTVRuleRecovery.read(from: directory) else { return nil }
         
        let settings = try frozenSettings ?? IPStackSettings.load(from: defaults)
        try prepareEnvironment(settings: settings)
        let plan = try ConfigTransforms.planResources(mergedYAML: record.sourceYAML)
        var snapshots = try ClashTVRuleRecovery.snapshots(sourceYAML: record.sourceYAML, plan: plan,
                                                       container: container, profileID: expected.profileID,
                                                       tunnelHashes: tunnelHashes)
         
        for provider in plan.providers where provider.kind == "rule" {
            let key = ClashTVProviderMaterializer.resourceKey(for: provider)
            if snapshots[key] == nil, record.hashes[key] != nil,
               let data = try? Data(contentsOf: directory.appendingPathComponent(provider.path)) {
                snapshots[key] = data
            }
        }
        guard ClashTVRuleRecovery.hashes(snapshots) != record.hashes else { return nil }
        if let verify {
            let hashes = ClashTVRuleRecovery.hashes(snapshots)
            guard try await verify(hashes) else { return nil }
        }
        return try await prepare(sourceYAML: record.sourceYAML, profileID: expected.profileID,
                                 userInfo: nil, panelName: nil, expected: expected,
                                 existingProxyDirectory: directory, snapshots: snapshots, progress: { _ in })
    }

     
     
     
     
     
     
    func prepareLeftRuleSets(expected: ActiveConfigurationPointer) async throws -> Activation? {
        let store = try ConfigResourceStore(containerURL: container)
        guard try store.activeIdentity() == expected,
              let directory = store.providersDirectory(profileID: expected.profileID, revision: expected.revision),
              ClashTVProviderCatalog.read(from: directory)?.ruleSetsLeftToTheTunnel == true,
              let record = ClashTVRuleRecovery.read(from: directory) else { return nil }
        let settings = try frozenSettings ?? IPStackSettings.load(from: defaults)
        try prepareEnvironment(settings: settings)
        return try await prepare(sourceYAML: record.sourceYAML, profileID: expected.profileID,
                                 userInfo: nil, panelName: nil, expected: expected,
                                 existingProxyDirectory: directory, fetchesRuleSets: true, progress: { _ in })
    }

     
     
     
     
    private func prepare(source: URL, checked: Bool, work: WorkFiles, profileID: String,
                         userInfo: String?, panelName: String?,
                         expected: ActiveConfigurationPointer? = nil, existingProxyDirectory: URL? = nil,
                         fetchesRuleSets requestedFetch: Bool? = nil,
                         snapshots suppliedSnapshots: [String: Data]? = nil, tunnelRunning: Bool = false,
                         progress: @escaping (Phase) -> Void) async throws -> Activation {
         
         
         
        defer { AppCore.returnFreeMemory() }
        progress(.preparing)
        if !checked {
            do {
                try ConfigTransforms.validateSource(atPath: source)
            } catch {
                throw Self.refusal(error)
            }
        }
        let plan: RemoteResourcePlan
        do {
            plan = try ConfigTransforms.planResources(atPath: source)
        } catch {
            throw Self.refusal(error)
        }
        guard plan.errors.isEmpty else {
            throw PipelineError.planRejected(plan.errors.map { "\($0.field): \($0.reason)" })
        }
         
         
         
         
        var ageSecretKeys: [String: String] = [:]
        if plan.providers.contains(where: { $0.kind == "proxy" }) {
            do {
                ageSecretKeys = try ConfigTransforms.providerAgeSecretKeys(atPath: source)
            } catch {
                throw Self.refusal(error)
            }
        }

        let fetchesRuleSets = requestedFetch ?? (!inBackground && expected == nil)
         
         
         
         
        let skeleton = Result { try ClashTVRuleRecovery.skeleton(atPath: source) }
        let hasRuleSets = plan.providers.contains { $0.kind == "rule" }
         
         
         
         
         
         
         
        let keepsText = hasRuleSets && ClashTVRuleRecovery.holds(source)
        let sourceYAML = keepsText ? try String(contentsOf: source, encoding: .utf8) : ""
        let identities = hasRuleSets ? try ClashTVRuleRecovery.identities(
            sourceYAML: sourceYAML, plan: plan, container: container, profileID: profileID, skeleton: skeleton.get()) : [:]
         
         
         
        let snapshots = try suppliedSnapshots ?? (keepsText ? ClashTVRuleRecovery.snapshots(
            sourceYAML: sourceYAML, plan: plan, container: container, profileID: profileID, identities: identities) : [:])
         
         
         
         
         
        let record = keepsText
            ? try ClashTVRuleRecovery(sourceYAML: sourceYAML, hashes: ClashTVRuleRecovery.hashes(snapshots)).encoded()
            : nil
        var runtimeFile = source
        if keepsText {
            let confined = try ClashTVRuleRecovery.confinedSource(
                sourceYAML, plan: plan, container: container, profileID: profileID, identities: identities)
            if confined != sourceYAML {
                try Data(confined.utf8).write(to: work.runtime, options: .atomic)
                runtimeFile = work.runtime
            }
        }
        let store = try ConfigResourceStore(containerURL: container)
        let previousDirectory = try? store.activeProvidersDirectory()
        let previous = previousDirectory.flatMap { ClashTVProviderCatalog.read(from: $0) }
        let sourceSHA256 = try ClashTVRuleRecovery.sha256(ofFile: source)
         
         
         
         
        let identity = userAgent
        let providerUserAgent = ClientUserAgent.written(in: try? skeleton.get()) ?? identity
        let candidate = try store.beginCandidate(profileID: profileID)
        do {
            let materialized = try await ClashTVProviderMaterializer.materialize(
                plan: plan,
                candidate: candidate,
                session: session,
                userAgent: providerUserAgent,
                ageSecretKeys: ageSecretKeys,
                ruleSnapshots: snapshots,
                routeSetNames: ClashTVRuleRecovery.routeSetNames(plan: plan, skeleton: try? skeleton.get()),
                routeSeedDates: ClashTVRuleRecovery.tunnelCheckedAt(container: container),
                existingProxyDirectory: existingProxyDirectory,
                existingCatalog: existingProxyDirectory.flatMap { ClashTVProviderCatalog.read(from: $0) },
                tunnelRunning: tunnelRunning,
                 
                 
                 
                fetchesRuleSets: fetchesRuleSets,
                tunnelRuns: ClashTVRuleRecovery.tunnelRuns(container: container, plan: plan, identities: identities),
                 
                recordsLeftSets: record != nil && (expected == nil ? inBackground : previous?.ruleSetsLeftToTheTunnel == true),
                ruleFetchDeadline: ruleFetchDeadline,
                seedDirectory: ProviderSeeds.directory(workingDirectory: container.appendingPathComponent("working", isDirectory: true)),
                unusableAddresses: ClashTVProviderMaterializer.notices(plan, kind: "provider-url-unusable"),
                localProviders: ClashTVProviderMaterializer.localProviders(plan: plan, skeleton: try? skeleton.get()),
                previousProvidersDirectory: previousDirectory,
                sourceSHA256: sourceSHA256
            )
            try Task.checkCancellation()
            var finalYAML = try ConfigTransforms.finalize(
                atPath: runtimeFile,
                providerPaths: materialized.paths,
                providerReadPaths: materialized.readPaths,
                seeds: .init(fetchedAt: materialized.fetchedAt),
                nodeLibraryDirectory: Self.nodeLibraryDirectory(container: container),
                 
                 
                ruleIndexDirectory: Self.nodeLibraryDirectory(container: container)
            )
             
             
            try ConfigTransforms.carryGlobalUA(identity, into: &finalYAML)
            let ruleFacts = try ClashTVRuleFacts.of(publishedYAML: finalYAML)
            try ruleFacts?.write(to: candidate.stagingProvidersDirectory)
            if let record {
                try ClashTVRuleRecovery.write(record, to: candidate.stagingProvidersDirectory)
            }
            GeoSiteCompiler.prepare(finalYAML: finalYAML)
            GeoSiteCompiler.prepareRulePayloads(in: candidate.stagingProvidersDirectory, plan: plan,
                                                readPaths: materialized.seedPaths)
            GeoIPCompiler.prepare(finalYAML: finalYAML)
            GeoIPCompiler.prepareRulePayloads(
                in: candidate.stagingProvidersDirectory,
                plan: plan,
                geodataMode: GeoIPCompiler.geodataModeEnabled(in: finalYAML),
                readPaths: materialized.seedPaths
            )

             
             
            try Task.checkCancellation()
            try beforePublish?()
            progress(.publishing)
            do {
                if let expected {
                    _ = try store.publishAndActivateIfCurrentMatches(candidate, finalData: Data(finalYAML.utf8), expectedActive: expected)
                } else {
                    _ = try store.publishAndActivate(candidate, finalData: Data(finalYAML.utf8))
                }
            } catch {
                throw PipelineError.publishFailed(error.localizedDescription)
            }
             
             
            Self.pruneNodeLibraries(container: container)
            if expected == nil || fetchesRuleSets {
                stage(finalYAML, plan.providers.count, !inBackground)
            }
             
             
            return Activation(
                profileID: profileID,
                revision: candidate.revision,
                finalYAML: finalYAML,
                providerCount: plan.providers.count,
                warnings: materialized.warnings,
                userInfo: userInfo,
                panelName: panelName,
                catalog: materialized.catalog,
                ruleFacts: ruleFacts,
                publishedPath: store.providersDirectory(profileID: profileID, revision: candidate.revision)
                    .map { ClashTVRuleFacts.publishedPath(providersDirectory: $0) },
                changed: previous?.sourceSHA256 != sourceSHA256 || materialized.contentChanged
            )
        } catch {
            try? store.discard(candidate)
             
             
             
             
            Self.pruneNodeLibraries(container: container)
            throw error
        }
    }
}

 
 
struct ClashTVRuleRecovery: Codable {
    static let fileName = "tv-rule-source.json"
     
    static let maximumCacheBytes = 16 * 1024 * 1024
    let sourceYAML: String
    let hashes: [String: String]

    var hasUnexpandedRoutes: Bool {
        guard let plan = try? ConfigTransforms.planResources(mergedYAML: sourceYAML) else { return false }
        let names = Self.routeSetNames(plan: plan, skeleton: Self.skeleton(of: sourceYAML))
        return plan.providers.contains {
            names.contains($0.name) && hashes[ClashTVProviderMaterializer.resourceKey(for: $0)] == nil
        }
    }

     
     
     
    static let unreadSections = ["proxies", "proxy-groups", "rules"]

     
     
    static func skeleton(of sourceYAML: String) -> [String: Any]? {
        guard let json = try? ConfigTransforms.yamlToJSON(sourceYAML, omitting: unreadSections) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }

     
    static func skeleton(atPath path: URL) throws -> [String: Any] {
        let json = try ConfigTransforms.yamlToJSON(atPath: path, omitting: unreadSections)
        return try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
    }

     
     
     
    static func sha256(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var done = false
        while !done {
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { done = true; return }
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

     
     
    static func routeSetNames(sourceYAML: String, plan: RemoteResourcePlan) -> Set<String> {
        routeSetNames(plan: plan, skeleton: skeleton(of: sourceYAML))
    }

     
    static func routeSetNames(plan: RemoteResourcePlan, skeleton root: [String: Any]?) -> Set<String> {
        guard plan.providers.contains(where: { $0.kind == "rule" && $0.behavior == "ipcidr" }),
              let tun = root?["tun"] as? [String: Any] else { return [] }
        let names = Set((tun["route-address-set"] as? [String] ?? []) + (tun["route-exclude-address-set"] as? [String] ?? []))
        return Set(plan.providers.filter { $0.kind == "rule" && $0.behavior == "ipcidr" && names.contains($0.name) }.map(\.name))
    }

     
     
     
    static func holds(_ url: URL) -> Bool {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return bytes.map { $0 <= ConfigResourceStore.maximumCandidateResourceBytes } ?? false
    }

     
     
    func encoded() throws -> Data? {
        let data = try JSONEncoder().encode(self)
        guard data.count <= ConfigResourceStore.maximumCandidateResourceBytes else {
            ClashLogStore.shared.append("tv rule recovery not kept  bytes=\(data.count)", stream: .app, level: .warning)
            return nil
        }
        return data
    }

     
    static func write(_ record: Data, to directory: URL) throws {
        try record.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func read(from directory: URL) -> Self? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func hashes(_ snapshots: [String: Data]) -> [String: String] {
        snapshots.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }

    static func cacheURL(for provider: RemoteResourcePlan.Provider, sourceYAML: String,
                         container: URL, profileID: String) throws -> URL {
        try cacheURLs(sourceYAML: sourceYAML, plan: .init(providers: [provider]),
                      container: container, profileID: profileID)[ClashTVProviderMaterializer.resourceKey(for: provider)]!
    }

    static func cacheURLs(sourceYAML: String, plan: RemoteResourcePlan,
                          container: URL, profileID: String) throws -> [String: URL] {
        try identities(sourceYAML: sourceYAML, plan: plan, container: container, profileID: profileID).mapValues(\.cacheURL)
    }

     
     
    struct RuleIdentity: Equatable {
        let cacheURL: URL
         
        let requestKey: String?
    }

     
     
    static func identities(sourceYAML: String, plan: RemoteResourcePlan,
                           container: URL, profileID: String,
                           skeleton: [String: Any]? = nil) throws -> [String: RuleIdentity] {
        guard plan.providers.contains(where: { $0.kind == "rule" }) else { return [:] }
        let root: [String: Any]
        if let skeleton {
            root = skeleton
        } else {
            let json = try ConfigTransforms.yamlToJSON(sourceYAML, omitting: unreadSections)
            root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
        }
        var identities: [String: RuleIdentity] = [:]
        for provider in plan.providers where provider.kind == "rule" {
            let section = "rule-providers"
            var definition = (root[section] as? [String: [String: Any]])?[provider.name] ?? [:]
            let requestKey = requestKey(kind: provider.kind, definition: definition)
            definition.removeValue(forKey: "path")
             
             
            let identity: [String: Any] = ["profile": profileID, "kind": provider.kind,
                                         "name": provider.name, "definition": definition,
                                         "globalUA": root["global-ua"] ?? ""]
            let data = try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            identities[ClashTVProviderMaterializer.resourceKey(for: provider)] = RuleIdentity(
                cacheURL: container.appendingPathComponent("working/tv-rule-cache/\(hash)"), requestKey: requestKey)
        }
        return identities
    }

     
     
     
     
     
     
     
     
     
    static func requestKey(kind: String, definition: [String: Any]) -> String? {
        let fields: Set<String> = ["url", "proxy", "size-limit", "header", "age-secret-key"]
        guard !definition.keys.contains(where: { fields.contains($0.lowercased()) && !fields.contains($0) }) else { return nil }
        var digest = SHA256()
        func write(_ parts: [String]) {
            for part in parts {
                digest.update(data: Data(part.utf8))
                digest.update(data: Data([0]))
            }
        }
        func text(_ value: Any?) -> String? {
            switch value {
            case let string as String: string
            case let number as NSNumber: number.stringValue
            default: nil
            }
        }
        func plain(_ field: String) -> String?? {
            guard let value = definition[field] else { return .some("") }
            guard let string = value as? String else { return nil }
            return .some(string)
        }
        guard let url = plain("url"), let proxy = plain("proxy"), let age = plain("age-secret-key") else { return nil }
        var sizeLimit: Int64 = 0
        if let value = definition["size-limit"] {
            let written = text(value)?.trimmingCharacters(in: .whitespaces) ?? ""
             
             
            guard !written.isEmpty, written.allSatisfy(\.isASCII), written.allSatisfy(\.isNumber),
                  !(value is String && written.count > 1 && written.hasPrefix("0")),
                  let parsed = Int64(written) else { return nil }
            sizeLimit = parsed
        }
        write(["kind", kind, "url", url ?? "", "proxy", proxy ?? "", "size-limit", String(sizeLimit), "age", age ?? ""])
        guard let headers = definition["header"].map({ $0 as? [String: Any] }) ?? [:] else { return nil }
        for name in headers.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            let values: [String]
            if let one = headers[name] as? String {
                values = [one]
            } else if let many = headers[name] as? [Any], let strings = many as? [String] {
                values = strings
            } else {
                return nil
            }
            write(["header", name])
            write(values)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func confinedSource(_ source: String, plan: RemoteResourcePlan,
                               container: URL, profileID: String,
                               identities: [String: RuleIdentity]? = nil) throws -> String {
        var sections: [String: [String: [String: String]]] = [:]
        let urls = try identities?.mapValues(\.cacheURL)
            ?? cacheURLs(sourceYAML: source, plan: plan, container: container, profileID: profileID)
        for provider in plan.providers where provider.kind == "rule" {
            let section = "rule-providers"
            guard let url = urls[ClashTVProviderMaterializer.resourceKey(for: provider)] else { continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            sections[section, default: [:]][provider.name] = ["path": url.path]
        }
        guard !sections.isEmpty else { return source }
        let patch = try JSONSerialization.data(withJSONObject: ["patch": sections], options: [.sortedKeys])
        return try ConfigTransforms.mergeOverride(raw: source, overrideJSON: String(decoding: patch, as: UTF8.self))
    }

    static func snapshots(sourceYAML: String, plan: RemoteResourcePlan,
                          container: URL, profileID: String,
                          tunnelHashes: [String: Set<String>]? = nil,
                          identities: [String: RuleIdentity]? = nil) throws -> [String: Data] {
        var snapshots: [String: Data] = [:]
        let urls = try identities?.mapValues(\.cacheURL)
            ?? cacheURLs(sourceYAML: sourceYAML, plan: plan, container: container, profileID: profileID)
        for provider in plan.providers where provider.kind == "rule" {
            guard let url = urls[ClashTVProviderMaterializer.resourceKey(for: provider)] else { continue }
            let limit = provider.maximumBytes > 0
                ? Int(min(Int64(maximumCacheBytes), provider.maximumBytes)) : maximumCacheBytes
            guard let data = stableBytes(at: url, maximumBytes: limit) else { continue }
            if let tunnelHashes, tunnelHashes[provider.name]?.contains(sha256(data)) != true { continue }
             
            guard (try? ClashTVProviderMaterializer.coreInspector(provider.kind, provider.behavior, provider.format, data)) != nil else { continue }
            snapshots[ClashTVProviderMaterializer.resourceKey(for: provider)] = data
        }
        return snapshots
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

     
     
     
     
     
     
     
     
     
    static func tunnelContent(container: URL) -> [String: Set<String>] {
        var content: [String: Set<String>] = [:]
        for (name, entry) in runningRuleSets(container: container) {
            var hashes = Set<String>()
            if let source = entry.sourceSHA256, !source.isEmpty { hashes.insert(source) }
            if entry.result == "pendingApp", entry.pendingReason == "routes",
               let pending = entry.pendingSHA256, !pending.isEmpty {
                hashes.insert(pending)
            }
            if !hashes.isEmpty { content[name] = hashes }
        }
        return content
    }

     
     
     
     
     
     
     
     
    static func tunnelRuns(container: URL, plan: RemoteResourcePlan,
                           identities: [String: RuleIdentity]) -> Set<String> {
        guard let state = refreshState(container: container) else { return [] }
        let cache = container.appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(ClashProviderRefreshDirectoryName, isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        var runs = Set<String>()
        for provider in plan.providers where provider.kind == "rule" {
            let key = ClashTVProviderMaterializer.resourceKey(for: provider)
             
             
             
             
            guard let request = identities[key]?.requestKey, state.running?.providers?[key] == request,
                  let productKey = state.running?.productKeys?[key],
                  let entry = state.entries[request],
                  let source = entry.sourceSHA256, !source.isEmpty else { continue }
             
            func catalogForm(_ behavior: String?, _ format: String?) -> String {
                let format = (format ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                return (behavior ?? "").trimmingCharacters(in: .whitespaces).lowercased() + "\u{0}" + (format.isEmpty ? "yaml" : format)
            }
            let behavior = provider.behavior.trimmingCharacters(in: .whitespaces).lowercased()
            let format = provider.format.trimmingCharacters(in: .whitespaces).lowercased()
            let form = catalogForm(behavior, format)
             
             
             
             
             
             
             
             
             
             
             
             
            let compiled = ["domain", "ipcidr"].contains(behavior) && format != "mrs" ? "mapped"
                : behavior == "classical" && format != "mrs" ? "indexed" : nil
            guard let product = entry.products?[productKey] else { continue }
             
             
            let productForm = product.sourceForm.flatMap { $0.isEmpty ? nil : $0 } ?? catalogForm(product.behavior, product.format)
            guard product.sourceSHA256 == source, productForm == form,
                  let generation = product.generation, let main = product.entry else { continue }
            let directory = cache.appendingPathComponent(request).appendingPathComponent("products")
                .appendingPathComponent(productKey).appendingPathComponent(generation)
            let files = Set((product.files ?? []) + [main])
            guard files.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(main).path)[.size] as? NSNumber)?.int64Value
            let runnable = compiled == nil || product.variant == compiled || (size ?? .max) <= 1 << 20
            if runnable { runs.insert(key) }
        }
        return runs
    }

     
     
     
     
    static func tunnelCheckedAt(container: URL) -> [String: Int64] {
        runningRuleSets(container: container).compactMapValues { entry in
            entry.lastCheckedAt.flatMap { $0 > 0 ? $0 : nil }
        }
    }

     
     
    private static func runningRuleSets(container: URL) -> [String: RefreshState.Entry] {
        guard let state = refreshState(container: container), let running = state.running?.providers else { return [:] }
        var sets: [String: RefreshState.Entry] = [:]
        for (key, requestKey) in running where key.hasPrefix("rule:") {
            if let entry = state.entries[requestKey] { sets[String(key.dropFirst("rule:".count))] = entry }
        }
        return sets
    }

     
     
    private static func refreshState(container: URL) -> RefreshState? {
        let url = container.appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(ClashProviderRefreshDirectoryName, isDirectory: true)
            .appendingPathComponent(ClashProviderRefreshStateFileName)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(RefreshState.self, from: data), state.version == 2 else { return nil }
        return state
    }

     
    private struct RefreshState: Decodable {
        struct Running: Decodable {
            let providers: [String: String]?
            let productKeys: [String: String]?
        }
        struct Product: Decodable {
            let behavior: String?
            let format: String?
            let variant: String?
            let entry: String?
            let files: [String]?
            let generation: String?
            let sourceSHA256: String?
            let sourceForm: String?
        }
        struct Entry: Decodable {
            let products: [String: Product]?
            let result: String?
            let lastCheckedAt: Int64?
            let pendingReason: String?
            let sourceSHA256: String?
            let pendingSHA256: String?
        }
        let version: Int
        let running: Running?
        let entries: [String: Entry]
    }

     
     
    private static func stableBytes(at url: URL, maximumBytes: Int) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= maximumBytes else { return nil }
        guard let data = try? handle.read(upToCount: maximumBytes + 1),
              data.count == before.st_size else { return nil }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { return nil }
        return data
    }
}
