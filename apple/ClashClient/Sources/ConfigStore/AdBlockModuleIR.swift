import CryptoKit
import Foundation

 
 
 
 
 
 
 

 
 
enum AdBlockModuleFormat: String, Codable, Equatable, Sendable {
     
    case surge
     
    case loon
     
    case stash
     
     
     
    case quantumultX
}

 
 
enum AdBlockPlatform: String, Codable, Equatable, Sendable {
    case ios
    case mac
    case tvos

    static var current: AdBlockPlatform {
#if os(macOS)
        return .mac
#elseif os(tvOS)
        return .tvos
#else
        return .ios
#endif
    }
}

 
enum AdBlockArgumentKind: Codable, Equatable, Sendable {
     
    case text
     
    case toggle
     
    case choice([String])
     
    case input
     
     
    case storedChoice([String])
    case storedInput
}

 
 
 
 
 
 
struct AdBlockModuleArgument: Sendable {
    let name: String
     
    let defaultValue: String?
    private var details: Details?

     
    struct Detail: Equatable, Sendable {
        var kind: AdBlockArgumentKind = .text
         
        var valueType: String?
        var tag: String?
        var desc: String?
    }

    /// The declaration's own word for the argument's type (`select`, `switch`,
    /// `input`, ...), when the module used one.
    var declaredKind: String? { details.map { _ in kindWord } }

    private var kindWord: String {
        guard let details else { return "text" }
        switch details.detail.kind {
        case .text: return details.detail.valueType ?? "text"
        case .toggle: return "switch"
        case .choice: return "select"
        case .input: return "input"
        case .storedChoice: return "select"
        case .storedInput: return "input"
        }
    }

    private final class Details: Sendable {
        let detail: Detail
        init(_ detail: Detail) { self.detail = detail }
    }

    init(name: String, defaultValue: String?, kind: AdBlockArgumentKind = .text, valueType: String? = nil, tag: String? = nil,
         desc: String? = nil) {
        self.name = name
        self.defaultValue = defaultValue
        let detail = Detail(kind: kind, valueType: valueType, tag: tag, desc: desc)
        details = detail == Detail() ? nil : Details(detail)
    }

    var detail: Detail {
        get { details?.detail ?? Detail() }
        set { details = newValue == Detail() ? nil : Details(newValue) }
    }

    var kind: AdBlockArgumentKind {
        get { detail.kind }
        set { detail.kind = newValue }
    }

    var valueType: String? {
        get { detail.valueType }
        set { detail.valueType = newValue }
    }

    var tag: String? {
        get { detail.tag }
        set { detail.tag = newValue }
    }

    var desc: String? {
        get { detail.desc }
        set { detail.desc = newValue }
    }
}

extension AdBlockModuleArgument: Equatable {
    static func == (lhs: AdBlockModuleArgument, rhs: AdBlockModuleArgument) -> Bool {
        lhs.name == rhs.name && lhs.defaultValue == rhs.defaultValue && lhs.detail == rhs.detail
    }
}

extension AdBlockModuleArgument: Codable {
    private enum CodingKeys: String, CodingKey { case name, defaultValue, kind, valueType, tag, desc }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name),
                  defaultValue: try c.decodeIfPresent(String.self, forKey: .defaultValue),
                  kind: try c.decodeIfPresent(AdBlockArgumentKind.self, forKey: .kind) ?? .text,
                  valueType: try c.decodeIfPresent(String.self, forKey: .valueType),
                  tag: try c.decodeIfPresent(String.self, forKey: .tag),
                  desc: try c.decodeIfPresent(String.self, forKey: .desc))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(defaultValue, forKey: .defaultValue)
        if kind != .text { try c.encode(kind, forKey: .kind) }
        try c.encodeIfPresent(valueType, forKey: .valueType)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encodeIfPresent(desc, forKey: .desc)
    }
}

 
 
 
struct AdBlockManifestKey: Equatable, Sendable {
    let key: String
    let value: String
}

extension AdBlockManifestKey: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(key: try c.decode(String.self), value: try c.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(key)
        try c.encode(value)
    }
}

struct AdBlockModuleManifest: Equatable, Sendable {
    var name: String?
    var desc: String?
    var author: String?
    var icon: String?
     
    var system: [String]
    var arguments: [AdBlockModuleArgument]
    var format: AdBlockModuleFormat
     
    var sourceURL: String?
    var fetchedAt: Date?
     
    var contentSHA256: String
     
     
     
    var homepage: String? = nil
    var category: String? = nil
    var openURL: String? = nil
    var date: String? = nil
    var tag: String? = nil
    var version: String? = nil
    var argumentsDescription: String? = nil
     
    var otherKeys: [AdBlockManifestKey] = []
}

extension AdBlockModuleManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, desc, author, icon, system, arguments, format, sourceURL, fetchedAt, contentSHA256
        case homepage, category, openURL, date, tag, version, argumentsDescription, otherKeys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decodeIfPresent(String.self, forKey: .name),
                  desc: try c.decodeIfPresent(String.self, forKey: .desc),
                  author: try c.decodeIfPresent(String.self, forKey: .author),
                  icon: try c.decodeIfPresent(String.self, forKey: .icon),
                  system: try c.decodeIfPresent([String].self, forKey: .system) ?? [],
                  arguments: try c.decodeIfPresent([AdBlockModuleArgument].self, forKey: .arguments) ?? [],
                  format: try c.decode(AdBlockModuleFormat.self, forKey: .format),
                  sourceURL: try c.decodeIfPresent(String.self, forKey: .sourceURL),
                  fetchedAt: try c.decodeIfPresent(Date.self, forKey: .fetchedAt),
                  contentSHA256: try c.decode(String.self, forKey: .contentSHA256),
                  homepage: try c.decodeIfPresent(String.self, forKey: .homepage),
                  category: try c.decodeIfPresent(String.self, forKey: .category),
                  openURL: try c.decodeIfPresent(String.self, forKey: .openURL),
                  date: try c.decodeIfPresent(String.self, forKey: .date),
                  tag: try c.decodeIfPresent(String.self, forKey: .tag),
                  version: try c.decodeIfPresent(String.self, forKey: .version),
                  argumentsDescription: try c.decodeIfPresent(String.self, forKey: .argumentsDescription),
                  otherKeys: try c.decodeIfPresent([AdBlockManifestKey].self, forKey: .otherKeys) ?? [])
    }

     
     
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(desc, forKey: .desc)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(system, forKey: .system)
        try c.encode(arguments, forKey: .arguments)
        try c.encode(format, forKey: .format)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encodeIfPresent(fetchedAt, forKey: .fetchedAt)
        try c.encode(contentSHA256, forKey: .contentSHA256)
        try c.encodeIfPresent(homepage, forKey: .homepage)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(openURL, forKey: .openURL)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(argumentsDescription, forKey: .argumentsDescription)
        if !otherKeys.isEmpty { try c.encode(otherKeys, forKey: .otherKeys) }
    }
}

 
 
 
 
 
 
struct AdBlockLineOrigin: Hashable, Sendable {
     
    let section: String
     
     
    let line: Int
}

 
 
 
enum AdBlockSectionTable {
    struct Table: Sendable {
        let names: [String]
        let indices: [String: Int]

        init(_ names: [String]) {
            self.names = names
            var indices: [String: Int] = [:]
            for (index, name) in names.enumerated() where indices[name] == nil { indices[name] = index }
            self.indices = indices
        }
    }

    @TaskLocal static var current: Table?
}

extension AdBlockLineOrigin: Codable {
    private enum CodingKeys: String, CodingKey { case section, line }

    init(from decoder: Decoder) throws {
        if let table = AdBlockSectionTable.current, var pair = try? decoder.unkeyedContainer() {
            let index = try pair.decode(Int.self)
            let line = try pair.decode(Int.self)
            guard table.names.indices.contains(index) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: #"an origin names a section the table does not have"#))
            }
            self.init(section: table.names[index], line: line)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(section: try c.decode(String.self, forKey: .section), line: try c.decode(Int.self, forKey: .line))
    }

    func encode(to encoder: Encoder) throws {
        if let index = AdBlockSectionTable.current?.indices[section] {
            var pair = encoder.unkeyedContainer()
            try pair.encode(index)
            try pair.encode(line)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(section, forKey: .section)
        try c.encode(line, forKey: .line)
    }
}

 

enum AdBlockHostPattern: Codable, Equatable, Hashable, Sendable {
     
    case name(String)
     
    case ipAddress
    case ipv4Address
    case ipv6Address
     
    case simpleHostname
}

enum AdBlockHostPort: Codable, Equatable, Hashable, Sendable {
     
     
    case standard
    case port(UInt16)
     
    case all
}

struct AdBlockHostEntry: Codable, Equatable, Hashable, Sendable {
     
    var excluded: Bool
    var pattern: AdBlockHostPattern
    var port: AdBlockHostPort
}

 
 
 
enum AdBlockHostListDirective: String, Codable, Equatable, Sendable {
    case replace
    case append
    case insert
     
     
     
     
     
    case merge
     
     
     
     
     
    case setting
}

struct AdBlockHostListLine: Codable, Equatable, Sendable {
    var directive: AdBlockHostListDirective
    var entries: [AdBlockHostEntry]
    var origin: AdBlockLineOrigin
}

 
 
struct AdBlockHostList: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var entry: AdBlockHostEntry
         
        var moduleID: String
    }

    var items: [Item] {
        didSet { index = AdBlockHostListIndex(items) }
    }
    var standardPort: UInt16
     
     
     
    private(set) var index: AdBlockHostListIndex

    init(items: [Item], standardPort: UInt16) {
        self.items = items
        self.standardPort = standardPort
        index = AdBlockHostListIndex(items)
    }

    private enum CodingKeys: String, CodingKey { case items, standardPort }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: try container.decode([Item].self, forKey: .items),
                  standardPort: try container.decode(UInt16.self, forKey: .standardPort))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(standardPort, forKey: .standardPort)
    }

    static func == (lhs: AdBlockHostList, rhs: AdBlockHostList) -> Bool {
        lhs.items == rhs.items && lhs.standardPort == rhs.standardPort
    }
}

 

enum AdBlockRewritePhase: String, Codable, Equatable, Sendable {
    case request
    case response
     
     
     
    case cron
    case generic
}

enum AdBlockHeaderOperation: String, Codable, Equatable, Sendable {
    case add
    case delete
    case replace
    case replaceRegex
     
    case set
}

struct AdBlockReplacementPair: Codable, Equatable, Sendable {
    let search: String
    let replacement: String
}

 
 
 
enum AdBlockRewriteAction: Codable, Equatable, Sendable {
    case reject
    case reject200
    case rejectImg
    case rejectTinyGif
    case rejectDict
    case rejectArray
    case rejectDrop
    case rejectNoDrop
    case redirect302(String)
    case redirect307(String)
     
     
    case transparent(String)
    case header(phase: AdBlockRewritePhase, operation: AdBlockHeaderOperation, name: String, arguments: [String])
    case bodyReplace(phase: AdBlockRewritePhase, pairs: [AdBlockReplacementPair])
     
     
     
     
     
     
     
     
    case bodyJQ(phase: AdBlockRewritePhase, expression: String, sha256: String? = nil)
     
     
     
     
    case localAnswer(AdBlockLocalAnswer)
     
     
    case requestBody(AdBlockAnswerBody, contentType: String?)
     
    case json(phase: AdBlockRewritePhase, operations: [AdBlockJSONOperation])
}

 

struct AdBlockHeaderField: Codable, Equatable, Sendable {
    var name: String
    var value: String
}

 
enum AdBlockAnswerBody: Codable, Equatable, Sendable {
    case empty
    case text(String)
    case bytes(Data)
     
     
     
     
     
    case file(sha256: String, byteCount: Int)
    case tinyGIF
    case emptyJSONObject
    case emptyJSONArray
    case emptyVideo
}

struct AdBlockLocalAnswer: Codable, Equatable, Sendable {
     
    var status: Int
     
    var headers: [AdBlockHeaderField]
    var body: AdBlockAnswerBody
}

 
 
 
 
struct AdBlockAnswerFileReference: Codable, Equatable, Sendable {
    var url: String
    var sha256: String?
    var origin: AdBlockLineOrigin
     
     
     
     
    var base64: Bool? = nil
}

 
 
 
 
enum AdBlockAnswerFileLimit {
    static let iOS = 256 * 1024
    static let macOS = 10 * 1024 * 1024
}

 

enum AdBlockJSONPathComponent: Codable, Hashable, Sendable {
    case key(String)
    case index(Int)
     
     
     
     
    case every
}

 
 
 
enum AdBlockJSONOperation: Codable, Equatable, Sendable {
    case delete([AdBlockJSONPathComponent])
    case replace([AdBlockJSONPathComponent], valueJSON: String)
    case add([AdBlockJSONPathComponent], valueJSON: String)
    case deleteIfTruthy([AdBlockJSONPathComponent])
    case replaceIfTruthy([AdBlockJSONPathComponent], valueJSON: String)
    case addIfMissingOrNull([AdBlockJSONPathComponent], valueJSON: String)
}

 

indirect enum AdBlockCondition: Codable, Hashable, Sendable {
    case all([AdBlockCondition])
    case any([AdBlockCondition])
     
     
    case match(AdBlockConditionVariable, AdBlockConditionOperator, AdBlockConditionValue, capture: String?)
}

enum AdBlockConditionVariable: Codable, Hashable, Sendable {
    case url
    case requestMethod
    case requestHeader(String)
    case responseStatus
    case responseHeader(String)
}

enum AdBlockConditionOperator: String, Codable, Sendable {
    case regexSearch = "~="
    case equals = "=="
}

enum AdBlockConditionValue: Codable, Hashable, Sendable {
     
    case regex(String)
    case string(String)
    case number(Double)
     
     
    case null
}

 
 
 
 
 
struct AdBlockRewriteRule: Equatable, Sendable {
     
     
    var pattern: String
     
     
     
     
     
     
    var phase: AdBlockRewritePhase?
     
    var condition: AdBlockCondition?
     
    var actions: [AdBlockRewriteAction]
    var origin: AdBlockLineOrigin
     
     
     
     
     
    var policy: String?

     
     
    init(pattern: String, phase: AdBlockRewritePhase? = nil, condition: AdBlockCondition? = nil,
         actions: [AdBlockRewriteAction], origin: AdBlockLineOrigin, policy: String? = nil) {
        precondition(!actions.isEmpty, #"a rewrite rule has at least one action"#)
        self.pattern = pattern
        self.phase = phase
        self.condition = condition
        self.actions = actions
        self.origin = origin
        self.policy = policy
    }

     
    init(pattern: String, action: AdBlockRewriteAction, origin: AdBlockLineOrigin) {
        self.init(pattern: pattern, actions: [action], origin: origin)
    }

     
     
    var action: AdBlockRewriteAction { actions[0] }
}

extension AdBlockRewriteRule: Codable {
    private enum CodingKeys: String, CodingKey { case pattern, phase, condition, actions, action, origin, policy }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var actions = try c.decodeIfPresent([AdBlockRewriteAction].self, forKey: .actions) ?? []
        if actions.isEmpty, let one = try c.decodeIfPresent(AdBlockRewriteAction.self, forKey: .action) { actions = [one] }
        guard !actions.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: #"a rewrite rule with no action"#))
        }
        self.init(pattern: try c.decodeIfPresent(String.self, forKey: .pattern) ?? "",
                  phase: try c.decodeIfPresent(AdBlockRewritePhase.self, forKey: .phase),
                  condition: try c.decodeIfPresent(AdBlockCondition.self, forKey: .condition),
                  actions: actions, origin: try c.decode(AdBlockLineOrigin.self, forKey: .origin),
                  policy: try c.decodeIfPresent(String.self, forKey: .policy))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !pattern.isEmpty { try c.encode(pattern, forKey: .pattern) }
        try c.encodeIfPresent(phase, forKey: .phase)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encode(actions, forKey: .actions)
        try c.encode(origin, forKey: .origin)
        try c.encodeIfPresent(policy, forKey: .policy)
    }
}

 

 
enum AdBlockRulePolicy: Codable, Hashable, Sendable {
     
     
     
     
    case builtIn(String)
     
    case moduleChoice
     
     
    case named(String)

     
     
    static let builtInNames: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "REJECT-NO-DROP",
                                            "REJECT-TINYGIF", "REJECT-IMG", "REJECT-DICT", "REJECT-ARRAY", "REJECT-200",
                                            "REJECT-VIDEO"]

     
     
     
    static func isBuiltInName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return builtInNames.contains(upper) || (upper.hasPrefix("REJECT-") && upper.count > 7)
    }

     
     
    var writtenName: String? {
        switch self {
        case .builtIn(let name), .named(let name): return name
        case .moduleChoice: return nil
        }
    }

     
     
     
     
    var kernelName: String? {
        guard case .builtIn(let name) = self else { return nil }
        let upper = name.uppercased()
        if upper == "REJECT-DROP" || upper.hasPrefix("REJECT-DROP-") { return "REJECT-DROP" }
        return upper.hasPrefix("REJECT-") ? "REJECT" : upper
    }
}

 
 
 
struct AdBlockRoutingRule: Equatable, Sendable {
     
    var head: String
    var policy: AdBlockRulePolicy
    var params: [String]
    var origin: AdBlockLineOrigin

     
     
    var appended = false

    init(head: String, policy: AdBlockRulePolicy, params: [String] = [], origin: AdBlockLineOrigin, appended: Bool = false) {
        self.head = head
        self.policy = policy
        self.params = params
        self.origin = origin
        self.appended = appended
    }

     
    static let trailingOptions: Set<String> = ["no-resolve", "src"]
     
    static let logicTypes: Set<String> = ["AND", "OR", "NOT", "SUB-RULE"]

     
     
     
     
     
    init(line: String, origin: AdBlockLineOrigin) {
        let type = line.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces).uppercased()
        let grouped = Self.logicTypes.contains(type)
        var fields: [String] = []
        var depth = 0
        var current = ""
        for character in line {
            switch character {
            case "(" where grouped: depth += 1
            case ")" where grouped: depth = max(0, depth - 1)
            case "," where depth == 0:
                fields.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        fields.append(current)
        var params: [String] = []
        while fields.count > 2, let last = fields.last, Self.trailingOptions.contains(last.lowercased()) {
            params.insert(last, at: 0)
            fields.removeLast()
        }
        guard fields.count >= 2, let policy = fields.popLast() else {
            self.init(head: line, policy: .named(""), params: [], origin: origin)
            return
        }
        self.init(head: fields.joined(separator: ","),
                  policy: AdBlockRulePolicy.isBuiltInName(policy) ? .builtIn(policy) : .named(policy),
                  params: params, origin: origin)
    }

     
    func rendered(_ name: String) -> String {
        ([head, name] + params).joined(separator: ",")
    }

     
     
     
     
    var line: String {
        rendered(policy.kernelName ?? policy.writtenName ?? "PROXY")
    }
}

extension AdBlockRoutingRule: Codable {
    private enum CodingKeys: String, CodingKey { case head, policy, params, origin, line, appended }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try c.decode(AdBlockLineOrigin.self, forKey: .origin)
         
        if let line = try c.decodeIfPresent(String.self, forKey: .line), !c.contains(.head) {
            self.init(line: line, origin: origin)
            return
        }
        self.init(head: try c.decode(String.self, forKey: .head), policy: try c.decode(AdBlockRulePolicy.self, forKey: .policy),
                  params: try c.decodeIfPresent([String].self, forKey: .params) ?? [], origin: origin,
                  appended: try c.decodeIfPresent(Bool.self, forKey: .appended) ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(head, forKey: .head)
        try c.encode(policy, forKey: .policy)
        if !params.isEmpty { try c.encode(params, forKey: .params) }
        try c.encode(origin, forKey: .origin)
        if appended { try c.encode(true, forKey: .appended) }
    }
}

 
 
 
indirect enum AdBlockRuleCondition: Codable, Equatable, Sendable {
    case and([AdBlockRuleCondition])
    case or([AdBlockRuleCondition])
    case not(AdBlockRuleCondition)
    case urlRegex(String)
    case userAgent(String)
    case domain(String)
    case domainSuffix(String)
    case domainKeyword(String)
    case domainWildcard(String)
    case domainRegex(String)
    case ipCIDR(String)
    case dstPort(String)
    case network(String)
}

enum AdBlockEngineDecision: Codable, Equatable, Sendable {
    case answer(AdBlockRewriteAction)
    case pass
}

struct AdBlockEngineRule: Codable, Equatable, Sendable {
    var condition: AdBlockRuleCondition
     
    var gatePattern: String
    var decision: AdBlockEngineDecision
    var origin: AdBlockLineOrigin
     
     
     
     
     
    var policy: String? = nil
}

 

enum AdBlockHostValue: Codable, Equatable, Sendable {
    case addresses([String])
     
    case name(String)
     
    case dnsServers([String])
    case systemDNS
     
     
    case ipMode(String)
}

 
 
 
struct AdBlockHostMapping: Codable, Equatable, Sendable {
    var pattern: String
    var value: AdBlockHostValue
    var origin: AdBlockLineOrigin
}

enum AdBlockEditOperation: String, Codable, Sendable {
    case replace
     
    case append
     
    case prepend
     
     
    case merge
     
    case replaceIfAbsent
     
     
     
    case copyIfAbsent
     
     
    case serverParameter
     
     
     
    case nameserversWithParameter
     
     
    case engineRoute
}

 
enum AdBlockEditCondition: String, Codable, Sendable {
     
     
     
    case whereWritten
     
     
     
    case plainNameserver
     
     
     
     
     
     
     
     
     
    case fakeIPFilter
}

 
 
struct AdBlockConfigurationEdit: Codable, Equatable, Sendable {
     
    var path: [String]
    var operation: AdBlockEditOperation
     
    var valueJSON: String
    var origin: AdBlockLineOrigin
    var condition: AdBlockEditCondition? = nil
     
     
     
     
    var moduleID: String? = nil
}

 
 
 
 
enum AdBlockDeviceSettingKey: String, Codable, CaseIterable, Sendable {
    case hideVPNIcon
    case includeAllNetworks
    case includeLocalNetworks
    case includeAPNs
    case includeCellularServices
     
     
    case homeKitCompatibility
     
    case testURL
}

 
 
 
 
struct AdBlockModuleChange: Codable, Equatable, Sendable {
    enum Key: String, Codable, CaseIterable, Sendable {
        case logLevel, mode
         
        case lanSharing
        case httpPort, socksPort, mixedPort
        case bindAddress
        case controller, secret
         
        case listener
         
        case hideVPNIcon, includeAllNetworks, includeLocalNetworks, includeAPNs, includeCellularServices
        case homeKitCompatibility, testURL

        init(_ device: AdBlockDeviceSettingKey) {
            self = Key(rawValue: device.rawValue)!
        }
    }

    var key: Key
    var value: String
    var origin: AdBlockLineOrigin
     
     
     
     
    var applied = true

    init(key: Key, value: String, origin: AdBlockLineOrigin, applied: Bool = true) {
        self.key = key
        self.value = value
        self.origin = origin
        self.applied = applied
    }

    private enum CodingKeys: String, CodingKey { case key, value, origin, applied }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(Key.self, forKey: .key), value: try c.decode(String.self, forKey: .value),
                  origin: try c.decode(AdBlockLineOrigin.self, forKey: .origin),
                  applied: try c.decodeIfPresent(Bool.self, forKey: .applied) ?? true)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(value, forKey: .value)
        try c.encode(origin, forKey: .origin)
        if !applied { try c.encode(false, forKey: .applied) }
    }
}

 
 
struct AdBlockLineNote: Codable, Equatable, Sendable {
    var sentence: AdBlockSentence
    var origin: AdBlockLineOrigin
}

 
 
struct AdBlockDeviceSetting: Codable, Equatable, Sendable {
    var key: AdBlockDeviceSettingKey
    var value: String
    var origin: AdBlockLineOrigin
}

 
 
 
struct AdBlockSettingInEffect: Codable, Equatable, Sendable {
     
    var key: String
    var origin: AdBlockLineOrigin
}

enum AdBlockRuleSetKind: Codable, Equatable, Sendable {
    case classical
    case domainSet
     
    case builtInLAN
    case builtInSystem
     
    case provider(behavior: String, format: String)
}

 
struct AdBlockRuleSet: Codable, Equatable, Sendable {
     
    var url: String?
     
    var inline: [String]?
    var kind: AdBlockRuleSetKind
    var policy: AdBlockRulePolicy
    var params: [String]
     
    var interval: Int?
    var origin: AdBlockLineOrigin
     
     
    var sha256: String? = nil
     
     
     
    var name: String? = nil
     
    var headers: [String: [String]]? = nil
     
     
    var copy: AdBlockRuleSetCopy? = nil
}

 
 
 
 
struct AdBlockRuleSetCopy: Codable, Equatable, Sendable {
    var sha256: String
     
    var lines: Int
     
     
    var skipped: Int = 0
     
     
     
    var held: Int = 0

    init(sha256: String, lines: Int, skipped: Int = 0, held: Int = 0) {
        self.sha256 = sha256
        self.lines = lines
        self.skipped = skipped
        self.held = held
    }

    private enum CodingKeys: String, CodingKey { case sha256, lines, skipped, held }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sha256: try c.decode(String.self, forKey: .sha256), lines: try c.decode(Int.self, forKey: .lines),
                  skipped: try c.decodeIfPresent(Int.self, forKey: .skipped) ?? 0, held: try c.decodeIfPresent(Int.self, forKey: .held) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sha256, forKey: .sha256)
        try c.encode(lines, forKey: .lines)
        if skipped != 0 { try c.encode(skipped, forKey: .skipped) }
        if held != 0 { try c.encode(held, forKey: .held) }
    }
}

struct AdBlockScript: Codable, Equatable, Sendable {
    var name: String
    var phase: AdBlockRewritePhase
     
    var pattern: String
     
    var scriptURL: String
    var requiresBody: Bool
    var binaryBodyMode: Bool
    var maxSize: Int?
     
    var timeout: Int?
    var argument: String?
     
     
    var updateInterval: Int
     
     
    var bodySHA256: String?
    var origin: AdBlockLineOrigin
     
     
     
    var condition: AdBlockCondition? = nil
     
     
     
    var argumentNames: [String]? = nil
     
     
    var imageURL: String? = nil

    /// The schedule a cron declaration asked for. Quantumult X writes a
    /// five- or six-field cron line; Surge and Loon write five. Both are kept
    /// here as the fields the declaration had.
    var cronFields: [String]?

    /// The module's declared arguments and their defaults, as they stood when
    /// the module was read. `argumentNames` says which ones the script asked
    /// for; this says what they default to, and what type each one is, so
    /// `$argument` can carry a boolean where a boolean was declared.
    var argumentDefaults: [AdBlockScriptArgument]? = nil
}

/// One declared argument, as a script needs it.
struct AdBlockScriptArgument: Codable, Equatable, Sendable {
    var name: String
    /// `select`, `switch`, `input`, `number` — the declaration's own word.
    var kind: String?
    var defaultValue: String?
}

 

 
 
 
enum AdBlockIgnoredReason: Error, Codable, Equatable, Sendable {
    case sectionNotSupported(String)
    case settingNotSupported(String)
     
    case mapLocalNotSupported
    case argumentsNotSupported
    case unreadableLine
    case invalidPattern
    case invalidHost(String)
    case unsupportedRewriteType(String)
    case unsupportedRuleType(String)
    case customPolicy(String)
     
     
    case readersOwnPolicy
    case catchAllRule
     
     
    case urlRuleNeedsReject
    case ruleListNotSupported
     
    case ruleRefused(String)
    case unsupportedScriptType(String)
    case scriptWithoutAddress
    case boxJSNotSupported
    case missingArgument(String)
     
    case scriptTurnedOff
     
     
     
    case scriptAddressNotSecure
     
     
    case newerSyntaxNotSupported
     
     
    case argumentsOverLimit
     
     
     
    case headerOverLimit
     
     
     
    case scriptDownloadFailed(AdBlockSentence)
     
     
    case fileDownloadFailed(AdBlockSentence)
     
    case platformCannot(AdBlockPlatformLimit)
     
    case waitingForKernel(String)
     
    case setInClashSettings(String)
     
     
    case noEffectInItsOwnApp(AdBlockSentence)
     
    case answerFileTooLarge(Int)
     
    case lineTooLong(Int)
     
    case jqExpressionInvalid(String)
     
     
    case policyNotFound(String)
     
     
    case notApplicable(AdBlockSentence)
     
     
     
    case settingsRefused(String)
     
     
     
     
    case ruleSetTooLarge
     
     
     
    case tooManyRuleSets
     
     
    case ruleSetNotDownloadedYet
}

 
enum AdBlockPlatformLimit: String, Codable, Sendable {
     
     
    case processRules
     
    case lanDeviceRules
     
    case carrierCode
     
    case remoteRelativeFile
     
    case vpnIcon
     
     
    case systemProxy
     
     
    case pingForwarding
     
    case snellVersion
     
     
    case networkSwitching
     
    case noSuchSetting
     
    case cellularServices
}

 
 
 
enum AdBlockSentence: Codable, Equatable, Hashable, Sendable {
     
    case app(String, arguments: [String])
     
    case verbatim(String)
}

struct AdBlockIgnoredEntry: Codable, Equatable, Sendable {
     
    var text: String
    var reason: AdBlockIgnoredReason
    var origin: AdBlockLineOrigin
     
     
     
     
    var moduleID: String? = nil
}

 
enum AdBlockModuleRefusal: Error, Equatable, Sendable {
     
    case quantumultX(String)
    case notAModule
     
    case otherPlatform([String])
    case notText
    case tooLarge(Int)
    case unreadableYAML(String)
    case notAnAddress
     
     
    case requirementNotMet
}

 

 
 
 
 
 
 
struct AdBlockModuleIR: Equatable, Sendable {
     
     
     
     
     
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var manifest: AdBlockModuleManifest
    var mitmHostLines: [AdBlockHostListLine]
    var forceHTTPEngineHostLines: [AdBlockHostListLine]
     
    var routingRules: [AdBlockRoutingRule]
     
    var rewriteRules: [AdBlockRewriteRule]
     
    var engineRules: [AdBlockEngineRule] = []
    var scripts: [AdBlockScript]
     
    var hosts: [AdBlockHostMapping] = []
     
    var edits: [AdBlockConfigurationEdit] = []
     
    var deviceSettings: [AdBlockDeviceSetting] = []
     
    var inEffect: [AdBlockSettingInEffect] = []
     
    var changes: [AdBlockModuleChange] = []
     
    var notes: [AdBlockLineNote] = []
     
    var ruleSets: [AdBlockRuleSet] = []
     
    var answerFiles: [AdBlockAnswerFileReference] = []
    var ignored: [AdBlockIgnoredEntry]

    static func empty(_ manifest: AdBlockModuleManifest) -> AdBlockModuleIR {
        AdBlockModuleIR(schemaVersion: currentSchemaVersion, manifest: manifest, mitmHostLines: [],
                        forceHTTPEngineHostLines: [], routingRules: [], rewriteRules: [], scripts: [], ignored: [])
    }

     
     
     
     
     
    var effectiveCount: Int {
        (mitmHostLines + forceHTTPEngineHostLines).reduce(0) { $0 + $1.entries.count }
            + routingRules.count + rewriteRules.count + engineRules.count + scripts.count
            + hosts.count + edits.count + deviceSettings.count + inEffect.count + ruleSets.count
    }

     
    var ignoredCount: Int { ignored.count }

     
     
    var sections: [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ origin: AdBlockLineOrigin) {
            if seen.insert(origin.section).inserted { out.append(origin.section) }
        }
        mitmHostLines.forEach { add($0.origin) }
        forceHTTPEngineHostLines.forEach { add($0.origin) }
        routingRules.forEach { add($0.origin) }
        rewriteRules.forEach { add($0.origin) }
        engineRules.forEach { add($0.origin) }
        scripts.forEach { add($0.origin) }
        hosts.forEach { add($0.origin) }
        edits.forEach { add($0.origin) }
        deviceSettings.forEach { add($0.origin) }
        inEffect.forEach { add($0.origin) }
        changes.forEach { add($0.origin) }
        notes.forEach { add($0.origin) }
        ruleSets.forEach { add($0.origin) }
        answerFiles.forEach { add($0.origin) }
        ignored.forEach { add($0.origin) }
        return out
    }
}

extension AdBlockModuleIR: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, manifest, sections, mitmHostLines, forceHTTPEngineHostLines, routingRules, rewriteRules
        case engineRules, scripts, hosts, edits, deviceSettings, inEffect, changes, notes, ruleSets, answerFiles, ignored
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let table = AdBlockSectionTable.Table(try c.decodeIfPresent([String].self, forKey: .sections) ?? [])
        func list<T: Decodable>(_ key: CodingKeys) throws -> [T] { try c.decodeIfPresent([T].self, forKey: key) ?? [] }
        self = try AdBlockSectionTable.$current.withValue(table) {
            AdBlockModuleIR(schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
                            manifest: try c.decode(AdBlockModuleManifest.self, forKey: .manifest),
                            mitmHostLines: try list(.mitmHostLines), forceHTTPEngineHostLines: try list(.forceHTTPEngineHostLines),
                            routingRules: try list(.routingRules), rewriteRules: try list(.rewriteRules),
                            engineRules: try list(.engineRules), scripts: try list(.scripts), hosts: try list(.hosts),
                            edits: try list(.edits), deviceSettings: try list(.deviceSettings), inEffect: try list(.inEffect),
                            changes: try list(.changes), notes: try list(.notes),
                            ruleSets: try list(.ruleSets), answerFiles: try list(.answerFiles),
                            ignored: try list(.ignored))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let sections = self.sections
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(manifest, forKey: .manifest)
        if !sections.isEmpty { try c.encode(sections, forKey: .sections) }
        try AdBlockSectionTable.$current.withValue(AdBlockSectionTable.Table(sections)) {
            func list<T: Encodable>(_ value: [T], _ key: CodingKeys) throws {
                if !value.isEmpty { try c.encode(value, forKey: key) }
            }
            try list(mitmHostLines, .mitmHostLines)
            try list(forceHTTPEngineHostLines, .forceHTTPEngineHostLines)
            try list(routingRules, .routingRules)
            try list(rewriteRules, .rewriteRules)
            try list(engineRules, .engineRules)
            try list(scripts, .scripts)
            try list(hosts, .hosts)
            try list(edits, .edits)
            try list(deviceSettings, .deviceSettings)
            try list(inEffect, .inEffect)
            try list(changes, .changes)
            try list(notes, .notes)
            try list(ruleSets, .ruleSets)
            try list(answerFiles, .answerFiles)
            try list(ignored, .ignored)
        }
    }
}

struct AdBlockPorts: Codable, Equatable, Sendable {
     
    let engine: UInt16
     
    let reinject: UInt16
}

 
 
 
 
 
struct AdBlockReinjectCredentials: Codable, Equatable, Sendable {
    let username: String
    let password: String

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static func random() -> AdBlockReinjectCredentials {
        func word() -> String {
            var generator = SystemRandomNumberGenerator()
            return String((0..<24).map { _ in alphabet[Int(generator.next(upperBound: UInt(alphabet.count)))] })
        }
        return AdBlockReinjectCredentials(username: word(), password: word())
    }

     
     
     
    var isWellFormed: Bool {
        [username, password].allSatisfy { word in
            !word.isEmpty && word.unicodeScalars.allSatisfy { $0.isASCII && Self.alphabet.contains(Character($0)) }
        }
    }
}

 
 
 
 
typealias AdBlockEngineProxyCredentials = AdBlockReinjectCredentials

 
 
struct AdBlockGlobalManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Module: Codable, Equatable, Sendable {
        let id: String
        let name: String
         
         
         
        let irSHA256: String
        let effectiveCount: Int
        let ignoredCount: Int
         
         
         
         
         
        var leftOutOrigins: [AdBlockLineOrigin]? = nil
    }

    var schemaVersion: Int
     
     
     
     
    var enabled: Bool
     
    var modules: [Module]
    var mitmHosts: AdBlockHostList
    var forceHTTPEngineHosts: AdBlockHostList
     
     
     
    var routingRules: [Rule]
    var ports: AdBlockPorts?
     
    var caFingerprintSHA256: String?
     
     
     
     
     
    var reinjectCredentials: AdBlockReinjectCredentials?
     
     
     
     
    var engineProxyCredentials: AdBlockEngineProxyCredentials?
    var publishedAt: Date
     
     
     
     
     
     
    var settings: [ModuleSettings]? = nil
     
     
     
     
    var ruleProviders: [RuleProvider]? = nil
}

extension AdBlockGlobalManifest {
     
     
    struct RuleProvider: Codable, Equatable, Sendable {
         
         
        var name: String
         
        var definition: String
         
         
         
        var copy: String?
         
         
        var held: Int = 0
         
         
        var reference: String? = nil
         
         
         
         
        var overBudget = false

        init(name: String, definition: String, copy: String?, held: Int = 0, reference: String? = nil, overBudget: Bool = false) {
            self.name = name
            self.definition = definition
            self.copy = copy
            self.held = held
            self.reference = reference
            self.overBudget = overBudget
        }

        private enum CodingKeys: String, CodingKey { case name, definition, copy, held, reference, overBudget }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(name: try c.decode(String.self, forKey: .name), definition: try c.decode(String.self, forKey: .definition),
                      copy: try c.decodeIfPresent(String.self, forKey: .copy), held: try c.decodeIfPresent(Int.self, forKey: .held) ?? 0,
                      reference: try c.decodeIfPresent(String.self, forKey: .reference),
                      overBudget: try c.decodeIfPresent(Bool.self, forKey: .overBudget) ?? false)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(definition, forKey: .definition)
            try c.encodeIfPresent(copy, forKey: .copy)
            if held != 0 { try c.encode(held, forKey: .held) }
            try c.encodeIfPresent(reference, forKey: .reference)
            if overBudget { try c.encode(overBudget, forKey: .overBudget) }
        }
    }

     
    struct ModuleSettings: Codable, Equatable, Sendable {
        let moduleID: String
        var edits: [AdBlockConfigurationEdit] = []
        var hosts: [AdBlockHostMapping] = []
        var deviceSettings: [AdBlockDeviceSetting] = []
         
        var changes: [AdBlockModuleChange] = []

        init(moduleID: String, edits: [AdBlockConfigurationEdit] = [], hosts: [AdBlockHostMapping] = [],
             deviceSettings: [AdBlockDeviceSetting] = [], changes: [AdBlockModuleChange] = []) {
            self.moduleID = moduleID
            self.edits = edits
            self.hosts = hosts
            self.deviceSettings = deviceSettings
            self.changes = changes
        }

         
        init?(moduleID: String, ir: AdBlockModuleIR) {
            guard !ir.edits.isEmpty || !ir.hosts.isEmpty || !ir.deviceSettings.isEmpty || !ir.changes.isEmpty else { return nil }
            self.init(moduleID: moduleID, edits: ir.edits, hosts: ir.hosts, deviceSettings: ir.deviceSettings, changes: ir.changes)
        }

        private enum CodingKeys: String, CodingKey { case moduleID, edits, hosts, deviceSettings, changes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(moduleID: try c.decode(String.self, forKey: .moduleID),
                      edits: try c.decodeIfPresent([AdBlockConfigurationEdit].self, forKey: .edits) ?? [],
                      hosts: try c.decodeIfPresent([AdBlockHostMapping].self, forKey: .hosts) ?? [],
                      deviceSettings: try c.decodeIfPresent([AdBlockDeviceSetting].self, forKey: .deviceSettings) ?? [],
                      changes: try c.decodeIfPresent([AdBlockModuleChange].self, forKey: .changes) ?? [])
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(moduleID, forKey: .moduleID)
            if !edits.isEmpty { try c.encode(edits, forKey: .edits) }
            if !hosts.isEmpty { try c.encode(hosts, forKey: .hosts) }
            if !deviceSettings.isEmpty { try c.encode(deviceSettings, forKey: .deviceSettings) }
            if !changes.isEmpty { try c.encode(changes, forKey: .changes) }
        }
    }

     
    static func settings(_ modules: [(moduleID: String, ir: AdBlockModuleIR)]) -> [ModuleSettings]? {
        let out = modules.compactMap { ModuleSettings(moduleID: $0.moduleID, ir: $0.ir) }
        return out.isEmpty ? nil : out
    }

     
     
     
     
     
     
     
    struct Rule: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
        var head: String
        var policy: AdBlockRulePolicy
        var params: [String]
        var choice: String?
         
         
        var appended = false

        init(head: String, policy: AdBlockRulePolicy, params: [String] = [], choice: String? = nil, appended: Bool = false) {
            self.head = head
            self.policy = policy
            self.params = params
            self.choice = choice
            self.appended = appended
        }

         
         
        init(_ rule: AdBlockRoutingRule, choice: String? = nil) {
            let kernel = rule.policy.kernelName
            self.init(head: rule.head, policy: kernel.map { .builtIn($0) } ?? rule.policy,
                      params: rule.params, choice: kernel == nil ? choice : nil, appended: rule.appended)
        }

         
        init(line: String) {
            self.init(AdBlockRoutingRule(line: line, origin: AdBlockLineOrigin(section: "", line: 0)))
        }

        init(stringLiteral line: String) {
            self.init(line: line)
        }

         
        func rendered(_ name: String) -> String {
            ([head, name] + params).joined(separator: ",")
        }

        private enum CodingKeys: String, CodingKey { case head, policy, params, choice, appended }

        init(from decoder: Decoder) throws {
            if let line = try? decoder.singleValueContainer().decode(String.self) {
                self.init(line: line)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(head: try c.decode(String.self, forKey: .head), policy: try c.decode(AdBlockRulePolicy.self, forKey: .policy),
                      params: try c.decodeIfPresent([String].self, forKey: .params) ?? [],
                      choice: try c.decodeIfPresent(String.self, forKey: .choice),
                      appended: try c.decodeIfPresent(Bool.self, forKey: .appended) ?? false)
        }

        func encode(to encoder: Encoder) throws {
            if let name = policy.kernelName, choice == nil, !appended {
                var c = encoder.singleValueContainer()
                try c.encode(rendered(name))
                return
            }
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(head, forKey: .head)
            try c.encode(policy, forKey: .policy)
            if !params.isEmpty { try c.encode(params, forKey: .params) }
            try c.encodeIfPresent(choice, forKey: .choice)
            if appended { try c.encode(true, forKey: .appended) }
        }
    }
}

 
 
 
enum AdBlockJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
