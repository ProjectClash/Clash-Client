import Clash
import ClashClientKit
import ClashClientUI
import CryptoKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum PublishedPresentation {
    static let fileName = "published-presentation.json"

     
     
     
    static var largeSourceBytes: Int { NodesInventoryProjection.wholeReadBytes }

     
     
     
     
     
     
     
     
    static func isLargeSource(fileAt url: URL) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else {
            return false
        }
        return size.intValue > largeSourceBytes
    }

    struct Record: Codable, Equatable {
        let revision: String
        let inputs: String
         
         
         
         
         
         
        var modeAsChosen: Bool?
    }

     
    struct Settings {
        var global: OverrideSpec
        var runtime: OverrideSpec
        var configScriptEnabled: Bool
        var configScriptBody: String
        var scripts: [ConfigScript]
        var udpFallback: String

         
        static func live() -> Settings {
            Settings(
                global: GlobalConfig.load(),
                runtime: FlClashRuntimeConfig.load(),
                configScriptEnabled: ScriptSettings.enabled(),
                configScriptBody: ScriptSettings.body(),
                scripts: ScriptLibrary.load(),
                udpFallback: String(describing: UDPFallbackSettings.policy())
            )
        }
    }

     
     
     
     
    static func buildFacts(of profile: Profile) -> Profile {
        var facts = profile
        facts.selectedMap = [:]
        facts.currentGroupName = nil
        facts.unfoldedGroups = nil
        facts.globalPickedByReader = nil
        facts.order = 0
        facts.activeRevision = nil
        facts.subscriptionInfo = nil
        facts.lastUpdatedAt = nil
        facts.subscriptionETag = nil
        facts.subscriptionLastModified = nil
        facts.providerDefinitionNotices = nil
        return facts
    }

     
     
    static func inputs(source: String, profile: Profile, settings: Settings) -> String? {
        inputs(sourcePrefix: sourcePrefix(source), profile: profile, settings: settings)
    }

     
     
     
    static func sourcePrefix(_ source: String) -> SHA256 {
        var hasher = SHA256()
        var text = source
        let length = text.utf8.count
        withUnsafeBytes(of: UInt64(length).bigEndian) { hasher.update(bufferPointer: $0) }
        text.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        return hasher
    }

     
     
    static func inputs(sourcePrefix: SHA256, profile: Profile, settings: Settings,
                       modeAsChosen: Bool = true) -> String? {
        var settings = settings
        if modeAsChosen { settings.runtime = runtimeWithModeAsChosen(settings.runtime) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
         
         
        let scripts = settings.scripts.sorted { $0.id < $1.id }
        guard let profileFacts = try? encoder.encode(buildFacts(of: profile)),
              let global = try? encoder.encode(settings.global),
              let runtime = try? encoder.encode(settings.runtime),
              let scriptLibrary = try? encoder.encode(scripts)
        else { return nil }
        var hasher = sourcePrefix
        func add(_ data: Data) {
            withUnsafeBytes(of: UInt64(data.count).bigEndian) { hasher.update(bufferPointer: $0) }
            hasher.update(data: data)
        }
        add(profileFacts)
        add(global)
        add(runtime)
        add(Data([settings.configScriptEnabled ? 1 : 0]))
        add(Data(settings.configScriptBody.utf8))
        add(scriptLibrary)
        add(Data(settings.udpFallback.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

     
     
     
     
    static func runtimeWithModeAsChosen(_ runtime: OverrideSpec) -> OverrideSpec {
        guard ClashTunnelOutboundMode.chosen(inPatchJSON: runtime.patchJSON) != nil else { return runtime }
        var patch = OverridePatch(patchJSON: runtime.patchJSON)
        patch.mode = "chosen"
        var counted = runtime
        counted.patchJSON = patch.patchJSON
        return counted
    }

     
     
    static func withModeChosen(_ text: String, runtime: OverrideSpec = FlClashRuntimeConfig.load()) -> String {
        ClashTunnelOutboundMode.chosen(inPatchJSON: runtime.patchJSON)
            .map { ClashTunnelOutboundMode.applying($0, to: text) } ?? text
    }

    static func url(profileID: String, workingDirectory: URL) -> URL {
        ProfileSourceStore.runnableURL(workingDirectory: workingDirectory, profileID: profileID)
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
    }

     
     
    static func record(_ pointer: ActiveConfigurationPointer, inputs: String?, workingDirectory: URL) {
        let file = url(profileID: pointer.profileID, workingDirectory: workingDirectory)
        guard let inputs,
              let data = try? JSONEncoder().encode(Record(revision: pointer.revision, inputs: inputs, modeAsChosen: true))
        else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read(profileID: String, workingDirectory: URL) -> Record? {
        guard let data = try? Data(contentsOf: url(profileID: profileID, workingDirectory: workingDirectory)) else {
            return nil
        }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

     
     
    static func isCurrent(
        _ pointer: ActiveConfigurationPointer,
        source: String,
        profile: Profile,
        workingDirectory: URL,
        settings: Settings = .live()
    ) -> Bool {
        isCurrent(pointer, sourcePrefix: sourcePrefix(source), profile: profile, workingDirectory: workingDirectory,
                  settings: settings)
    }

     
    static func isCurrent(
        _ pointer: ActiveConfigurationPointer,
        sourcePrefix: SHA256,
        profile: Profile,
        workingDirectory: URL,
        settings: Settings = .live()
    ) -> Bool {
        guard pointer.profileID == profile.id,
              let record = read(profileID: pointer.profileID, workingDirectory: workingDirectory),
              record.revision == pointer.revision,
              let now = inputs(sourcePrefix: sourcePrefix, profile: profile, settings: settings,
                               modeAsChosen: record.modeAsChosen == true)
        else { return false }
        return record.inputs == now
    }

     
     
    static func sourcePrefix(fileAt url: URL) -> SHA256? {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: UInt64(data.count).bigEndian) { hasher.update(bufferPointer: $0) }
        data.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher
    }

     
     
    static func currentText(
        of pointer: ActiveConfigurationPointer,
        store: ConfigResourceStore,
        source: String,
        profile: Profile,
        workingDirectory: URL,
        settings: Settings = .live()
    ) -> String? {
        currentText(of: pointer, store: store, sourcePrefix: sourcePrefix(source), profile: profile,
                    workingDirectory: workingDirectory, settings: settings)
    }

     
    static func currentText(
        of pointer: ActiveConfigurationPointer,
        store: ConfigResourceStore,
        sourcePrefix: SHA256,
        profile: Profile,
        workingDirectory: URL,
        settings: Settings = .live()
    ) -> String? {
        guard isCurrent(pointer, sourcePrefix: sourcePrefix, profile: profile, workingDirectory: workingDirectory,
                        settings: settings),
              let text = try? store.loadConfiguration(profileID: pointer.profileID, revision: pointer.revision).text,
              namedFilesArePresent(in: text)
        else { return nil }
         
         
        return withModeChosen(
            PublishedRulesAsWritten.restoring(text, profileID: pointer.profileID, revision: pointer.revision,
                                              workingDirectory: workingDirectory),
            runtime: settings.runtime)
    }

     
     
     
     
     
    static func namedFilesArePresent(in text: String) -> Bool {
        for path in [ConfigTransforms.nodeLibraryPath(in: text), ConfigTransforms.ruleIndexPath(in: text)] {
            if let path, !FileManager.default.fileExists(atPath: path) { return false }
        }
        return true
    }
}

 
 
 
 
 
 
 
 
 
 
enum PublishedRulesAsWritten {
    static let fileName = "published-rules.yaml"

    static func url(profileID: String, workingDirectory: URL) -> URL {
        PublishedPresentation.url(profileID: profileID, workingDirectory: workingDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
    }

     
     
     
     
     
     
     
    static func section(ofFinalized finalized: String, prepending before: [String]) -> String? {
        guard let section = section(ofFinalized: finalized) else { return nil }
        guard !before.isEmpty else { return section }
        guard let keyEnd = section.firstIndex(of: "\n") else { return nil }
        let keyLine = section[..<keyEnd]
         
        guard let colon = keyLine.firstIndex(of: ":") else { return nil }
        let value = keyLine[keyLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard value.isEmpty || value.hasPrefix("#") else { return nil }
        let rest = section[section.index(after: keyEnd)...]
         
         
        var indent = "  "
        var start = rest.startIndex
        while start < rest.endIndex {
            let end = rest[start...].firstIndex(of: "\n") ?? rest.endIndex
            let line = rest[start..<end]
            let content = line.drop { $0 == " " }
            if !content.isEmpty, !content.hasPrefix("#") {
                if content.hasPrefix("- ") || content == "-" { indent = String(repeating: " ", count: line.count - content.count) }
                break
            }
            start = end < rest.endIndex ? rest.index(after: end) : end
        }
        let head = before.map { indent + "- " + ModuleYAMLText.scalar($0) + "\n" }.joined()
        return String(keyLine) + "\n" + head + rest
    }

     
     
     
     
     
    static func section(ofFinalized finalized: String) -> String? {
        enum Read { case large, unreadable, section(String) }
        var text = finalized
        let read: Read = text.withUTF8 { bytes in
            if let range = TopLevelYAMLSections.sectionRange("rules", inBytes: bytes) {
                if range.count >= ConfigTransforms.ruleSectionCutFromBytes { return .large }
                 
                return TopLevelYAMLSections.section("rules", inBytes: bytes).map(Read.section) ?? .unreadable
            }
            return .unreadable
        }
        switch read {
        case .large:
            return nil
        case .section(let section):
            return section.hasSuffix("\n") ? section : section + "\n"
        case .unreadable:
             
             
             
            guard finalized.utf8.count < ConfigTransforms.ruleSectionCutFromBytes,
                  let root = try? ConfigTransforms.foundationRoot(ofYAML: finalized, omitting: ["proxies"]),
                  let rules = root["rules"] as? [Any], !rules.isEmpty,
                  let json = try? JSONSerialization.data(withJSONObject: ["rules": rules]),
                  let yaml = try? ConfigTransforms.jsonToYAML(String(decoding: json, as: UTF8.self))
            else { return nil }
            return yaml.hasSuffix("\n") ? yaml : yaml + "\n"
        }
    }

     
     
    static func record(_ pointer: ActiveConfigurationPointer, section: String?, workingDirectory: URL) {
        let file = url(profileID: pointer.profileID, workingDirectory: workingDirectory)
        guard let section else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((header(pointer.revision) + section).utf8)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

     
     
    static func recorded(profileID: String, revision: String, workingDirectory: URL) -> String? {
        guard let data = try? Data(contentsOf: url(profileID: profileID, workingDirectory: workingDirectory)),
              let text = String(data: data, encoding: .utf8), text.hasPrefix(header(revision)) else { return nil }
        return String(text.dropFirst(header(revision).count))
    }

     
     
     
    static func restoring(_ text: String, profileID: String, revision: String, workingDirectory: URL) -> String {
        guard ConfigTransforms.ruleIndexPath(in: text) != nil,
              let section = recorded(profileID: profileID, revision: revision, workingDirectory: workingDirectory),
              let cut = TopLevelYAMLSections.cutting([ConfigTransforms.ruleIndexKey], from: text),
              let restored = cut.replacingSection(ConfigTransforms.ruleIndexKey, with: section).splicing(into: cut.rest)
        else { return text }
        return restored
    }

    private static func header(_ revision: String) -> String { "# revision: \(revision)\n" }
}

extension PublishedPresentation {
    nonisolated(unsafe) private static var verdicts: [String: Bool] = [:]
    private static let verdictLock = NSLock()

     
     
     
     
     
     
     
     
     
    static func opensWhole(_ text: String, revision: String, sourceWritesNodes: Bool,
                           resourceMapJSON: String, selectionsJSON: String,
                           setupContainer: URL? = AppCoreSetup.applicationContainer) -> Bool {
        if let known = verdict(for: revision) { return known }
        guard let setupContainer else { return true }
        let verdict = measuresWhole(text, sourceWritesNodes: sourceWritesNodes, resourceMapJSON: resourceMapJSON,
                                    selectionsJSON: selectionsJSON, container: setupContainer)
        verdictLock.lock()
        verdicts[revision] = verdict
        verdictLock.unlock()
        if !verdict {
            ClashLogStore.shared.append("offline pages build from the source  reason=publication \(revision) does not open whole",
                                       stream: .app, level: .warning)
        }
        return verdict
    }

     
    static func verdict(for revision: String) -> Bool? {
        verdictLock.lock()
        defer { verdictLock.unlock() }
        return verdicts[revision]
    }

    private static func measuresWhole(_ text: String, sourceWritesNodes written: Bool, resourceMapJSON: String,
                                      selectionsJSON: String, container: URL) -> Bool {
        do {
            let summary = try AppCoreSetup.withConfiguration(container: container) { () throws -> NodeSummary in
                OfflineProxyCatalogLoader.noteOpening(text, resourceMapJSON: resourceMapJSON, selectionsJSON: selectionsJSON,
                                                      holder: "probe", key: revision(of: text))
                var error: NSError?
                guard let catalog = AppCore.openNodeCatalog(text, resourceMapJSON, selectionsJSON, &error) else {
                    throw error ?? NodePageSourceError.unavailable
                }
                defer { catalog.close() }
                return try Data(catalog.summaryJSON().utf8).decoded(NodeSummary.self)
            }
            ClashLogStore.shared.append("offline catalog probe  nodes=\(summary.nodes) sourceWritesNodes=\(written)", stream: .app)
            return summary.nodes > 0 || !written
        } catch {
            ClashLogStore.shared.append("offline catalog probe  refused=\((error as NSError).localizedDescription)",
                                       stream: .app, level: .warning)
            return false
        }
    }

    private static func revision(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func resetVerdictsForTesting() {
        verdictLock.lock()
        verdicts = [:]
        verdictLock.unlock()
    }

     
     
     
    static func textForPages(
        source: String,
        profile: Profile,
        store: ConfigResourceStore?,
        workingDirectory: URL?
    ) -> String? {
        guard source.utf8.count > largeSourceBytes else { return nil }
        return textForPages(sourcePrefix: { sourcePrefix(source) }, profile: profile, store: store,
                            workingDirectory: workingDirectory)
    }

     
     
    static func textForPages(
        sourceAt url: URL,
        profile: Profile,
        store: ConfigResourceStore?,
        workingDirectory: URL?
    ) -> String? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > largeSourceBytes else { return nil }
        return textForPages(sourcePrefix: { sourcePrefix(fileAt: url) }, profile: profile, store: store,
                            workingDirectory: workingDirectory)
    }

    private static func textForPages(
        sourcePrefix: () -> SHA256?,
        profile: Profile,
        store: ConfigResourceStore?,
        workingDirectory: URL?
    ) -> String? {
        guard let store, let workingDirectory,
              let pointer = try? store.activeIdentity(), pointer.profileID == profile.id,
              let prefix = sourcePrefix(),
              let text = currentText(of: pointer, store: store, sourcePrefix: prefix, profile: profile,
                                     workingDirectory: workingDirectory)
        else { return nil }
         
        if verdict(for: pointer.revision) == nil {
            _ = OfflineProxyCatalogLoader.input(containerURL: workingDirectory.deletingLastPathComponent(),
                                                preferredProfileID: profile.id)
        }
        return verdict(for: pointer.revision) == false ? nil : text
    }
}

extension LargeConfigurationDisplay {
     
     
    static func phrase(_ told: Told, locale: Locale = AppPreferences.language().locale) -> String {
        func counted(_ format: String, _ value: Int?) -> String {
            guard let value else { return ClashCopy.string(for: .copy("Not shown"), locale: locale) }
            return ClashCopy.format(format, locale: locale, ClashCopy.count(value, locale: locale))
        }
        switch told {
        case .nodes(let value): return counted("%@ nodes, not shown", value)
        case .rules(let value): return counted("%@ rules, not shown", value)
        case .groups(let value): return counted("%@ groups, not shown", value)
        case .entries(let value): return counted("%@ entries, not shown", value)
        }
    }

     
     
     
     
    static func text(for profile: Profile, sourceAt url: URL?, container: URL?) -> String? {
        let containerPath = container?.path
        if let container, let revision = profile.activeRevision,
           let published = (try? ConfigResourceStore(containerURL: container)
               .loadConfiguration(profileID: profile.id, revision: revision))?.text {
             
             
            let nodes = ConfigTransforms.nodeLibraryPath(in: published) == nil ? nil
                : ModuleRouteHiding.nodeCount(
                    OfflineProxyCatalogLoader.publishedNodeCount(profileID: profile.id, containerURL: container),
                    of: ActiveConfigurationPointer(profileID: profile.id, revision: revision),
                    locations: ModuleLocations(container: container))
                    ?? url.flatMap { ConfigurationSections.entryCount(ofSection: "proxies", inFileAt: $0) }
            let rules = ConfigTransforms.ruleIndexPath(in: published) == nil ? nil
                : PublishedRules.summary(ofPublishedText: published)?.written
            return text(of: PublishedPresentation.withModeChosen(published), nodeCount: nodes, ruleCount: rules,
                        containerPath: containerPath,
                        telling: { phrase($0) })
        }
        guard let url else { return nil }
        return text(ofFileAt: url, containerPath: containerPath, telling: { phrase($0) })
    }
}
