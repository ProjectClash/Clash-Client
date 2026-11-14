import ClashClientKit
import Foundation

 
 
 
 
enum ModuleEngineStatus: Equatable, Sendable {
     
     
    case ready
     
     
     
     
    case untrusted(ModuleUntrustedReason)
     
     
    case withheld(ModuleWithheldReason)
     
     
    case portsFailed(Set<UInt16>)
     
     
    case unavailable
}

 
 
enum ModuleWithheldReason: Equatable, Sendable {
     
    case certificateMissing
     
     
    case certificateUnusable
     
     
    case stoppedForMemory
     
     
     
     
    case engineUnavailable

    var degradeReason: ModuleDegradeReason {
        switch self {
        case .certificateMissing: return .certificateMissing
        case .certificateUnusable: return .certificateUnusable
        case .stoppedForMemory: return .stoppedForMemory
        case .engineUnavailable: return .engineUnavailable
        }
    }
}

 
 
enum ModuleUntrustedReason: Equatable, Sendable {
     
    case certificateNotTrusted

    var degradeReason: ModuleDegradeReason {
        switch self {
        case .certificateNotTrusted: return .certificateNotTrusted
        }
    }
}

 
 
 
 
 
 
 
 
 
enum ModuleCertEntry {
    static let candidates = ["198.19.255.254", "198.18.255.254", "192.0.2.254", "198.51.100.254", "203.0.113.254"]
}

struct ModuleActivationInput: Equatable, Sendable {
    var manifest: ModuleGlobalManifest
    var engine: ModuleEngineStatus
     
     
     
     
     
    var geodataDirectory: URL? = nil
     
     
     
    var unreachableCertEntryIPs: Set<String> = []
     
     
     
     
    var ruleIndexDirectory: URL? = nil
     
     
     
     
    var knownPolicies: Set<String>? = nil
     
     
     
     
    var lanPermitted = true
     
     
     
    var logLevelSetByApp = false
     
     
     
    var modeSetByApp = false
     
     
     
    var listenerKeysSetByApp: Set<String> = []
     
     
     
    var settingsRefused: String? = nil
     
     
    var platform: ModulePlatform = .current
     
     
     
     
     
     
    var ruleSetCopiesDirectory: URL? = nil

     
     
     
     
     
     
    static func loadPublished(locations: ModuleLocations?, engine: ModuleEngineStatus) -> ModuleActivationInput? {
         
        guard let locations,
              let data = try? Data(contentsOf: locations.globalManifest),
              let manifest = try? ModuleJSON.decoder().decode(ModuleGlobalManifest.self, from: data),
              manifest.schemaVersion == ModuleGlobalManifest.currentSchemaVersion,
              !manifest.modules.isEmpty else { return nil }
        var input = ModuleActivationInput(manifest: manifest, engine: engine,
                                           geodataDirectory: locations.container.appendingPathComponent("working", isDirectory: true))
        input.ruleSetCopiesDirectory = locations.ruleSetCopiesDirectory
        input.lanPermitted = LocalNetworkPermission.isPermitted(UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite))
        return input
    }
}

 
 
enum ModuleDegradeReason: Equatable, Sendable {
    case engineUnavailable
     
    case certificateNotTrusted
     
    case certificateMissing
     
    case certificateUnusable
     
    case stoppedForMemory
    case portsTaken
    case noCertificateAddress
    case groupsNotAdjustable
     
    case sectionNotAdjustable(String)
     
     
    case alreadyPublished
     
    case moduleRulesLeftOut
     
     
    case moduleEntriesLeftOut
     
     
     
    case moduleSettingsLeftOut
     
     
    case engineNameTaken
     
    case notApplied(AuthoredText)
     
     
     
     
    case snifferWrittenOff(String)
     
     
     
    case snifferNotCompleted

     
     
     
     
     
    var authoredText: AuthoredText {
        switch self {
        case .engineUnavailable:
             
             
             
            return .app("HTTPS Decryption is not available yet, so only the rules in your modules work.")
        case .certificateNotTrusted:
             
             
            return .app("Once the certificate is installed and trusted, the rewrites and scripts in your modules work on HTTPS sites.")
        case .certificateMissing:
            return .app("Create and install the certificate so your modules work fully.")
        case .certificateUnusable:
            return .app("The certificate can't be used right now; the rules in your modules still work.")
        case .stoppedForMemory:
             
             
            return ModuleEngineInsight.Copy.rewritesAndScriptsOnHold
        case .portsTaken:
             
             
             
             
            return .app("HTTPS Decryption is getting ready; it will start working by itself.")
        case .noCertificateAddress:
             
             
             
            return .app("The certificate page can't open with the current configuration.")
         
         
         
         
         
        case .groupsNotAdjustable, .sectionNotAdjustable:
            return .app("Rewrites and scripts can't work with how this configuration is written, so only the rules in your modules work; Clash can't change this.")
        case .alreadyPublished:
            return .app("This configuration was exported from Clash, so only the rules in your modules work; import the original configuration to use rewrites and scripts too.")
        case .moduleRulesLeftOut:
             
             
            return .app("Some rules don't fit the current configuration, so they were skipped.")
        case .moduleEntriesLeftOut:
            return .app("Some module lines could not be read, so they were skipped.")
        case .moduleSettingsLeftOut:
             
             
            return .app("Some module settings can't be used with this configuration and were skipped; a module's details list them.")
        case .engineNameTaken:
             
             
            return .app("A proxy in the current configuration is named “%@”, so HTTPS Decryption is off; rename that proxy to turn HTTPS Decryption back on.", arguments: [ModuleActivationStep.engineProxyName])
        case .snifferWrittenOff(let keys):
             
             
             
             
             
             
             
            let names = Self.snifferSwitchNames(keys)
             
             
            guard !names.isEmpty else {
                return .app(Self.snifferWrittenOffInSectionSentence, arguments: [Self.snifferSwitchName])
            }
            return .app(Self.snifferWrittenOffSentence(count: names.count), arguments: names)
        case .snifferNotCompleted:
             
             
             
             
             
             
             
             
            return .app("Clash couldn't add what modules need to your configuration's “%@”, so they may not work in some apps; choose On in its menu, not Follow profile, and save.",
                        arguments: [Self.snifferSwitchName])
        case .notApplied(let text):
             
            return ModuleStoredSentence.current(text)
        }
    }

     
     
     
     
    static let refusedWithModules = ModuleDegradeReason.notApplied(
        .app("Modules cannot be used with this configuration, so it runs without them."))

     
     
     
     
     
     
    static let snifferSwitchName = "Sniffer"
    static let snifferSwitchNames: [(key: String, name: String)] = [
        ("enable", snifferSwitchName),
        ("force-dns-mapping", "Sniff DNS-mapped traffic"),
        ("parse-pure-ip", "Sniff pure-IP traffic"),
    ]

     
     
    static func snifferSwitchNames(_ keys: String) -> [String] {
        let needed = Set(snifferKeys(keys))
        return snifferSwitchNames.filter { needed.contains($0.key) }.map(\.name)
    }

     
     
     
    static func snifferKeys(_ keys: String) -> [String] {
        let written = Set(keys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return snifferSwitchNames.map(\.key).filter(written.contains)
    }

     
     
     
     
     
    static func macSnifferWrittenOffSentence(count: Int) -> String {
        switch count {
        case ...1:
            return "Your configuration turns off “%@”, so modules may not work in some apps; turn it on to fix this."
        case 2:
            return "Your configuration turns off “%@” and “%@”, so modules may not work in some apps; turn them on to fix this."
        default:
            return "Your configuration turns off “%@”, “%@” and “%@”, so modules may not work in some apps; turn them on to fix this."
        }
    }
    static let macSnifferWrittenOffInSectionSentence =
        "Your configuration turns off a setting modules need in “%@”, so they may not work in some apps; turn it on there to fix this."
    static let macSnifferNotCompletedSentence =
        "Clash couldn't add what modules need to your configuration, so they may not work in some apps; turn on “%@”, or if it's already on, turn it off and back on."

     
     
     
    static let snifferWrittenOffInSectionSentence =
        "Your configuration turns off a setting modules need in “%@”, so they may not work in some apps; set it to On there to fix this."

     
     
    static func snifferWrittenOffSentence(count: Int) -> String {
        switch count {
        case ...1:
            return "Your configuration turns off “%@”, so modules may not work in some apps; set it to On to fix this."
        case 2:
            return "Your configuration turns off “%@” and “%@”, so modules may not work in some apps; set them to On to fix this."
        default:
            return "Your configuration turns off “%@”, “%@” and “%@”, so modules may not work in some apps; set them to On to fix this."
        }
    }
}

 
 
 
 
enum ModulePublishPath: CaseIterable, Hashable, Sendable {
     
     
    case fromSourceWithIndex
     
     
    case fromSourceWithoutIndex
     
     
    case republishWithIndex
     
     
     
    case republishWithoutIndex

    init(publishedText: Bool, ruleIndex: Bool) {
        switch (publishedText, ruleIndex) {
        case (false, true): self = .fromSourceWithIndex
        case (false, false): self = .fromSourceWithoutIndex
        case (true, true): self = .republishWithIndex
        case (true, false): self = .republishWithoutIndex
        }
    }

     
    var carriesPrependRules: Bool { self != .republishWithoutIndex }
}

extension ModuleDegradeReason {
     
     
     
     
    static let exportedWithoutIndex = ModuleDegradeReason.notApplied(
        .app("This configuration was exported from Clash, so modules cannot take effect."))
}

 
 
 
struct ModuleRuleSetHandover: Equatable {
     
     
     
    var definitions: [String: OrderedJSON] = [:]
     
     
     
    var leftOut: [(name: String, reference: String, reason: ModuleIgnoredReason)] = []

    var names: Set<String> { Set(definitions.keys) }

    static func == (a: ModuleRuleSetHandover, b: ModuleRuleSetHandover) -> Bool {
        a.definitions == b.definitions && a.leftOut.map { "\($0.name) \($0.reference) \($0.reason)" } == b.leftOut.map { "\($0.name) \($0.reference) \($0.reason)" }
    }
}

 
 
 
 
struct ModulePrependedRules: Equatable {
     
    var lines: [String] = []
     
     
     
    var skipped: [ModuleIgnoredEntry] = []
     
     
    var policies: Set<String> = []
     
     
    var defaulted: [String: String] = [:]
}

 
 
struct ModuleActivationRecord: Codable, Equatable, Sendable {
     
     
    let engineProxyName: String
    let listenerName: String
    let listen: String
    let port: UInt16
     
    let userListenerCount: Int
    let snifferInjected: Bool
}

extension ModuleLocations {
     
     
    var activationRecord: URL { container.appendingPathComponent("working/adblock/activation.json") }
}

 
 
 
 
 
 
struct ModulePublicationRecord: Codable, Equatable, Sendable {
    let profileID: String
    let revision: String
     
     
     
     
    let manifestSHA256: String?
     
    let engine: ModuleActivationRecord?
     
     
     
     
     
    var heldEngine: String? = nil
     
     
     
    var composition: Int? = nil

    var pointer: ActiveConfigurationPointer { ActiveConfigurationPointer(profileID: profileID, revision: revision) }

     
     
    var hiddenEngineName: String? { engine?.engineProxyName ?? heldEngine }

     
     
    static func load(locations: ModuleLocations?) -> ModulePublicationRecord? {
        guard let locations, let data = try? Data(contentsOf: locations.activationRecord) else { return nil }
        return try? ModuleJSON.decoder().decode(ModulePublicationRecord.self, from: data)
    }

     
     
     
    static func store(_ record: ModulePublicationRecord?, locations: ModuleLocations) {
         
         
        if let production = ModuleLocations.production,
           ModuleStore.normalized(locations.container) == ModuleStore.normalized(production.container) {
            ModuleRouteHiding.note(engineName: record?.hiddenEngineName)
        }
        let url = locations.activationRecord
        guard let record, record.manifestSHA256 != nil || record.engine != nil || record.heldEngine != nil,
              let data = try? ModuleJSON.encoder().encode(record) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

     
     
    static func manifestDigest(locations: ModuleLocations) -> String? {
        guard let data = try? Data(contentsOf: locations.globalManifest) else { return nil }
        return ModuleJSON.sha256(data)
    }

     
     
     
     
     
     
     
    static func staleComposition(locations: ModuleLocations,
                                 inUse: ActiveConfigurationPointer?) -> ModuleStaleComposition? {
        guard let inUse else { return nil }
        let record = load(locations: locations)
        if let record, record.pointer != inUse { return nil }
        let now = manifestDigest(locations: locations)
         
         
         
        if let record, record.engine != nil, record.composition != ModuleInjection.composition {
            return ModuleStaleComposition(pointer: inUse, manifestSHA256: now)
        }
        guard record?.manifestSHA256 != now else { return nil }
        return ModuleStaleComposition(pointer: inUse, manifestSHA256: now)
    }
}

 
 
struct ModuleStaleComposition: Equatable, Sendable {
    let pointer: ActiveConfigurationPointer
    let manifestSHA256: String?
}

extension ModuleActivationRecord {
     
    static func load(locations: ModuleLocations?) -> ModuleActivationRecord? {
        ModulePublicationRecord.load(locations: locations)?.engine
    }

     
     
     
     
    static func load(locations: ModuleLocations?, publishedAs ran: ActiveConfigurationPointer?) -> ModuleActivationRecord? {
        guard let ran, let record = ModulePublicationRecord.load(locations: locations), record.pointer == ran else { return nil }
        return record.engine
    }
}

 
 
enum ModuleDisclosure: Equatable, Sendable {
     
     
     
     
     
     
     
     
     
    case originRulesDoNotApply

     
     
     
     
     
    var authoredText: AuthoredText? {
        switch self {
        case .originRulesDoNotApply: return nil
        }
    }
}

struct ModuleActivationOutcome: Equatable {
    var text: String
    var degradedBecause: [ModuleDegradeReason]
     
    var notApplied: AuthoredText?
     
     
    var portsInUse: Set<UInt16>
     
     
     
    var needsNewPorts: Bool
     
    var record: ModuleActivationRecord?
     
     
    var reinjectCredentials: ModuleReinjectCredentials?
     
     
     
     
    var engineProxyCredentials: ModuleEngineProxyCredentials? = nil
     
    var certEntryIP: String?
     
     
     
     
    var certEntryIPNeedsConfirming: Bool
     
    var logLine: String?
     
     
     
    var injectedRules: [String] = []
     
    var disclosures: [ModuleDisclosure] = []
     
     
     
     
    var prependRules: [String]? = nil
     
    var publishPath: ModulePublishPath? = nil
     
     
     
     
     
    var ruleSets: ModuleRuleSetHandover? = nil
     
     
     
    var skipped: [ModuleIgnoredEntry] = []
     
    var inEffect: [ModuleSettingInEffect] = []
     
     
    var notes: [ModuleLineNote] = []
     
     
    var moduleLogLevel: String? = nil
     
    var carriesSettings = false
     
     
     
    var changes: [ModuleChange] = []
     
     
     
     
    var engineAssignment: ModuleEngineAssignment? = nil

    var engineInjected: Bool { record != nil }

     
    var handover: ModuleFinalizeHandover { ModuleFinalizeHandover(prependRules: prependRules, ruleSets: ruleSets) }
}

 
 
 
struct ModuleFinalizeHandover: Equatable {
    var prependRules: [String]? = nil
    var ruleSets: ModuleRuleSetHandover? = nil
}

enum ModuleActivationStep {
     
     
    static let engineProxyName = ModuleRuntimeNames.current.engineProxy
    static let reinjectListenerName = ModuleRuntimeNames.current.reinjectListener
     
     
    static let defaultFakeIPRange = "198.18.0.1/16"
     
     
    static let heldChanges: [String: ModuleChange.Key] = [
        "log-level": .logLevel, "mode": .mode,
        "allow-lan": .lanSharing, "port": .httpPort, "socks-port": .socksPort, "mixed-port": .mixedPort,
    ]



    struct IPv4Prefix: Equatable, Sendable {
        let address: UInt32
        let length: Int

        init?(_ text: String) {
            let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = parts.first, let address = ModuleActivationStep.ipv4(String(first)) else { return nil }
            let length = parts.count == 2 ? Int(parts[1]) : 32
            guard let length, (0...32).contains(length) else { return nil }
            self.address = address
            self.length = length
        }

        init(address: UInt32, length: Int) {
            self.address = address
            self.length = length
        }

        func contains(_ other: UInt32) -> Bool {
            let mask: UInt32 = length == 0 ? 0 : ~UInt32(0) << UInt32(32 - length)
            return address & mask == other & mask
        }
    }

     
     
    struct ConfigFacts: Equatable {
         
        var readable = true
         
        var declaredPorts: Set<UInt16> = []
         
        var listenerCount = 0
         
         
        var fakeIPRange: IPv4Prefix? = IPv4Prefix(ModuleActivationStep.defaultFakeIPRange)
         
         
        var tunAddress = IPv4Prefix(address: 0xC612_0001, length: 30)
         
         
        var fakeIPRanges: [String] = [ModuleActivationStep.defaultFakeIPRange]
         
         
        var routeAddresses: [IPv4Prefix] = []
        var routeExcludeAddresses: [IPv4Prefix] = []
         
         
         
        var routeSetsDeclared = false
         
        var geodataMode = false
         
        var namesANodeLibrary = false
         
        var namesARuleIndex = false
    }

    static func ipv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }), let byte = UInt8(part) else { return nil }
            value = value << 8 | UInt32(byte)
        }
        return value
    }

     

     
    static let factKeys: Set<String> = [
        "port", "socks-port", "mixed-port", "redir-port", "tproxy-port", "external-controller", "external-controller-tls",
        "ss-config", "vmess-config", "listeners", "tunnels", "tuic-server", "dns", "tun", "geodata-mode", "sniffer",
        "x-clash-node-library", "x-clash-rule-index",
    ]

     
     
     
     
     
     
    private static func factsRoot(of yaml: String) -> [String: Any]? {
        let mark = "\u{FEFF}"
        var body = yaml.hasPrefix(mark) ? String(yaml.dropFirst()) : yaml
        if let keys = TopLevelYAMLSections.keyLines(of: body) {
            let wanted: String = body.withUTF8 { bytes in
                var out: [UInt8] = []
                for (index, line) in keys.enumerated() where factKeys.contains(line.key) {
                    let end = index + 1 < keys.count ? keys[index + 1].offset : bytes.count
                    out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[line.offset..<end]))
                    if out.last != UInt8(ascii: "\n") { out.append(UInt8(ascii: "\n")) }
                }
                return String(decoding: out, as: UTF8.self)
            }
            if wanted.isEmpty { return [:] }
             
            if TopLevelYAMLSections.cutting(factKeys, from: wanted) != nil,
               let json = try? ConfigTransforms.yamlToJSON(wanted, omitting: []),
               let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                return root
            }
        }
        let omitted = ["proxies", "rules", "rule-providers", "proxy-providers", "proxy-groups", "sub-rules"]
        return (try? ConfigTransforms.foundationRoot(ofYAML: yaml, omitting: omitted)) ?? nil
    }

     
     
    static func facts(of yaml: String) -> ConfigFacts {
        var facts = ConfigFacts()
        guard let root = factsRoot(of: yaml) else {
            facts.readable = false
            return facts
        }
        facts.namesANodeLibrary = root["x-clash-node-library"] != nil
        facts.namesARuleIndex = root[ConfigTransforms.ruleIndexKey] != nil
        func declare(_ value: Any?) {
            facts.declaredPorts.formUnion(ports(value).filter { $0 != 0 })
        }
        for key in ["port", "socks-port", "mixed-port", "redir-port", "tproxy-port", "external-controller", "external-controller-tls"] {
            declare(root[key])
        }
         
        for key in ["ss-config", "vmess-config"] {
            if let text = root[key] as? String, let at = text.lastIndex(of: "@") { declare(String(text[text.index(after: at)...])) }
        }
        let listeners = root["listeners"] as? [Any] ?? []
        facts.listenerCount = listeners.count
        for listener in listeners {
            declare((listener as? [String: Any])?["port"])
        }
         
        for tunnel in root["tunnels"] as? [Any] ?? [] {
            if let text = tunnel as? String {
                let fields = text.split(separator: ",", omittingEmptySubsequences: false)
                if fields.count >= 2 { declare(String(fields[1])) }
            } else {
                declare((tunnel as? [String: Any])?["address"])
            }
        }
        declare((root["tuic-server"] as? [String: Any])?["listen"])
        let dns = root["dns"] as? [String: Any] ?? [:]
        declare(dns["listen"])

         
         
        if let written = dns["fake-ip-range"] {
            let text = (written as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if text.isEmpty {
                facts.fakeIPRange = nil
                facts.fakeIPRanges = []
            } else if let prefix = IPv4Prefix(text) {
                facts.fakeIPRange = prefix
                facts.fakeIPRanges = [text]
            }
        }
        if let prefix = facts.fakeIPRange {
            facts.tunAddress = IPv4Prefix(address: prefix.address, length: 30)
        }
        if let six = (dns["fake-ip-range6"] as? String)?.trimmingCharacters(in: .whitespaces), !six.isEmpty {
            facts.fakeIPRanges.append(six)
        }
        if let tun = root["tun"] as? [String: Any] {
            for key in ["route-address", "inet4-route-address"] {
                facts.routeAddresses += (tun[key] as? [Any] ?? []).compactMap { ($0 as? String).flatMap(IPv4Prefix.init) }
            }
            for key in ["route-exclude-address", "inet4-route-exclude-address"] {
                facts.routeExcludeAddresses += (tun[key] as? [Any] ?? []).compactMap { ($0 as? String).flatMap(IPv4Prefix.init) }
            }
            facts.routeSetsDeclared = ["route-address-set", "route-exclude-address-set"].contains { !((tun[$0] as? [Any]) ?? []).isEmpty }
        }
        facts.geodataMode = (root["geodata-mode"] as? Bool) ?? false
        return facts
    }

     
     
     
     
     
    static func ports(_ value: Any?) -> [UInt16] {
        if let number = value as? NSNumber { return UInt16(exactly: number.intValue).map { [$0] } ?? [] }
        guard let text = value as? String else { return [] }
        let written = text.split(separator: ":").last.map(String.init) ?? text
        var out: [UInt16] = []
        for item in written.split(whereSeparator: { $0 == "," || $0 == "/" }) {
            let bounds = item.split(separator: "-", maxSplits: 1).map { UInt16($0.trimmingCharacters(in: .whitespaces)) }
            guard let low = bounds.first ?? nil else { continue }
            let high = bounds.count == 2 ? (bounds[1] ?? low) : low
             
             
            out.append(contentsOf: min(low, high)...max(low, high))
        }
        return out
    }

     
     
     
     
     
     
    static func certEntryIP(for facts: ConfigFacts, excluding: Set<String> = []) -> String? {
        ModuleCertEntry.candidates.first { !excluding.contains($0) && serves($0, facts) }
    }

     
     
     
    static func certEntryIP(_ ip: String, reachableIn finalized: String) -> Bool {
        let read = facts(of: finalized)
        return read.readable && serves(ip, read)
    }

     
     
     
     
     
    static func unreachableCertEntryIPs(in finalized: String) -> Set<String> {
        let read = facts(of: finalized)
        return Set(ModuleCertEntry.candidates.filter { !read.readable || !serves($0, read) })
    }

    private static func serves(_ text: String, _ facts: ConfigFacts) -> Bool {
        guard let address = ipv4(text) else { return false }
        if facts.fakeIPRange?.contains(address) == true || facts.tunAddress.contains(address) { return false }
        if !facts.routeAddresses.isEmpty, !facts.routeAddresses.contains(where: { $0.contains(address) }) { return false }
        return !facts.routeExcludeAddresses.contains { $0.contains(address) }
    }

     

     
     
     
     
    static let originRuleTypes = [
        "SOURCE-APP-SIGNING-ID", "SOURCE-APP-TEAM-ID", "PROCESS-NAME", "PROCESS-PATH", "PROCESS-NAME-REGEX",
        "PROCESS-PATH-REGEX", "PROCESS-NAME-WILDCARD", "PROCESS-PATH-WILDCARD", "UID", "SRC-GEOIP", "SRC-IP-ASN",
        "SRC-IP-CIDR", "SRC-IP-SUFFIX", "SRC-PORT", "IN-PORT", "IN-TYPE", "IN-USER", "IN-NAME", "DSCP",
    ]

     
     
     
     
     
    static let addressRuleTypes = ["IP-CIDR", "IP-CIDR6", "IP-SUFFIX", "IP-ASN", "GEOIP"]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func originRuleTypes(in yaml: String) -> [String] {
        var text = yaml
        var found = [Bool](repeating: false, count: scanTypes.count)
        text.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return }
            let count = bytes.count
            let types = scanTypes
            let byFirst = scanTypesByFirstByte
            let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), dash = UInt8(ascii: "-"), comma = UInt8(ascii: ",")
            let quote = UInt8(ascii: "\""), apostrophe = UInt8(ascii: "'"), hash = UInt8(ascii: "#"), open = UInt8(ascii: "(")
            let close = UInt8(ascii: ")")
            let noResolve = Array("no-resolve".utf8)
            let source = Array("src".utf8)
             
             
            func field(_ from: Int, _ stop: Int) -> (text: String, end: Int) {
                var finish = from
                while finish < stop, base[finish] != comma { finish += 1 }
                var first = from, last = finish
                while first < last, base[first] == space || base[first] == tab { first += 1 }
                while last > first, [space, tab, quote, apostrophe].contains(base[last - 1]) { last -= 1 }
                return (String(decoding: UnsafeBufferPointer(start: base + first, count: last - first), as: UTF8.self), finish)
            }
             
            func hasSource(_ after: Int, _ stop: Int) -> Bool {
                guard stop - after >= source.count, memmem(base + after, stop - after, source, source.count) != nil else { return false }
                var at = field(after + 1, stop).end
                while at < stop {
                    let next = field(at + 1, stop)
                    if next.text == "src" { return true }
                    at = next.end
                }
                return false
            }
            func check(_ at: Int, _ end: Int, member: Bool) {
                for index in byFirst[Int(base[at])] where !found[index] {
                    let type = types[index]
                    var after = at + type.bytes.count
                    guard after < end, memcmp(base + at, type.bytes, type.bytes.count) == 0 else { continue }
                    while after < end, base[after] == space || base[after] == tab { after += 1 }
                    guard after < end, base[after] == comma else { continue }
                    if type.kind != .origin {
                         
                         
                        let stop = member ? memchr(base + after, Int32(close), end - after)
                            .map { UnsafeRawPointer(base).distance(to: UnsafeRawPointer($0)) } ?? end : end
                        let sourced = hasSource(after, stop)
                        if type.kind == .source {
                            guard sourced else { continue }
                        } else {
                            guard !sourced, stop - after >= noResolve.count,
                                  memmem(base + after, stop - after, noResolve, noResolve.count) != nil,
                                  !isPrivateDestination(type.name, field(after + 1, stop).text) else { continue }
                        }
                    }
                    found[index] = true
                }
            }
            var line = 0
            while line < count {
                let end = memchr(base + line, 10, count - line).map { UnsafeRawPointer(base).distance(to: UnsafeRawPointer($0)) } ?? count
                var at = line
                while at < end, base[at] == space || base[at] == tab { at += 1 }
                if at < end, base[at] == dash {
                    at += 1
                    while at < end, base[at] == space || base[at] == tab { at += 1 }
                }
                if at < end, base[at] == quote || base[at] == apostrophe { at += 1 }
                if at < end, base[at] != hash {
                    check(at, end, member: false)
                     
                    let first = base[at]
                    if first == UInt8(ascii: "A") || first == UInt8(ascii: "O") || first == UInt8(ascii: "N") || first == UInt8(ascii: "S"),
                       logicWords.contains(where: { at + $0.count <= end && memcmp(base + at, $0, $0.count) == 0 }) {
                        var from = at
                        while from < end, let hit = memchr(base + from, Int32(open), end - from) {
                            var position = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit)) + 1
                            while position < end, base[position] == space || base[position] == tab { position += 1 }
                            if position < end { check(position, end, member: true) }
                            from = position
                        }
                    }
                }
                line = end + 1
            }
        }
        return scanTypes.indices.filter { found[$0] }.map { index in
            let type = scanTypes[index]
            switch type.kind {
            case .origin: return type.name
            case .noResolve: return type.name + #" no-resolve"#
            case .source: return type.name + #" src"#
            }
        }
    }

     
    private enum ScanKind { case origin, noResolve, source }

    private static let scanTypes: [(name: String, bytes: [UInt8], kind: ScanKind)] =
        originRuleTypes.map { ($0, Array($0.utf8), .origin) }
        + addressRuleTypes.map { ($0, Array($0.utf8), .noResolve) }
        + addressRuleTypes.map { ($0, Array($0.utf8), .source) }

     
     
     
     
     
    private static let privateIPv4: [IPv4Prefix] = ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
                                                    "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4"]
        .compactMap(IPv4Prefix.init)
    private static let privateIPv6: [(bytes: [UInt8], length: Int)] = [("::", 128), ("::1", 128), ("fc00::", 7), ("fe80::", 10), ("ff00::", 8)]
        .compactMap { address, length in ipv6Bytes(address).map { ($0, length) } }

    private static func ipv6Bytes(_ text: String) -> [UInt8]? {
        guard ModuleIPLiteral(text)?.isIPv6 == true else { return nil }
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

     
     
     
    static func isPrivateDestination(_ type: String, _ payload: String) -> Bool {
        switch type {
        case "GEOIP":
            return ["private", "lan"].contains(payload.lowercased())
        case "IP-CIDR", "IP-CIDR6":
            let parts = payload.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let length = Int(parts[1]) else { return false }
            if let prefix = IPv4Prefix(payload), prefix.length == length {
                return privateIPv4.contains { $0.length <= prefix.length && $0.contains(prefix.address) }
            }
            guard (0...128).contains(length), let bytes = ipv6Bytes(parts[0]) else { return false }
            return privateIPv6.contains { range in
                guard range.length <= length else { return false }
                let whole = range.length / 8, rest = range.length % 8
                if bytes[..<whole] != range.bytes[..<whole] { return false }
                guard rest > 0 else { return true }
                let mask = UInt8(0xFF) << UInt8(8 - rest)
                return bytes[whole] & mask == range.bytes[whole] & mask
            }
        default:
            return false
        }
    }
     
    private static let scanTypesByFirstByte: [[Int]] = {
        var table = [[Int]](repeating: [], count: 256)
        for (index, type) in scanTypes.enumerated() { table[Int(type.bytes[0])].append(index) }
        return table
    }()
    private static let logicWords = ["AND", "OR", "NOT", "SUB-RULE"].map { Array($0.utf8) }

     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func readBack(_ finalized: String, outcome: ModuleActivationOutcome) -> String? {
        let expected = outcome.injectedRules
        guard !expected.isEmpty || outcome.record != nil else { return nil }
        var text = finalized
        let sections: (rules: String?, listeners: String?, sniffer: String?) = text.withUTF8 { bytes in
            func string(_ range: Range<Int>) -> String {
                String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
            }
            func lineEnd(_ start: Int) -> Int {
                var end = start
                while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
                return end
            }
             
            func keyLine(_ key: String) -> Int? {
                let needle = Array((key + ":").utf8)
                guard let base = bytes.baseAddress else { return nil }
                var from = 0
                while from + needle.count <= bytes.count {
                    guard let hit = needle.withUnsafeBytes({ memmem(base + from, bytes.count - from, $0.baseAddress, needle.count) })
                    else { return nil }
                    let at = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
                    let after = at + needle.count
                    if at == 0 || bytes[at - 1] == UInt8(ascii: "\n"),
                       after == bytes.count || [UInt8(ascii: " "), UInt8(ascii: "\r"), UInt8(ascii: "\n")].contains(bytes[after]) {
                        return at
                    }
                    from = at + 1
                }
                return nil
            }
             
             
             
            func section(_ key: String, items: Int? = nil) -> String? {
                guard let start = keyLine(key) else { return nil }
                var line = lineEnd(start) + 1
                var itemIndent: Int?
                var seen = 0
                while line < bytes.count {
                    let end = lineEnd(line)
                    var first = line
                    while first < end, bytes[first] == UInt8(ascii: " ") { first += 1 }
                    if first == line, first < end,
                       ![UInt8(ascii: "-"), UInt8(ascii: "#"), UInt8(ascii: "\r")].contains(bytes[first]) { break }
                    if let items, first < end, bytes[first] == UInt8(ascii: "-"),
                       first + 1 == end || [UInt8(ascii: " "), UInt8(ascii: "\r")].contains(bytes[first + 1]) {
                        let indent = first - line
                        if itemIndent == nil { itemIndent = indent }
                        if indent == itemIndent {
                            seen += 1
                            if seen > items { break }
                        }
                    }
                    line = end + 1
                }
                return string(start..<min(line, bytes.count))
            }
            return (expected.isEmpty ? nil : section("rules", items: expected.count),
                    outcome.record == nil ? nil : section("listeners"),
                    outcome.record == nil ? nil : section("sniffer"))
        }
        func value(_ yaml: String, _ key: String) -> Any? {
            guard let json = try? ConfigTransforms.yamlToJSON(yaml, omitting: []),
                  let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
            return root[key]
        }
        if !expected.isEmpty {
            let first: [String]
            if let rules = sections.rules {
                let got = (value(rules, "rules") as? [Any]) ?? []
                first = got.prefix(expected.count).map { ($0 as? String) ?? String(describing: $0) }
            } else if ConfigTransforms.ruleIndexPath(in: finalized) != nil {
                 
                 
                 
                do {
                    guard let catalog = try PublishedRules.open(publishedText: finalized) else {
                        return #"its rule index could not be read"#
                    }
                    defer { catalog.close() }
                    first = try catalog.rules(ofTypes: [], most: expected.count).map(\.rule)
                } catch {
                    return "its rule index could not be read: \(error.localizedDescription)"
                }
            } else {
                return #"the published configuration has no rules section"#
            }
            guard first == expected else {
                return "its first rules read back as \(first.map(\.debugDescription)), not \(expected.map(\.debugDescription))"
            }
        }
        if let record = outcome.record {
            let listeners = sections.listeners.flatMap { value($0, "listeners") as? [Any] } ?? []
            let found = listeners.contains { listener in
                guard let fields = listener as? [String: Any] else { return false }
                return fields["name"] as? String == record.listenerName && (fields["port"] as? NSNumber)?.intValue == Int(record.port)
            }
            guard found else { return "its listeners do not hold \(record.listenerName) on \(record.port)" }
            if record.snifferInjected {
                let sniffer = sections.sniffer.flatMap { value($0, "sniffer") as? [String: Any] }
                guard sniffer?["enable"] as? Bool == true else { return #"its sniffer is not the one modules added"# }
            } else if sections.sniffer == nil {
                 
                 
                return #"it has no sniffer, and modules added none because it took one to be there"#
            }
        }
        return nil
    }

     

     
     
     
    typealias RuleCheck = (_ line: String, _ contextJSON: String) throws -> String?

     
     
    static let kernelRuleCheck: RuleCheck = { line, context in
        let item = String(decoding: try JSONSerialization.data(withJSONObject: line, options: [.fragmentsAllowed]), as: UTF8.self)
        return try ConfigurationTextEditing.check(kind: "rule", itemJSON: item, contextJSON: context)
    }

     
     
    static func askedNames(_ rules: [ModuleGlobalManifest.Rule]) -> Set<String> {
        var asked = Set<String>()
        for rule in rules {
            if case .named(let written) = rule.policy { asked.insert(written) }
            if let choice = rule.choice { asked.insert(choice) }
        }
        return asked
    }

     
     
     
     
    private static func resolved(_ rules: [ModuleGlobalManifest.Rule], catalog: () -> ModulePolicyCatalog)
        -> (lines: [(line: String, written: String, target: String)], skipped: [ModuleIgnoredEntry], policies: Set<String>,
            defaulted: [String: String]) {
        var lines: [(line: String, written: String, target: String)] = []
        var skipped: [ModuleIgnoredEntry] = []
        var policies: Set<String> = []
        var defaulted: [String: String] = [:]
        var seen = Set<String>()
        var read: ModulePolicyCatalog?
        for rule in rules {
             
            let written = rule.rendered(rule.policy.kernelName ?? rule.policy.writtenName ?? "PROXY")
            var name = rule.policy.kernelName
            if name == nil {
                if read == nil { read = catalog() }
                name = read?.resolve(rule.policy, choice: rule.choice)
                if let name, ModuleRuleMapping.kernelPolicy(name) != name { policies.insert(name) }
                if case .named(let named) = rule.policy, let name, name != named { defaulted[named] = name }
            }
            guard let name else {
                skipped.append(ModuleIgnoredEntry(text: written, reason: .policyNotFound(rule.policy.writtenName ?? "PROXY"),
                                                   origin: moduleRuleOrigin))
                continue
            }
            let line = rule.rendered(name)
            if seen.insert(line).inserted { lines.append((line, written, name)) }
        }
        return (lines, skipped, policies, defaulted)
    }

     
     
    private static let uidRule = try! NSRegularExpression(pattern: #"(?:^|\()\s*UID\s*,"#, options: [.caseInsensitive])

     
     
     
    static func engineRoute(in rules: [String], engine name: String) -> String? {
        rules.last { $0.hasPrefix("AND,") && $0.hasSuffix("," + name) && $0.contains("(NETWORK,TCP)") }
    }

     
     
     
     
    static func isEnginesOwnRule(_ rule: String, engine name: String) -> Bool {
        guard rule.hasPrefix("AND,((IN-TYPE,TUN),") else { return false }
        return rule.hasSuffix("," + name)
            || (rule.hasPrefix("AND,((IN-TYPE,TUN),(NETWORK,UDP),(DST-PORT,443),") && rule.hasSuffix("),REJECT"))
    }

     
     
    static func enginesOwnRules(in rules: [String], engine name: String) -> [String] {
        rules.filter { isEnginesOwnRule($0, engine: name) }
    }

    static func carriesUID(_ line: String) -> Bool {
        uidRule.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

     
     
    private static let processRule = try! NSRegularExpression(
        pattern: #"(?:^|\()\s*(?:"# + ModuleRuleMapping.processTypes.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")\s*,"#,
        options: [.caseInsensitive])

    static func carriesProcessRule(_ line: String) -> Bool {
        processRule.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

     
     
    static let moduleRuleOrigin = ModuleLineOrigin(section: "Rule", line: 0)

     
     
     
     
     
     
     
     
     
    static func ruleSetHandover(_ providers: [ModuleGlobalManifest.RuleProvider], copies: URL?) -> ModuleRuleSetHandover {
        var out = ModuleRuleSetHandover()
        for provider in providers where ModuleRuleSetSyntax.isModuleProviderName(provider.name) {
            guard case .object(var pairs)? = try? OrderedJSON.parse(provider.definition) else { continue }
            let reference = provider.reference ?? provider.name
             
             
            guard !provider.overBudget else {
                out.leftOut.append((provider.name, reference, .tooManyRuleSets))
                continue
            }
            switch pairs.first(where: { $0.key == "type" })?.value {
            case .string("file")?:
                guard let file = provider.copy, !file.isEmpty, !file.contains("/"), let copy = copies?.appendingPathComponent(file),
                      FileManager.default.fileExists(atPath: copy.path) else {
                    out.leftOut.append((provider.name, reference, .ruleSetNotDownloadedYet))
                    continue
                }
                pairs.removeAll { $0.key == "path" }
                pairs.append(("path", .string(copy.path)))
            case .string("inline")?:
                break
            default:
                 
                 
                out.leftOut.append((provider.name, reference, .ruleSetNotDownloadedYet))
                continue
            }
            out.definitions[provider.name] = .object(pairs)
        }
        return out
    }

     
     
    static func namesASetLeftOut(_ rule: ModuleGlobalManifest.Rule, _ handover: ModuleRuleSetHandover) -> Bool {
        guard rule.head.hasPrefix("RULE-SET,") else { return false }
        let name = String(rule.head.dropFirst("RULE-SET,".count))
        return ModuleRuleSetSyntax.isModuleProviderName(name) && !handover.names.contains(name)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func prependedRules(_ rules: [ModuleGlobalManifest.Rule], catalog: ModulePolicyCatalog,
                               check: RuleCheck, firstPlace: Int = 0,
                               platform: ModulePlatform = .current) -> ModulePrependedRules {
        let resolution = resolved(rules, catalog: { catalog })
        var out = ModulePrependedRules(lines: [], skipped: resolution.skipped, policies: resolution.policies,
                                        defaulted: resolution.defaulted)
        guard !resolution.lines.isEmpty else { return out }
        var contexts: [String: String] = [:]
        for item in resolution.lines {
             
             
            guard ModuleYAMLText.isOneLine(item.line), ModuleRuleMapping.isWithinTheBounds(item.line) else {
                out.skipped.append(ModuleIgnoredEntry(text: item.written, reason: .unreadableLine, origin: moduleRuleOrigin))
                continue
            }
             
             
             
             
             
             
            if platform != .mac, carriesUID(item.line) || carriesProcessRule(item.line) {
                out.skipped.append(ModuleIgnoredEntry(text: item.written, reason: .platformCannot(.processRules), origin: moduleRuleOrigin))
                continue
            }
            let context: String
            if let made = contexts[item.target] {
                context = made
            } else {
                context = catalog.checkContext(forTarget: item.target)
                contexts[item.target] = context
            }
            let refusal: String?
            do {
                refusal = try check(item.line, ModulePolicyCatalog.checkContext(context, place: firstPlace + out.lines.count))
            } catch {
                 
                 
                refusal = error.localizedDescription
            }
            if let refusal {
                out.skipped.append(ModuleIgnoredEntry(text: item.written, reason: .ruleRefused(refusal), origin: moduleRuleOrigin))
            } else {
                out.lines.append(item.line)
            }
        }
        return out
    }

     
     
     
     
    static func renderedModuleRules(_ rules: [ModuleGlobalManifest.Rule], in yaml: String)
        -> (lines: [String], policies: Set<String>, leftOut: Int, defaulted: [String: String]) {
        let resolution = resolved(rules, catalog: { ModulePolicyCatalog.read(yaml, naming: askedNames(rules)) })
        return (resolution.lines.map(\.line), resolution.policies, resolution.skipped.count, resolution.defaulted)
    }

     

     
    enum GeodataKind: String, CaseIterable, Sendable {
        case geoIP = "GeoIP"
        case geoSite = "GeoSite"
        case asn = "ASN"
    }

     
     
     
    private static let geodataToken = try! NSRegularExpression(
        pattern: #"(?:^|\()\s*(GEOIP|SRC-GEOIP|GEOSITE|IP-ASN|SRC-IP-ASN)\s*,\s*([^,()]*)"#, options: [.caseInsensitive])

     
     
    static func geodataNeeded(by rule: String) -> Set<GeodataKind> {
        let lowered = rule.lowercased()
        guard lowered.contains("geo") || lowered.contains("ip-a") else { return [] }
        var kinds = Set<GeodataKind>()
        let range = NSRange(rule.startIndex..., in: rule)
        for match in geodataToken.matches(in: rule, range: range) {
            guard let typeRange = Range(match.range(at: 1), in: rule) else { continue }
            let payload = Range(match.range(at: 2), in: rule).map { rule[$0].trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            switch rule[typeRange].uppercased() {
            case "GEOIP", "SRC-GEOIP": if payload != "lan" { kinds.insert(.geoIP) }
            case "GEOSITE": kinds.insert(.geoSite)
            default: kinds.insert(.asn)
            }
        }
        return kinds
    }

     
     
     
     
     
    static func geodataPlanDocument(for rules: [String], in yaml: String) throws -> String {
        let keys: Set<String> = ["geox-url", "geodata-mode"]
        var text = yaml
        var root: [String: Any] = [:]
        if let cut = text.withUTF8({ TopLevelYAMLSections.sections(keys, inBytes: $0) }), cut.refused.isEmpty {
            let written = keys.sorted().compactMap { cut.texts[$0] }.map { $0.hasSuffix("\n") ? $0 : $0 + "\n" }.joined()
            if !written.isEmpty {
                let json = try ConfigTransforms.yamlToJSON(written, omitting: [])
                root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
            }
        } else if let whole = try ConfigTransforms.foundationRoot(
            ofYAML: yaml, omitting: ["proxies", "rules", "rule-providers", "proxy-providers", "proxy-groups", "sub-rules"]) {
            for key in keys { root[key] = whole[key] }
        }
        root["rules"] = rules
        return String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), as: UTF8.self)
    }

     
     
     
    static func geodataStaged(_ kind: GeodataKind, geodataMode: Bool, in directory: URL?) -> Bool {
        guard let directory,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return false }
        let names: Set<String>
        switch kind {
        case .geoIP: names = geodataMode ? ["geoip.dat"] : ["country.mmdb", "geoip.db", "geoip.metadb"]
        case .geoSite: names = ["geosite.dat"]
        case .asn: names = ["asn.mmdb"]
        }
        return entries.contains { entry in
            names.contains(entry.lastPathComponent.lowercased())
                && (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

     

     
     
     
     
     
    static func prepare(_ runtimeYAML: String, input: ModuleActivationInput?,
                        priority: TaskPriority? = nil) async -> ModuleActivationOutcome {
        let priority = priority ?? Task.currentPriority


        var outcome = await Task.detached(priority: priority) { apply(to: runtimeYAML, input: input) }.value


        return outcome
    }

     
     
     
     
    static func namesAPublication(_ yaml: String, facts: () -> ConfigFacts) -> Bool {
        guard ConfigTransforms.mentions(yaml, ConfigTransforms.nodeLibraryKey)
                || ConfigTransforms.mentions(yaml, ConfigTransforms.ruleIndexKey) else { return false }
        let read = facts()
        return read.namesANodeLibrary || read.namesARuleIndex
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func strippingAnEarlierEngine(_ yaml: String)
        -> (text: String, removed: [String], heldInALibrary: Bool, engineName: String) {
        var read: ConfigFacts?
        func readFacts() -> ConfigFacts {
            if let read { return read }
            let made = facts(of: yaml)
            read = made
            return made
        }
        guard namesAPublication(yaml, facts: readFacts),
              let root = (try? ConfigTransforms.foundationRoot(ofYAML: yaml, omitting: ["proxy-groups", "rule-providers",
                                                                                        "proxy-providers", "sub-rules"])) ?? nil
        else { return (yaml, [], false, engineProxyName) }
        func fields(_ item: Any) -> [String: Any] { item as? [String: Any] ?? [:] }
        func hasValue(_ value: Any?) -> Bool {
            switch value {
            case let text as String: return !text.isEmpty
            case let list as [Any]: return !list.isEmpty
            case let map as [String: Any]: return !map.isEmpty
            default: return false
            }
        }
         
         
        var generation = ModuleRuntimeNames.current
        func isReinjectListener(_ item: Any) -> Bool {
            let listener = fields(item)
            guard let name = listener["name"] as? String, let named = ModuleRuntimeNames.reinjectGeneration(of: name),
                  listener["type"] as? String == "mixed", listener["listen"] as? String == "127.0.0.1",
                  hasValue(listener["users"]) else { return false }
            generation = named
            return true
        }
        func isEngineProxy(_ item: Any) -> Bool {
            let proxy = fields(item)
            guard let name = proxy["name"] as? String, ModuleRuntimeNames.engineGeneration(of: name) != nil else { return false }
            return proxy["type"] as? String == "http"
                && proxy["server"] as? String == "127.0.0.1" && hasValue(proxy["username"]) && hasValue(proxy["password"])
        }
        func isEngineRule(_ item: Any) -> Bool {
            guard let rule = item as? String else { return false }
            return ModuleRuntimeNames.all.contains { isEnginesOwnRule(rule, engine: $0.engineProxy) }
        }
        var deletions: [(path: [ConfigurationTextPathStep], said: String)] = []
        for (key, isInjected) in [("listeners", isReinjectListener), ("proxies", isEngineProxy), ("rules", isEngineRule),
                                  ("x-clash-every-mode-rules", isEngineRule)] {
            let items = root[key] as? [Any] ?? []
            for index in items.indices.reversed() where isInjected(items[index]) {
                deletions.append(([.key(key), .index(index)], key))
            }
        }
        if let hosts = root["hosts"] as? [String: Any], let alias = hosts[ModuleInjection.certEntryHostName] as? String,
           ModuleYAMLText.isIPv4Literal(alias) {
            deletions.append(([.key("hosts"), .key(ModuleInjection.certEntryHostName)], "hosts"))
        }
        var text = yaml
        var removed: [String] = []
        var removedProxies: Set<Int> = []
        for deletion in deletions {
            guard let edited = try? ConfigurationTextEditing.editAlone(text, at: deletion.path, .delete) else { continue }
            text = edited
            removed.append(deletion.said)
            if deletion.said == "proxies", case .index(let index)? = deletion.path.last { removedProxies.insert(index) }
        }
         
         
         
         
         
        if !removedProxies.isEmpty, let library = root["x-clash-node-library"] as? [String: Any],
           let places = (library["inline-at"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.intValue }),
           places.count == (root["proxies"] as? [Any])?.count {
            let kept = places.enumerated().filter { !removedProxies.contains($0.offset) }.map { item in
                item.element - removedProxies.filter { $0 < item.offset }.count
            }
            let path: [ConfigurationTextPathStep] = [.key("x-clash-node-library"), .key("inline-at")]
            let edit: ConfigurationTextEdit = kept.isEmpty ? .delete : .set(json: "[" + kept.map(String.init).joined(separator: ",") + "]")
            if let edited = try? ConfigurationTextEditing.editAlone(text, at: path, edit) {
                text = edited
                removed.append("x-clash-node-library")
            }
        }
         
         
         
         
        let held = removed.contains("listeners") && !removed.contains("proxies") && readFacts().namesANodeLibrary
        return (text, removed, held, generation.engineProxy)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func apply(to runtimeYAML: String, input: ModuleActivationInput?,
                      check: RuleCheck = kernelRuleCheck) -> ModuleActivationOutcome {


        let off = ModuleActivationOutcome(text: runtimeYAML, degradedBecause: [], notApplied: nil, portsInUse: [],
                                           needsNewPorts: false, record: nil, reinjectCredentials: nil,
                                           certEntryIP: nil, certEntryIPNeedsConfirming: false, logLine: nil)
        guard let input, !input.manifest.modules.isEmpty else { return off }
        let manifest = input.manifest
         
         
        let decryption = manifest.enabled
         
         
         
        let settings = input.settingsRefused == nil ? manifest.settings ?? [] : []
        guard decryption || !manifest.routingRules.isEmpty || !settings.isEmpty || input.settingsRefused != nil else { return off }
         
         
         
        let leadingRules = manifest.routingRules.filter { !$0.appended }
        let appendedRules = manifest.routingRules.filter(\.appended)
        var degraded: [ModuleDegradeReason] = []
        var notes: [String] = []
        var portsInUse: Set<UInt16> = []
        var needsNewPorts = false
        var moduleRules: [String] = []
         
        var policiesGiven: Set<String> = []
         
         
        var entriesLeftOut: [String] = []

         
        var skippedLines: [ModuleIgnoredEntry] = []
         
        var settledInEffect: [ModuleSettingInEffect] = []
        var settledNotes: [ModuleLineNote] = []
        var settledLogLevel: String?
        var settlesSettings = false
         
         
        var heldByClash: [ModuleLineOrigin: Set<ModuleChange.Key>] = [:]

         
        var cachedFacts: ConfigFacts?
        func facts() -> ConfigFacts {
            if let cachedFacts { return cachedFacts }
            let read = Self.facts(of: runtimeYAML)
            cachedFacts = read
            return read
        }
         
        let path = ModulePublishPath(publishedText: namesAPublication(runtimeYAML, facts: facts),
                                      ruleIndex: input.ruleIndexDirectory != nil)
         
         
        let ruleSets = ruleSetHandover(manifest.ruleProviders ?? [], copies: input.ruleSetCopiesDirectory)
        for set in ruleSets.leftOut {
            skippedLines.append(ModuleIgnoredEntry(text: set.reference, reason: set.reason, origin: moduleRuleOrigin))
            notes.append(#"module rule set "# + set.name + #" left out: "# + set.reason.authoredText.englishText)
        }

        var certIP: String?
        var confirmCertIP = false
         
        var decrypts = false
         
         
         
        let mitmHosts = decryption ? manifest.mitmHosts : ModuleHostList([String]())
        let forceHTTPEngineHosts = decryption ? manifest.forceHTTPEngineHosts
            : ModuleHostList([String](), standardPort: ModuleHostList.forceHTTPStandardPort)
         
         
         
        func finish(_ text: String, _ reasons: [ModuleDegradeReason], record: ModuleActivationRecord? = nil,
                    credentials: ModuleReinjectCredentials? = nil, notApplied: AuthoredText? = nil,
                    rules: [String] = [], engineCredentials: ModuleEngineProxyCredentials? = nil,
                    hostSets: [ModuleEngineHostSet] = []) -> ModuleActivationOutcome {
            var reasons = notApplied.map { [ModuleDegradeReason.notApplied($0)] } ?? reasons
            var text = text
             
             
            let engineRules = record.map { enginesOwnRules(in: rules, engine: $0.engineProxyName) } ?? []
            if notApplied == nil, !settings.isEmpty || !engineRules.isEmpty {
                let settled = settle(text, engineRules: engineRules)
                text = settled.text
                reasons += settled.reasons.filter { !reasons.contains($0) }
            }
            if notApplied == nil, let refusal = input.settingsRefused {
                 
                 
                 
                for module in manifest.settings ?? [] {
                    guard let origin = module.edits.first?.origin ?? module.hosts.first?.origin
                            ?? module.deviceSettings.first?.origin ?? module.changes.first?.origin else { continue }
                    skippedLines.append(ModuleIgnoredEntry(text: module.moduleID, reason: .settingsRefused(refusal), origin: origin,
                                                            moduleID: module.moduleID))
                }
                notes.append(#"module settings left out: the configuration was refused with them in it: "# + refusal)
                if !reasons.contains(.moduleSettingsLeftOut) { reasons.append(.moduleSettingsLeftOut) }
            }
            if notApplied == nil, !entriesLeftOut.isEmpty {
                notes.append("\(entriesLeftOut.count) module entries left out, not one line, not a host, or not a rule a module may write: "
                             + entriesLeftOut.map(\.debugDescription).joined(separator: ", "))
                if !reasons.contains(.moduleEntriesLeftOut) { reasons.append(.moduleEntriesLeftOut) }
            }
             
             
            let why = reasons.map(\.spelling).joined(separator: " | ")
            var line: String
            if let notApplied {
                line = "modules not applied: \(notApplied.englishText)"
            } else if let record {
                line = "modules applied: modules=\(manifest.modules.count) rules=\(moduleRules.count) engine=on decrypting=\(decrypts) proxy=\(record.engineProxyName) listener=\(record.listenerName) \(record.listen):\(record.port) sniffer-added=\(record.snifferInjected) degraded=[\(why)]"
            } else {
                line = "modules applied: modules=\(manifest.modules.count) rules=\(moduleRules.count) engine=off\(decryption ? "" : #" decryption=off"#) degraded=[\(why)]"
            }
             
            if !notes.isEmpty { line += #" notes=["# + notes.joined(separator: " | ") + "]" }
            let handed = notApplied == nil ? rules : []
             
             
             
             
            let assignment = record.map { _ in
                ModuleEngineAssignment(
                    ports: manifest.ports ?? ModulePorts(engine: 0, reinject: 0), certEntryIP: certIP, decryptsTLS: decrypts,
                    mitmHosts: decrypts ? mitmHosts : ModuleHostList(items: [], standardPort: mitmHosts.standardPort),
                    forceHTTPEngineHosts: forceHTTPEngineHosts, modules: manifest.modules,
                    caFingerprintSHA256: manifest.caFingerprintSHA256,
                    reinjectCredentials: credentials.map { ModuleReinjectAuthorization(username: $0.username, password: $0.password) },
                    engineProxyCredentials: engineCredentials.map {
                        ModuleReinjectAuthorization(username: $0.username, password: $0.password)
                    })
            }
            var outcome = ModuleActivationOutcome(text: text, degradedBecause: reasons, notApplied: notApplied,
                                                   portsInUse: portsInUse, needsNewPorts: needsNewPorts, record: record,
                                                   reinjectCredentials: credentials,
                                                   engineProxyCredentials: record == nil ? nil : engineCredentials,
                                                   certEntryIP: record == nil ? nil : certIP,
                                                   certEntryIPNeedsConfirming: record != nil && certIP != nil && confirmCertIP,
                                                   logLine: line, injectedRules: handed)
            outcome.engineAssignment = assignment
            outcome.prependRules = path.carriesPrependRules && !handed.isEmpty ? handed : nil
            if path.carriesPrependRules, notApplied == nil {
                 
                 
                 
                var sets = ruleSets
                for (name, definition) in ModuleEngineHostSet.definitions(hostSets, copies: input.ruleSetCopiesDirectory) {
                    sets.definitions[name] = definition
                }
                outcome.ruleSets = sets
            }
            outcome.publishPath = path
            outcome.skipped = notApplied == nil ? skippedLines : []
            if notApplied == nil {
                outcome.inEffect = settledInEffect
                outcome.notes = settledNotes
                outcome.moduleLogLevel = settledLogLevel
                outcome.carriesSettings = settlesSettings
                outcome.changes = (manifest.settings ?? []).flatMap(\.changes).map { change in
                    var change = change
                    let held = heldByClash[change.origin]?.contains(change.key) == true
                    if held || input.settingsRefused != nil { change.applied = false }
                    return change
                }
            }
            return outcome
        }
         
         
         
         
        func settle(_ text: String, engineRules: [String]) -> (text: String, reasons: [ModuleDegradeReason]) {
            if namesAPublication(runtimeYAML, facts: facts), facts().namesANodeLibrary {
                notes.append(#"module settings left out: the nodes are in a node library"#)
                return (text, [.alreadyPublished])
            }
             
             
             
            var edits: [ModuleConfigurationEdit] = []
            var routeAsked: [(origin: ModuleLineOrigin, moduleID: String?)] = []
            var ipRewrites = 0
            for module in settings {
                for written in module.edits {
                     
                     
                     
                    var edit = written
                    edit.moduleID = module.moduleID
                    if edit.path.first == "dns", edit.valueJSON.contains("rule-set:module-"),
                       let value = try? OrderedJSON.parse(edit.valueJSON) {
                        let kept = ModuleRuleSetSyntax.strippingModuleSets(value, keeping: ruleSets.names)
                        guard let kept, !kept.isEmptyContainer else {
                            notes.append(#"a module's DNS setting names only sets this publication does not have: "# + edit.path.joined(separator: "."))
                            continue
                        }
                        edit.valueJSON = kept.serialized()
                    }
                    if edit.operation == .engineRoute {
                        routeAsked.append((edit.origin, module.moduleID))
                        continue
                    }
                     
                     
                     
                     
                    if edit.path.count == 1, let held = Self.heldChanges[edit.path[0]],
                       (edit.path == ["log-level"] && input.logLevelSetByApp) || (edit.path == ["mode"] && input.modeSetByApp)
                        || input.listenerKeysSetByApp.contains(edit.path[0]) {
                        heldByClash[edit.origin, default: []].insert(held)
                        skippedLines.append(ModuleIgnoredEntry(text: edit.path[0], reason: .setInClashSettings(edit.path[0]), origin: edit.origin,
                                                                moduleID: module.moduleID))
                        continue
                    }
                     
                     
                    if edit.path == ["x-clash-ip-rewrite"] {
                        ipRewrites += 1
                        if ipRewrites > ModuleSettingsMapping.maximumIPRewriteLines {
                            skippedLines.append(ModuleIgnoredEntry(text: "ip-rewrite", reason: .argumentsOverLimit, origin: edit.origin,
                                                                    moduleID: module.moduleID))
                            continue
                        }
                    }
                    edits.append(edit)
                }
                 
                 
                 
                var hosts: [ModuleHostMapping] = []
                for mapping in module.hosts {
                    if mapping.pattern.hasPrefix("rule-set:"), !ruleSets.names.contains(String(mapping.pattern.dropFirst("rule-set:".count))) {
                        skippedLines.append(ModuleIgnoredEntry(text: mapping.pattern, reason: .notApplicable(.doesNotApply), origin: mapping.origin,
                                                                moduleID: module.moduleID))
                        notes.append(#"a module's [Host] line names a set this publication does not have: "# + mapping.pattern)
                        continue
                    }
                    hosts.append(mapping)
                }
                edits += ModuleInjection.edits(of: hosts).map { edit in
                    var edit = edit
                    edit.moduleID = module.moduleID
                    return edit
                }
            }
             
             
             
             
             
             
             
            if !engineRules.isEmpty {
                let route = OrderedJSON.array(engineRules.map(OrderedJSON.string)).serialized()
                edits.append(ModuleConfigurationEdit(path: ["x-clash-every-mode-rules"], operation: .prepend, valueJSON: route,
                                                      origin: moduleRuleOrigin))
            }
             
             
             
            var waiting = routeAsked.map {
                ModuleIgnoredEntry(text: "always-reject-url-rewrite", reason: .waitingForKernel("always-reject-url-rewrite"), origin: $0.origin,
                                    moduleID: $0.moduleID)
            }
            edits.removeAll { edit in
                guard let key = ModuleSettingsMapping.waitsForTheKernel(edit) else { return false }
                waiting.append(ModuleIgnoredEntry(text: key, reason: .waitingForKernel(key), origin: edit.origin, moduleID: edit.moduleID))
                return true
            }
            if !waiting.isEmpty {
                skippedLines += waiting
                notes.append("\(waiting.count) module settings stay out for now: "
                             + Set(waiting.map(\.text)).sorted().joined(separator: ", "))
            }
            let groups = checkedGroups(edits)
            edits = groups.edits
            var left = groups.skipped
            guard !edits.isEmpty else {
                guard !left.isEmpty else { return (text, []) }
                skippedLines += left
                return (text, [.moduleSettingsLeftOut])
            }
            let written = ModuleInjection.applyEdits(edits, hosts: [], to: text)
            left += written.skipped
            settledInEffect += written.inEffect
            settlesSettings = !ConfigTransforms.sameText(written.text, text)
            notes += written.logNotes
             
            if let level = edits.last(where: { $0.path == ["log-level"] }),
               !left.contains(where: { $0.origin == level.origin && $0.moduleID == level.moduleID }),
               case .string(let value)? = try? OrderedJSON.parse(level.valueJSON) {
                settledLogLevel = value
            }
             
             
            let opening = edits.filter(opensToOtherDevices).filter { edit in
                !left.contains { $0.origin == edit.origin && $0.moduleID == edit.moduleID }
            }
            if !opening.isEmpty {
                for origin in opening.map(\.origin) where !settledNotes.contains(where: { $0.origin == origin }) {
                    settledNotes.append(ModuleLineNote(sentence: ModuleCopy.lanSharingOn, origin: origin))
                }
                notes.append(input.lanPermitted
                             ? #"a module opens the listeners to other devices"#
                             : #"a module opens the listeners to other devices, and this device does not permit it"#)
            }
            guard !left.isEmpty else { return (written.text, []) }
            skippedLines += left
            notes.append("\(left.count) module settings left out: "
                         + left.map { #"\#($0.text.debugDescription) (\#($0.reason.authoredText.englishText))"# }.joined(separator: ", "))
            return (written.text, [.moduleSettingsLeftOut])
        }
         
         
         
        func opensToOtherDevices(_ edit: ModuleConfigurationEdit) -> Bool {
            guard let value = try? OrderedJSON.parse(edit.valueJSON) else { return false }
            switch edit.path.first {
            case "allow-lan": return value == .scalar("true")
             
             
            case "bind-address" where input.listenerKeysSetByApp.contains("allow-lan"):
                return false
            case "bind-address":
                if case .string(let address) = value { return ModuleSettingsMapping.opensToOtherDevices(address) }
                return false
            case "listeners":
                guard case .object(let pairs) = value, case .string(let address)? = pairs.first(where: { $0.key == "listen" })?.value else { return false }
                return ModuleSettingsMapping.opensToOtherDevices(address)
            default:
                return false
            }
        }
         
         
         
        func checkedGroups(_ edits: [ModuleConfigurationEdit]) -> (edits: [ModuleConfigurationEdit], skipped: [ModuleIgnoredEntry]) {
            guard edits.contains(where: { $0.path == ["proxy-groups"] }) else { return (edits, []) }
            var groups: [(edit: Int, group: [(key: String, value: OrderedJSON)])] = []
            var parsed: [Int: [OrderedJSON]] = [:]
            for (index, edit) in edits.enumerated() where edit.path == ["proxy-groups"] {
                guard case .array(let items)? = try? OrderedJSON.parse(edit.valueJSON) else { continue }
                parsed[index] = items
                for case .object(let pairs) in items { groups.append((index, pairs)) }
            }
            func text(_ value: OrderedJSON?) -> String? {
                switch value {
                case .string(let text)?: return text
                case .scalar(let token)? where token != "null": return token
                default: return nil
                }
            }
            func list(_ value: OrderedJSON?) -> [String] {
                guard case .array(let items)? = value else { return [] }
                return items.compactMap(text)
            }
            let newNames = Set(groups.compactMap { text($0.group.first { $0.key == "name" }?.value) })
            let members = Set(groups.flatMap { list($0.group.first { $0.key == "proxies" }?.value) })
            let catalog = ModulePolicyCatalog.read(runtimeYAML, naming: members.union(newNames), knownPolicies: input.knownPolicies)
            var kept: [Int: [OrderedJSON]] = [:]
            var skipped: [ModuleIgnoredEntry] = []
            let builtIns = ProfileRuntimeConfigBuilder.builtinPolicies
            for (index, group) in groups {
                let origin = edits[index].origin
                let moduleID = edits[index].moduleID
                guard let name = text(group.first { $0.key == "name" }?.value), !name.isEmpty, ModuleYAMLText.isOneLine(name) else {
                    skipped.append(ModuleIgnoredEntry(text: "proxy-groups", reason: .unreadableLine, origin: origin, moduleID: moduleID))
                    continue
                }
                if catalog.has(name) || builtIns.contains(name) {
                     
                    notes.append(#"module group \#(name.debugDescription) left out: the configuration has a policy of this name"#)
                    skipped.append(ModuleIgnoredEntry(text: name, reason: .notApplicable(.doesNotApply), origin: origin, moduleID: moduleID))
                    continue
                }
                let named = list(group.first { $0.key == "proxies" }?.value)
                if let missing = named.first(where: { !builtIns.contains($0) && !catalog.has($0) && !newNames.contains($0) && $0 != "GLOBAL" }) {
                    skipped.append(ModuleIgnoredEntry(text: name, reason: .policyNotFound(missing), origin: origin, moduleID: moduleID))
                    continue
                }
                let context: [String: Any] = ["proxies": named.filter { catalog.nodes.contains($0) },
                                              "groups": catalog.groups + Array(newNames.subtracting([name])),
                                              "proxyProviders": catalog.proxyProviders]
                let contextJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: context, options: [.sortedKeys])) ?? Data("{}".utf8),
                                         as: UTF8.self)
                let refusal: String?
                do {
                    refusal = try ConfigurationTextEditing.check(kind: "proxyGroup", itemJSON: OrderedJSON.object(group).serialized(),
                                                                 contextJSON: contextJSON)
                } catch {
                    refusal = error.localizedDescription
                }
                if let refusal {
                    skipped.append(ModuleIgnoredEntry(text: name, reason: .ruleRefused(refusal), origin: origin, moduleID: moduleID))
                    continue
                }
                kept[index, default: []].append(.object(group))
            }
            var out: [ModuleConfigurationEdit] = []
            for (index, edit) in edits.enumerated() {
                guard edit.path == ["proxy-groups"], parsed[index] != nil else { out.append(edit); continue }
                guard let items = kept[index], !items.isEmpty else { continue }
                var copy = edit
                copy.valueJSON = OrderedJSON.array(items).serialized()
                out.append(copy)
            }
            return (out, skipped)
        }
        func notApplied(_ text: AuthoredText) -> ModuleActivationOutcome { finish(runtimeYAML, [], notApplied: text) }
         
         
         
        func moduleGroups() -> [(name: String, type: String)] {
            let edits = settings.flatMap(\.edits).filter { $0.path == ["proxy-groups"] }
            guard !edits.isEmpty else { return [] }
            let said = notes.count
            let checked = checkedGroups(edits)
            notes.removeSubrange(said...)
            var out: [(name: String, type: String)] = []
            for edit in checked.edits {
                guard case .array(let items)? = try? OrderedJSON.parse(edit.valueJSON) else { continue }
                for case .object(let pairs) in items {
                    guard case .string(let name)? = pairs.first(where: { $0.key == "name" })?.value else { continue }
                    var type = ""
                    if case .string(let written)? = pairs.first(where: { $0.key == "type" })?.value { type = written }
                    out.append((name, type))
                }
            }
            return out
        }

         
         
         
        guard path.carriesPrependRules else {
            notes.append(#"a published configuration published again without a rule index: its module rules cannot be told from its own"#)
            return notApplied(ModuleDegradeReason.exportedWithoutIndex.authoredText)
        }

        var engine = false
        if decryption {
            switch input.engine {
            case .ready:
                engine = true
                decrypts = true
            case .untrusted(let reason):
                engine = true
                degraded.append(reason.degradeReason)
            case .withheld(let reason):
                degraded.append(reason.degradeReason)
            case .portsFailed(let failed):
                 
                 
                degraded.append(.portsTaken)
                portsInUse = failed
                needsNewPorts = true
            case .unavailable:
                degraded.append(.engineUnavailable)
            }
        }
        var credentials: ModuleReinjectCredentials?
        var engineCredentials: ModuleEngineProxyCredentials?
        if engine {
            let read = facts()
            guard read.readable else { return notApplied(ModuleInjectionError.unreadableLayout.authoredText) }
            if read.namesANodeLibrary {
                 
                 
                 
                 
                 
                 
                engine = false
                degraded.append(.alreadyPublished)
                notes.append(#"the nodes are in a node library"#)
            } else if let ports = manifest.ports, let published = manifest.reinjectCredentials, published.isWellFormed,
                      let engineOwn = manifest.engineProxyCredentials, engineOwn.isWellFormed, engineOwn != published {
                if read.declaredPorts.isDisjoint(with: [ports.engine, ports.reinject]) {
                    certIP = certEntryIP(for: read, excluding: input.unreachableCertEntryIPs)
                    if certIP == nil { degraded.append(.noCertificateAddress) }
                    if let certIP, read.routeSetsDeclared {
                        confirmCertIP = true
                        notes.append("certificate address \(certIP) to be confirmed once the route sets are expanded")
                    }
                    credentials = published
                    engineCredentials = engineOwn
                } else {
                    engine = false
                    degraded.append(.portsTaken)
                    portsInUse = read.declaredPorts
                    needsNewPorts = true
                }
            } else {
                engine = false
                degraded.append(.engineUnavailable)
                portsInUse = read.declaredPorts
                needsNewPorts = true
                notes.append(manifest.ports == nil ? #"no ports published"#
                             : manifest.reinjectCredentials?.isWellFormed != true ? #"no usable re-inject credentials published"#
                             : #"no usable engine proxy credentials of its own published"#)
            }
             
             
             
            let work = certIP != nil || ModuleHostListEncoding.clause(for: manifest.forceHTTPEngineHosts) != nil
                || (decrypts && ModuleHostListEncoding.clause(for: manifest.mitmHosts) != nil)
            if engine, !work {
                engine = false
                notes.append(#"nothing for the engine to serve"#)
            }
        }

         
         
         
         
         
         
        if !appendedRules.isEmpty {
             
             
             
             
            let endsInMatch = ModulePolicyCatalog.read(runtimeYAML, naming: [], knownPolicies: input.knownPolicies).matchTarget != nil
            for rule in appendedRules {
                let reason: ModuleIgnoredReason = endsInMatch ? .noEffectInItsOwnApp(.noEffectThereEither) : .settingNotSupported(#"rules: #!append"#)
                skippedLines.append(ModuleIgnoredEntry(text: rule.rendered(rule.policy.kernelName ?? rule.policy.writtenName ?? "PROXY"),
                                                        reason: reason, origin: moduleRuleOrigin))
            }
            notes.append("\(appendedRules.count) module rules to go after the configuration's: "
                         + (endsInMatch ? #"its MATCH comes first"# : #"not supported"#))
        }
        let handedRules = leadingRules.filter { !namesASetLeftOut($0, ruleSets) }
        if !handedRules.isEmpty {
            let leadingRules = handedRules
            var catalog = ModulePolicyCatalog.read(runtimeYAML, naming: askedNames(leadingRules),
                                                    knownPolicies: input.knownPolicies)
             
             
             
             
            catalog.ruleProviders += ruleSets.names.sorted().filter { !catalog.ruleProviders.contains($0) }
            for (name, type) in moduleGroups() where catalog.groupTypes[name] == nil {
                catalog.groups.append(name)
                catalog.groupTypes[name] = type
            }
             
            let ahead = (engine && certIP != nil ? 1 : 0)
                + ModuleEngineRoute.quic(mitm: ModuleInjection.hostsForTheDocument(mitmHosts).list).rules.count
            let prepended = prependedRules(leadingRules, catalog: catalog, check: check, firstPlace: ahead,
                                          platform: input.platform)
            skippedLines += prepended.skipped
            moduleRules = prepended.lines
             
             
             
             
            entriesLeftOut = prepended.skipped.filter { $0.reason == .unreadableLine }.map(\.text)
            let device = prepended.skipped.filter { if case .platformCannot = $0.reason { return true } else { return false } }
            let unusable = prepended.skipped.filter { entry in
                if case .platformCannot = entry.reason { return false }
                return entry.reason != .unreadableLine
            }
            if !unusable.isEmpty {
                degraded.append(.moduleRulesLeftOut)
                notes.append("\(unusable.count) module rules left out: "
                             + unusable.map { #"\#($0.text.debugDescription) (\#($0.reason.authoredText.englishText))"# }
                                .joined(separator: ", "))
            }
            if !device.isEmpty {
                notes.append("\(device.count) module rules this device cannot run: "
                             + device.map(\.text.debugDescription).joined(separator: ", "))
            }
            if !prepended.defaulted.isEmpty {
                let pairs = prepended.defaulted.sorted { $0.key < $1.key }.map { #"\#($0.key) -> \#($0.value)"# }
                notes.append(#"policies the modules name and this configuration lacks: "# + pairs.joined(separator: ", "))
            }
            policiesGiven = prepended.policies
        }

         
         
         
        let needs = moduleRules.map(geodataNeeded(by:))
        let needed = needs.reduce(into: Set<GeodataKind>()) { $0.formUnion($1) }
        if !needed.isEmpty {
            guard facts().readable else { return notApplied(ModuleInjectionError.unreadableLayout.authoredText) }
            let missing = needed.filter { !geodataStaged($0, geodataMode: facts().geodataMode, in: input.geodataDirectory) }
            if !missing.isEmpty {
                let before = moduleRules.count
                moduleRules = zip(moduleRules, needs).filter { $0.1.isDisjoint(with: missing) }.map(\.0)
                if !degraded.contains(.moduleRulesLeftOut) { degraded.append(.moduleRulesLeftOut) }
                let kinds = GeodataKind.allCases.filter(missing.contains).map(\.rawValue).joined(separator: ", ")
                notes.append("\(before - moduleRules.count) module rules left out: \(kinds) not staged in \(input.geodataDirectory?.path ?? "no directory")")
            }
        }
         
         
        if !decryption, moduleRules.isEmpty { return finish(runtimeYAML, degraded) }

        let ports = manifest.ports ?? ModulePorts(engine: 0, reinject: 0)
        func plan(engine ready: Bool) -> ModuleInjectionPlan {
            ModuleInjectionPlan(enginePort: ports.engine, reinjectPort: ports.reinject,
                                 reinjectListenerName: reinjectListenerName, engineProxyName: engineProxyName,
                                 certEntryIP: certIP, mitmHosts: mitmHosts,
                                 forceHTTPEngineHosts: forceHTTPEngineHosts,
                                 moduleRules: moduleRules, engineReady: ready, decryptsTLS: decrypts,
                                 fakeIPRanges: cachedFacts?.fakeIPRanges ?? [],
                                 reinjectCredentials: credentials ?? .random(),
                                 engineProxyCredentials: engineCredentials ?? .random(),
                                 moduleRulePolicies: policiesGiven, platform: input.platform, moduleRuleSets: ruleSets.names)
        }
         
         
         
        func noting(_ result: ModuleInjection.Result, _ reasons: [ModuleDegradeReason]) -> [ModuleDegradeReason] {
            entriesLeftOut += result.leftOut
            return reasons
        }
        func subset(_ reasons: [ModuleDegradeReason]) -> ModuleActivationOutcome {
            do {
                let result = try ModuleInjection.injectReporting(into: runtimeYAML, plan: plan(engine: false))
                return finish(result.text, noting(result, reasons), rules: result.rules, hostSets: result.hostSets)
            } catch {
                 
                return notApplied(AuthoredText.of(error))
            }
        }

        let injected: ModuleInjection.Result
        do {
            injected = try ModuleInjection.injectReporting(into: runtimeYAML, plan: plan(engine: engine))
        } catch let refusal as ModuleInjectionError {
            guard engine else { return notApplied(refusal.authoredText) }
             
             
            notes.append("engine left out: \(refusal.authoredText.englishText)")
            switch refusal {
            case .unsupportedSectionLayout(let key): return subset(degraded + [.sectionNotAdjustable(key)])
            case .unusableCredentials, .unusableOwnValue: return subset(degraded + [.engineUnavailable])
            case .unreadableLayout: return subset(degraded + [.groupsNotAdjustable])
            case .engineNameTaken: return subset(degraded + [.engineNameTaken])
            }
        } catch {
            return notApplied(AuthoredText.of(error))
        }
        guard let engineName = injected.engineProxyName, let listener = injected.reinjectListenerName else {
            return finish(injected.text, noting(injected, degraded), rules: injected.rules, hostSets: injected.hostSets)
        }
        do {
            let text = try ModuleGroupExclusion.apply(to: injected.text, engineName: engineName)
             
             
             
            var degraded = degraded
            if !injected.snifferAdded.isEmpty {
                notes.append(#"the configuration's own sniffer gets what modules need: "# + injected.snifferAdded.joined(separator: ", "))
            }
            if !injected.snifferWrittenOff.isEmpty {
                notes.append(#"the configuration's own sniffer writes off what modules need, left as written: "#
                             + injected.snifferWrittenOff.joined(separator: ", "))
                degraded.append(.snifferWrittenOff(injected.snifferWrittenOff.joined(separator: ",")))
            }
            if injected.snifferNotCompleted {
                notes.append(#"the configuration's own sniffer needs what modules need and is left as written: it holds an anchor, an alias or a merge key, or does not read alone"#)
                degraded.append(.snifferNotCompleted)
            }
            let record = ModuleActivationRecord(engineProxyName: engineName, listenerName: listener,
                                                 listen: "127.0.0.1", port: ports.reinject,
                                                 userListenerCount: cachedFacts?.listenerCount ?? 0,
                                                 snifferInjected: injected.snifferInjected)
             
             
            var disclosures: [ModuleDisclosure] = []
            let reinjects = ModuleHostListEncoding.clause(for: manifest.forceHTTPEngineHosts) != nil
                || (decrypts && ModuleHostListEncoding.clause(for: manifest.mitmHosts) != nil)
            if reinjects {
                let origin = originRuleTypes(in: runtimeYAML)
                if !origin.isEmpty {
                    disclosures.append(.originRulesDoNotApply)
                    notes.append(#"rules that match by origin, or by an address they never look up, do not apply to what the engine reads: "#
                                 + origin.joined(separator: ", "))
                }
            }
            var outcome = finish(text, noting(injected, degraded), record: record, credentials: injected.reinjectCredentials,
                                 rules: injected.rules, engineCredentials: injected.engineProxyCredentials,
                                 hostSets: injected.hostSets)
            outcome.disclosures = disclosures
            return outcome
        } catch {
             
             
             
            notes.append("groups: \(AuthoredText.of(error).englishText)")
            return subset(degraded + [.groupsNotAdjustable])
        }
    }
}
