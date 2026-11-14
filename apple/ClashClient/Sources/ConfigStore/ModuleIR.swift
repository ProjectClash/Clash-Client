import CryptoKit
import Foundation

 
 
 
 
 
 
 

 
 
enum ModuleFormat: String, Codable, Equatable, Sendable {
     
    case surge
     
    case loon
     
    case stash
     
     
     
    case quantumultX
}

 
 
enum ModulePlatform: String, Codable, Equatable, Sendable {
    case ios
    case mac
    case tvos

    static var current: ModulePlatform {
#if os(macOS)
        return .mac
#elseif os(tvOS)
        return .tvos
#else
        return .ios
#endif
    }
}

 
enum ModuleArgumentKind: Codable, Equatable, Sendable {
     
    case text
     
    case toggle
     
    case choice([String])
     
    case input
     
     
    case storedChoice([String])
    case storedInput
}

 
 
 
 
 
 
struct ModuleArgument: Sendable {
    let name: String
     
    let defaultValue: String?
    private var details: Details?

     
    struct Detail: Equatable, Sendable {
        var kind: ModuleArgumentKind = .text
         
        var valueType: String?
        var tag: String?
        var desc: String?
    }

    private final class Details: Sendable {
        let detail: Detail
        init(_ detail: Detail) { self.detail = detail }
    }

    init(name: String, defaultValue: String?, kind: ModuleArgumentKind = .text, valueType: String? = nil, tag: String? = nil,
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

    var kind: ModuleArgumentKind {
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

extension ModuleArgument: Equatable {
    static func == (lhs: ModuleArgument, rhs: ModuleArgument) -> Bool {
        lhs.name == rhs.name && lhs.defaultValue == rhs.defaultValue && lhs.detail == rhs.detail
    }
}

extension ModuleArgument: Codable {
    private enum CodingKeys: String, CodingKey { case name, defaultValue, kind, valueType, tag, desc }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name),
                  defaultValue: try c.decodeIfPresent(String.self, forKey: .defaultValue),
                  kind: try c.decodeIfPresent(ModuleArgumentKind.self, forKey: .kind) ?? .text,
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

 
 
 
struct ModuleManifestKey: Equatable, Sendable {
    let key: String
    let value: String
}

extension ModuleManifestKey: Codable {
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

struct ModuleManifest: Equatable, Sendable {
    var name: String?
    var desc: String?
    var author: String?
    var icon: String?
     
     
     
     
     
     
     
    var system: [String]
    var arguments: [ModuleArgument]
    var format: ModuleFormat
     
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
     
    var otherKeys: [ModuleManifestKey] = []
}

extension ModuleManifest: Codable {
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
                  arguments: try c.decodeIfPresent([ModuleArgument].self, forKey: .arguments) ?? [],
                  format: try c.decode(ModuleFormat.self, forKey: .format),
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
                  otherKeys: try c.decodeIfPresent([ModuleManifestKey].self, forKey: .otherKeys) ?? [])
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

 
 
 
 
 
 
struct ModuleLineOrigin: Hashable, Sendable {
     
    let section: String
     
     
    let line: Int
}

 
 
 
enum ModuleSectionTable {
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

extension ModuleLineOrigin: Codable {
    private enum CodingKeys: String, CodingKey { case section, line }

    init(from decoder: Decoder) throws {
        if let table = ModuleSectionTable.current, var pair = try? decoder.unkeyedContainer() {
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
        if let index = ModuleSectionTable.current?.indices[section] {
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

 

enum ModuleHostPattern: Codable, Equatable, Hashable, Sendable {
     
    case name(String)
     
    case ipAddress
    case ipv4Address
    case ipv6Address
     
    case simpleHostname
}

enum ModuleHostPort: Codable, Equatable, Hashable, Sendable {
     
     
    case standard
    case port(UInt16)
     
    case all
}

struct ModuleHostEntry: Codable, Equatable, Hashable, Sendable {
     
    var excluded: Bool
    var pattern: ModuleHostPattern
    var port: ModuleHostPort
}

 
 
 
enum ModuleHostListDirective: String, Codable, Equatable, Sendable {
    case replace
    case append
    case insert
     
     
     
     
     
    case merge
     
     
     
     
     
    case setting
}

struct ModuleHostListLine: Codable, Equatable, Sendable {
    var directive: ModuleHostListDirective
    var entries: [ModuleHostEntry]
    var origin: ModuleLineOrigin
}

 
 
struct ModuleHostList: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var entry: ModuleHostEntry
         
        var moduleID: String
    }

    var items: [Item] {
        didSet { index = ModuleHostListIndex(items) }
    }
    var standardPort: UInt16
     
     
     
    private(set) var index: ModuleHostListIndex

    init(items: [Item], standardPort: UInt16) {
        self.items = items
        self.standardPort = standardPort
        index = ModuleHostListIndex(items)
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

    static func == (lhs: ModuleHostList, rhs: ModuleHostList) -> Bool {
        lhs.items == rhs.items && lhs.standardPort == rhs.standardPort
    }
}

 

enum ModuleRewritePhase: String, Codable, Equatable, Sendable {
    case request
    case response
}

enum ModuleHeaderOperation: String, Codable, Equatable, Sendable {
    case add
    case delete
    case replace
    case replaceRegex
     
    case set
     
     
     
     
    case replaceHead
}

struct ModuleReplacementPair: Codable, Equatable, Sendable {
    let search: String
    let replacement: String
}

 
 
 
enum ModuleRewriteAction: Codable, Equatable, Sendable {
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
    case header(phase: ModuleRewritePhase, operation: ModuleHeaderOperation, name: String, arguments: [String])
    case bodyReplace(phase: ModuleRewritePhase, pairs: [ModuleReplacementPair])
     
     
     
     
     
     
     
     
    case bodyJQ(phase: ModuleRewritePhase, expression: String, sha256: String? = nil)
     
     
     
     
    case localAnswer(ModuleLocalAnswer)
     
     
    case requestBody(ModuleAnswerBody, contentType: String?)
     
    case json(phase: ModuleRewritePhase, operations: [ModuleJSONOperation])
}

 

struct ModuleHeaderField: Codable, Equatable, Sendable {
    var name: String
    var value: String
}

 
enum ModuleAnswerBody: Codable, Equatable, Sendable {
    case empty
    case text(String)
    case bytes(Data)
     
     
     
     
     
    case file(sha256: String, byteCount: Int)
    case tinyGIF
    case emptyJSONObject
    case emptyJSONArray
    case emptyVideo
}

struct ModuleLocalAnswer: Codable, Equatable, Sendable {
     
    var status: Int
     
    var headers: [ModuleHeaderField]
    var body: ModuleAnswerBody
}

 
 
 
 
struct ModuleAnswerFileReference: Codable, Equatable, Sendable {
    var url: String
    var sha256: String?
    var origin: ModuleLineOrigin
     
     
     
     
    var base64: Bool? = nil
}

 

enum ModuleJSONPathComponent: Codable, Hashable, Sendable {
    case key(String)
    case index(Int)
     
     
     
     
    case every
}

 
 
 
enum ModuleJSONOperation: Codable, Equatable, Sendable {
    case delete([ModuleJSONPathComponent])
    case replace([ModuleJSONPathComponent], valueJSON: String)
    case add([ModuleJSONPathComponent], valueJSON: String)
    case deleteIfTruthy([ModuleJSONPathComponent])
    case replaceIfTruthy([ModuleJSONPathComponent], valueJSON: String)
    case addIfMissingOrNull([ModuleJSONPathComponent], valueJSON: String)
}

 

indirect enum ModuleCondition: Codable, Hashable, Sendable {
    case all([ModuleCondition])
    case any([ModuleCondition])
     
     
    case match(ModuleConditionVariable, ModuleConditionOperator, ModuleConditionValue, capture: String?)
}

enum ModuleConditionVariable: Codable, Hashable, Sendable {
    case url
    case requestMethod
    case requestHeader(String)
    case responseStatus
    case responseHeader(String)
     
     
     
     
    case requestHead
}

enum ModuleConditionOperator: String, Codable, Sendable {
    case regexSearch = "~="
    case equals = "=="
}

enum ModuleConditionValue: Codable, Hashable, Sendable {
     
    case regex(String)
    case string(String)
    case number(Double)
     
     
    case null
}

 
 
 
 
 
struct ModuleRewriteRule: Equatable, Sendable {
     
     
    var pattern: String
     
     
     
     
     
     
    var phase: ModuleRewritePhase?
     
    var condition: ModuleCondition?
     
    var actions: [ModuleRewriteAction]
    var origin: ModuleLineOrigin
     
     
     
     
     
    var policy: String?

     
     
    init(pattern: String, phase: ModuleRewritePhase? = nil, condition: ModuleCondition? = nil,
         actions: [ModuleRewriteAction], origin: ModuleLineOrigin, policy: String? = nil) {
        precondition(!actions.isEmpty, #"a rewrite rule has at least one action"#)
        self.pattern = pattern
        self.phase = phase
        self.condition = condition
        self.actions = actions
        self.origin = origin
        self.policy = policy
    }

     
    init(pattern: String, action: ModuleRewriteAction, origin: ModuleLineOrigin) {
        self.init(pattern: pattern, actions: [action], origin: origin)
    }

     
     
    var action: ModuleRewriteAction { actions[0] }
}

extension ModuleRewriteRule: Codable {
    private enum CodingKeys: String, CodingKey { case pattern, phase, condition, actions, action, origin, policy }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var actions = try c.decodeIfPresent([ModuleRewriteAction].self, forKey: .actions) ?? []
        if actions.isEmpty, let one = try c.decodeIfPresent(ModuleRewriteAction.self, forKey: .action) { actions = [one] }
        guard !actions.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: #"a rewrite rule with no action"#))
        }
        self.init(pattern: try c.decodeIfPresent(String.self, forKey: .pattern) ?? "",
                  phase: try c.decodeIfPresent(ModuleRewritePhase.self, forKey: .phase),
                  condition: try c.decodeIfPresent(ModuleCondition.self, forKey: .condition),
                  actions: actions, origin: try c.decode(ModuleLineOrigin.self, forKey: .origin),
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

 

 
enum ModuleRulePolicy: Codable, Hashable, Sendable {
     
     
     
     
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

 
 
 
struct ModuleRoutingRule: Equatable, Sendable {
     
    var head: String
    var policy: ModuleRulePolicy
    var params: [String]
    var origin: ModuleLineOrigin

     
     
    var appended = false

    init(head: String, policy: ModuleRulePolicy, params: [String] = [], origin: ModuleLineOrigin, appended: Bool = false) {
        self.head = head
        self.policy = policy
        self.params = params
        self.origin = origin
        self.appended = appended
    }

     
    static let trailingOptions: Set<String> = ["no-resolve", "src"]
     
    static let logicTypes: Set<String> = ["AND", "OR", "NOT", "SUB-RULE"]

     
     
     
     
     
    init(line: String, origin: ModuleLineOrigin) {
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
                  policy: ModuleRulePolicy.isBuiltInName(policy) ? .builtIn(policy) : .named(policy),
                  params: params, origin: origin)
    }

     
    func rendered(_ name: String) -> String {
        ([head, name] + params).joined(separator: ",")
    }

     
     
     
     
    var line: String {
        rendered(policy.kernelName ?? policy.writtenName ?? "PROXY")
    }
}

extension ModuleRoutingRule: Codable {
    private enum CodingKeys: String, CodingKey { case head, policy, params, origin, line, appended }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try c.decode(ModuleLineOrigin.self, forKey: .origin)
         
        if let line = try c.decodeIfPresent(String.self, forKey: .line), !c.contains(.head) {
            self.init(line: line, origin: origin)
            return
        }
        self.init(head: try c.decode(String.self, forKey: .head), policy: try c.decode(ModuleRulePolicy.self, forKey: .policy),
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

 
 
 
indirect enum ModuleRuleCondition: Codable, Equatable, Sendable {
    case and([ModuleRuleCondition])
    case or([ModuleRuleCondition])
    case not(ModuleRuleCondition)
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

enum ModuleEngineDecision: Codable, Equatable, Sendable {
    case answer(ModuleRewriteAction)
    case pass
}

struct ModuleEngineRule: Codable, Equatable, Sendable {
    var condition: ModuleRuleCondition
     
    var gatePattern: String
    var decision: ModuleEngineDecision
    var origin: ModuleLineOrigin
     
     
     
     
     
    var policy: String? = nil
}

 

enum ModuleHostValue: Codable, Equatable, Sendable {
    case addresses([String])
     
    case name(String)
     
    case dnsServers([String])
    case systemDNS
     
     
    case ipMode(String)
}

 
 
 
struct ModuleHostMapping: Codable, Equatable, Sendable {
    var pattern: String
    var value: ModuleHostValue
    var origin: ModuleLineOrigin
}

enum ModuleEditOperation: String, Codable, Sendable {
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

 
enum ModuleEditCondition: String, Codable, Sendable {
     
     
     
    case whereWritten
     
     
     
    case plainNameserver
     
     
     
     
     
     
     
     
     
    case fakeIPFilter
}

 
 
struct ModuleConfigurationEdit: Codable, Equatable, Sendable {
     
    var path: [String]
    var operation: ModuleEditOperation
     
    var valueJSON: String
    var origin: ModuleLineOrigin
    var condition: ModuleEditCondition? = nil
     
     
     
     
    var moduleID: String? = nil
}

 
 
 
 
enum ModuleDeviceSettingKey: String, Codable, CaseIterable, Sendable {
    case hideVPNIcon
    case includeAllNetworks
    case includeLocalNetworks
    case includeAPNs
    case includeCellularServices
     
     
    case homeKitCompatibility
     
    case testURL
}

 
 
 
 
struct ModuleChange: Codable, Equatable, Sendable {
    enum Key: String, Codable, CaseIterable, Sendable {
        case logLevel, mode
         
        case lanSharing
        case httpPort, socksPort, mixedPort
        case bindAddress
        case controller, secret
         
        case listener
         
        case hideVPNIcon, includeAllNetworks, includeLocalNetworks, includeAPNs, includeCellularServices
        case homeKitCompatibility, testURL

        init(_ device: ModuleDeviceSettingKey) {
            self = Key(rawValue: device.rawValue)!
        }
    }

    var key: Key
    var value: String
    var origin: ModuleLineOrigin
     
     
     
     
    var applied = true

    init(key: Key, value: String, origin: ModuleLineOrigin, applied: Bool = true) {
        self.key = key
        self.value = value
        self.origin = origin
        self.applied = applied
    }

    private enum CodingKeys: String, CodingKey { case key, value, origin, applied }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(Key.self, forKey: .key), value: try c.decode(String.self, forKey: .value),
                  origin: try c.decode(ModuleLineOrigin.self, forKey: .origin),
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

 
 
struct ModuleLineNote: Codable, Equatable, Sendable {
    var sentence: ModuleSentence
    var origin: ModuleLineOrigin
}

 
 
struct ModuleDeviceSetting: Codable, Equatable, Sendable {
    var key: ModuleDeviceSettingKey
    var value: String
    var origin: ModuleLineOrigin
}

 
 
 
struct ModuleSettingInEffect: Codable, Equatable, Sendable {
     
    var key: String
    var origin: ModuleLineOrigin
}

enum ModuleRuleSetKind: Codable, Equatable, Sendable {
    case classical
    case domainSet
     
    case builtInLAN
    case builtInSystem
     
    case provider(behavior: String, format: String)
}

 
struct ModuleRuleSet: Codable, Equatable, Sendable {
     
    var url: String?
     
    var inline: [String]?
    var kind: ModuleRuleSetKind
    var policy: ModuleRulePolicy
    var params: [String]
     
    var interval: Int?
    var origin: ModuleLineOrigin
     
     
    var sha256: String? = nil
     
     
     
    var name: String? = nil
     
    var headers: [String: [String]]? = nil
     
     
    var copy: ModuleRuleSetCopy? = nil
}

 
 
 
 
struct ModuleRuleSetCopy: Codable, Equatable, Sendable {
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

struct ModuleScript: Codable, Equatable, Sendable {
    var name: String
    var phase: ModuleRewritePhase
     
    var pattern: String
     
    var scriptURL: String
    var requiresBody: Bool
    var binaryBodyMode: Bool
    var maxSize: Int?
     
    var timeout: Int?
    var argument: String?
     
     
    var updateInterval: Int
     
     
    var bodySHA256: String?
    var origin: ModuleLineOrigin
     
     
     
    var condition: ModuleCondition? = nil
     
     
    var argumentNames: [String]? = nil
     
     
    var imageURL: String? = nil
     
     
     
     
    var typedArguments: [ModuleScriptTypedArgument]? = nil
}

 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleScriptTypedArgument: Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
    }

    let name: String
    let value: Value
}

extension ModuleScriptTypedArgument.Value: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
         
         
        if c.decodeNil() {
            self = .null
        } else if let flag = try? c.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? c.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let text): try c.encode(text)
         
         
         
        case .number(let number) where !number.isFinite: try c.encode(String(number))
        case .number(let number): try c.encode(number)
        case .bool(let flag): try c.encode(flag)
        case .null: try c.encodeNil()
        }
    }
}

extension ModuleScriptTypedArgument: Codable {
    private enum CodingKeys: String, CodingKey { case name, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
         
        self.init(name: try c.decode(String.self, forKey: .name),
                  value: try c.decodeIfPresent(Value.self, forKey: .value) ?? .null)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
    }
}

 
 
enum ModuleAppScriptKind: String, Codable, CaseIterable, Sendable {
     
     
    case cron
     
     
    case event
     
     
    case networkChanged
     
     
    case generic
}

 
 
 
 
 
 
 
 
 
 
struct ModulePanel: Codable, Equatable, Sendable {
    var name: String
    var title: String? = nil
    var content: String? = nil
     
    var style: String? = nil
     
    var icon: String? = nil
     
    var iconColor: String? = nil
     
    var scriptName: String? = nil
     
    var updateInterval: Int? = nil
    var origin: ModuleLineOrigin
}

struct ModuleAppScript: Equatable, Sendable {
     
     
    var name: String
    var kind: ModuleAppScriptKind
     
     
     
     
    var cronExpression: String? = nil
     
    var eventName: String? = nil
     
    var scriptURL: String
     
     
    var timeout: Int? = nil
     
    var argument: String? = nil
     
     
    var argumentNames: [String]? = nil
    var typedArguments: [ModuleScriptTypedArgument]? = nil
     
    var updateInterval: Int = ModuleAppScript.defaultUpdateInterval
     
     
    var bodySHA256: String? = nil
    var origin: ModuleLineOrigin
     
    var imageURL: String? = nil
     
     
     
    var wakeSystem: Bool = false
     
     
     
    var engine: String? = nil
}

extension ModuleAppScript: Codable {
     
     
     
     
    static let defaultUpdateInterval = 86_400

    private enum CodingKeys: String, CodingKey {
        case name, kind, cronExpression, eventName, scriptURL, timeout, argument, argumentNames, typedArguments
        case updateInterval, bodySHA256, origin, imageURL, wakeSystem, engine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), kind: try c.decode(ModuleAppScriptKind.self, forKey: .kind),
                  cronExpression: try c.decodeIfPresent(String.self, forKey: .cronExpression),
                  eventName: try c.decodeIfPresent(String.self, forKey: .eventName),
                  scriptURL: try c.decode(String.self, forKey: .scriptURL),
                  timeout: try c.decodeIfPresent(Int.self, forKey: .timeout),
                  argument: try c.decodeIfPresent(String.self, forKey: .argument),
                  argumentNames: try c.decodeIfPresent([String].self, forKey: .argumentNames),
                  typedArguments: try c.decodeIfPresent([ModuleScriptTypedArgument].self, forKey: .typedArguments),
                  updateInterval: try c.decodeIfPresent(Int.self, forKey: .updateInterval) ?? Self.defaultUpdateInterval,
                  bodySHA256: try c.decodeIfPresent(String.self, forKey: .bodySHA256),
                  origin: try c.decode(ModuleLineOrigin.self, forKey: .origin),
                  imageURL: try c.decodeIfPresent(String.self, forKey: .imageURL),
                  wakeSystem: try c.decodeIfPresent(Bool.self, forKey: .wakeSystem) ?? false,
                  engine: try c.decodeIfPresent(String.self, forKey: .engine))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(cronExpression, forKey: .cronExpression)
        try c.encodeIfPresent(eventName, forKey: .eventName)
        try c.encode(scriptURL, forKey: .scriptURL)
        try c.encodeIfPresent(timeout, forKey: .timeout)
        try c.encodeIfPresent(argument, forKey: .argument)
        try c.encodeIfPresent(argumentNames, forKey: .argumentNames)
        try c.encodeIfPresent(typedArguments, forKey: .typedArguments)
        if updateInterval != Self.defaultUpdateInterval { try c.encode(updateInterval, forKey: .updateInterval) }
        try c.encodeIfPresent(bodySHA256, forKey: .bodySHA256)
        try c.encode(origin, forKey: .origin)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        if wakeSystem { try c.encode(true, forKey: .wakeSystem) }
        try c.encodeIfPresent(engine, forKey: .engine)
    }
}

 

 
 
 
enum ModuleIgnoredReason: Error, Codable, Equatable, Sendable {
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
    case missingArgument(String)
     
    case scriptTurnedOff
     
     
     
     
     
     
    case scriptAddressNotSecure
     
     
    case newerSyntaxNotSupported
     
     
     
    case argumentsOverLimit
     
     
     
     
     
     
     
    case scriptDownloadFailed(ModuleSentence)
     
     
    case fileDownloadFailed(ModuleSentence)
     
    case platformCannot(ModulePlatformLimit)
     
    case waitingForKernel(String)
     
    case setInClashSettings(String)
     
     
    case noEffectInItsOwnApp(ModuleSentence)
     
     
     
     
     
     
    case jqExpressionInvalid(String)
     
     
    case policyNotFound(String)
     
     
    case notApplicable(ModuleSentence)
     
     
     
    case settingsRefused(String)
     
     
     
     
    case ruleSetTooLarge
     
     
     
    case tooManyRuleSets
     
     
    case ruleSetNotDownloadedYet
}

 
enum ModulePlatformLimit: String, Codable, Sendable {
     
     
    case processRules
     
    case lanDeviceRules
     
    case carrierCode
     
    case remoteRelativeFile
     
     
    case systemProxy
     
     
    case pingForwarding
     
    case snellVersion
     
     
    case networkSwitching
     
    case noSuchSetting
     
    case cellularServices
     
     
     
     
     
    case dnsScripts
     
     
    case ruleScripts
}

 
 
 
enum ModuleSentence: Codable, Equatable, Hashable, Sendable {
     
    case app(String, arguments: [String])
     
    case verbatim(String)
}

struct ModuleIgnoredEntry: Codable, Equatable, Sendable {
     
    var text: String
    var reason: ModuleIgnoredReason
    var origin: ModuleLineOrigin
     
     
     
     
    var moduleID: String? = nil

    private enum CodingKeys: String, CodingKey { case text, reason, origin, moduleID }
}

extension ModuleIgnoredEntry {
     
     
     
     
     
     
     
     
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decode(String.self, forKey: .text)
        let origin = try c.decode(ModuleLineOrigin.self, forKey: .origin)
        let moduleID = try c.decodeIfPresent(String.self, forKey: .moduleID)
        let reason: ModuleIgnoredReason
        do {
            reason = try c.decode(ModuleIgnoredReason.self, forKey: .reason)
        } catch {
            guard c.contains(.reason) else { throw error }
            guard let retired = (try? c.decode(RetiredReason.self, forKey: .reason))?.now else { throw UnknownReason(underlying: error) }
            reason = retired
        }
        self.init(text: text, reason: reason, origin: origin, moduleID: moduleID)
    }

     
     
    struct UnknownReason: Error {
        let underlying: Error
    }

     
     
    static let scriptNotDownloadedYet = ModuleSentence.app("This script is not downloaded yet; it will be at the next update.", arguments: [])

     
     
     
    private struct RetiredReason: Decodable {
        struct Limit: Decodable { let _0: String }
        struct Nothing: Decodable {}
        let platformCannot: Limit?
         
         
         
        let boxJSNotSupported: Nothing?

        var now: ModuleIgnoredReason? {
            if boxJSNotSupported != nil { return .scriptAddressNotSecure }
            return platformCannot?._0 == "scriptTooLargeHere" ? .scriptDownloadFailed(ModuleIgnoredEntry.scriptNotDownloadedYet) : nil
        }
    }

     
     
    struct IfReadable: Decodable {
        let entry: ModuleIgnoredEntry?

        init(from decoder: Decoder) throws {
            do {
                entry = try ModuleIgnoredEntry(from: decoder)
            } catch is UnknownReason {
                entry = nil
            }
        }
    }
}

 
enum ModuleRefusal: Error, Equatable, Sendable {
     
     
     
     
    case quantumultX
    case notAModule
     
    case otherPlatform([String])
    case notText
     
     
     
    case tooLarge(Int)
    case unreadableYAML(String)
    case notAnAddress
     
     
    case requirementNotMet
}

 

 
 
 
 
 
 
struct ModuleIR: Equatable, Sendable {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var manifest: ModuleManifest
    var mitmHostLines: [ModuleHostListLine]
    var forceHTTPEngineHostLines: [ModuleHostListLine]
     
    var routingRules: [ModuleRoutingRule]
     
    var rewriteRules: [ModuleRewriteRule]
     
    var engineRules: [ModuleEngineRule] = []
    var scripts: [ModuleScript]
     
    var hosts: [ModuleHostMapping] = []
     
    var edits: [ModuleConfigurationEdit] = []
     
    var deviceSettings: [ModuleDeviceSetting] = []
     
    var inEffect: [ModuleSettingInEffect] = []
     
    var changes: [ModuleChange] = []
     
    var notes: [ModuleLineNote] = []
     
    var ruleSets: [ModuleRuleSet] = []
     
    var answerFiles: [ModuleAnswerFileReference] = []
     
     
     
    var appScripts: [ModuleAppScript] = []
    var ignored: [ModuleIgnoredEntry]
     
    var panels: [ModulePanel] = []
     
     
     
     
    var mitmHTTP2: Bool? = nil

     
     
     
     
    var mitmOverHTTP2: Bool { manifest.format != .surge || mitmHTTP2 == true }

    static func empty(_ manifest: ModuleManifest) -> ModuleIR {
        ModuleIR(schemaVersion: currentSchemaVersion, manifest: manifest, mitmHostLines: [],
                        forceHTTPEngineHostLines: [], routingRules: [], rewriteRules: [], scripts: [], ignored: [])
    }

     
     
     
     
     
     
     
     
     
     
     
    var effectiveCount: Int {
        let lines = routingRules.map(\.origin) + rewriteRules.map(\.origin) + engineRules.map(\.origin) + scripts.map(\.origin)
        let written = forceHTTPEngineHostLines.filter { !lines.contains($0.origin) }
        return (mitmHostLines + written).reduce(0) { $0 + $1.entries.count }
            + routingRules.count + rewriteRules.count + engineRules.count + scripts.count
            + hosts.count + edits.count + deviceSettings.count + inEffect.count + ruleSets.count + panels.count
    }

     
    var ignoredCount: Int { ignored.count }

     
     
    var sections: [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ origin: ModuleLineOrigin) {
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
        appScripts.forEach { add($0.origin) }
        panels.forEach { add($0.origin) }
        ignored.forEach { add($0.origin) }
        return out
    }
}

extension ModuleIR: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, manifest, sections, mitmHostLines, forceHTTPEngineHostLines, routingRules, rewriteRules
        case engineRules, scripts, hosts, edits, deviceSettings, inEffect, changes, notes, ruleSets, answerFiles, appScripts, ignored
        case mitmHTTP2, panels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let table = ModuleSectionTable.Table(try c.decodeIfPresent([String].self, forKey: .sections) ?? [])
        func list<T: Decodable>(_ key: CodingKeys) throws -> [T] { try c.decodeIfPresent([T].self, forKey: key) ?? [] }
        self = try ModuleSectionTable.$current.withValue(table) {
            var ir = ModuleIR(schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
                            manifest: try c.decode(ModuleManifest.self, forKey: .manifest),
                            mitmHostLines: try list(.mitmHostLines), forceHTTPEngineHostLines: try list(.forceHTTPEngineHostLines),
                            routingRules: try list(.routingRules), rewriteRules: try list(.rewriteRules),
                            engineRules: try list(.engineRules), scripts: try list(.scripts), hosts: try list(.hosts),
                            edits: try list(.edits), deviceSettings: try list(.deviceSettings), inEffect: try list(.inEffect),
                            changes: try list(.changes), notes: try list(.notes),
                            ruleSets: try list(.ruleSets), answerFiles: try list(.answerFiles),
                            appScripts: try list(.appScripts),
                             
                            ignored: try c.decodeIfPresent([ModuleIgnoredEntry.IfReadable].self, forKey: .ignored)?.compactMap(\.entry) ?? [])
            ir.panels = try list(.panels)
            return ir
        }
        mitmHTTP2 = try c.decodeIfPresent(Bool.self, forKey: .mitmHTTP2)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let sections = self.sections
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(manifest, forKey: .manifest)
        if !sections.isEmpty { try c.encode(sections, forKey: .sections) }
        try ModuleSectionTable.$current.withValue(ModuleSectionTable.Table(sections)) {
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
            try list(appScripts, .appScripts)
            try list(ignored, .ignored)
            try list(panels, .panels)
        }
        try c.encodeIfPresent(mitmHTTP2, forKey: .mitmHTTP2)
    }
}

struct ModulePorts: Codable, Equatable, Sendable {
     
    let engine: UInt16
     
    let reinject: UInt16
}

 
 
 
 
 
struct ModuleReinjectCredentials: Codable, Equatable, Sendable {
    let username: String
    let password: String

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static func random() -> ModuleReinjectCredentials {
        func word() -> String {
            var generator = SystemRandomNumberGenerator()
            return String((0..<24).map { _ in alphabet[Int(generator.next(upperBound: UInt(alphabet.count)))] })
        }
        return ModuleReinjectCredentials(username: word(), password: word())
    }

     
     
     
    var isWellFormed: Bool {
        [username, password].allSatisfy { word in
            !word.isEmpty && word.unicodeScalars.allSatisfy { $0.isASCII && Self.alphabet.contains(Character($0)) }
        }
    }
}

 
 
 
 
typealias ModuleEngineProxyCredentials = ModuleReinjectCredentials

 
 
struct ModuleGlobalManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Module: Codable, Equatable, Sendable {
        let id: String
        let name: String
         
         
         
        let irSHA256: String
        let effectiveCount: Int
        let ignoredCount: Int
         
         
         
         
         
        var leftOutOrigins: [ModuleLineOrigin]? = nil
         
         
         
        var http2: Bool? = nil
    }

    var schemaVersion: Int
     
     
     
     
    var enabled: Bool
     
    var modules: [Module]
    var mitmHosts: ModuleHostList
    var forceHTTPEngineHosts: ModuleHostList
     
     
     
    var routingRules: [Rule]
    var ports: ModulePorts?
     
    var caFingerprintSHA256: String?
     
     
     
     
     
    var reinjectCredentials: ModuleReinjectCredentials?
     
     
     
     
    var engineProxyCredentials: ModuleEngineProxyCredentials?
    var publishedAt: Date
     
     
     
     
     
     
    var settings: [ModuleSettings]? = nil
     
     
     
     
    var ruleProviders: [RuleProvider]? = nil
}

extension ModuleGlobalManifest {
     
     
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
        var edits: [ModuleConfigurationEdit] = []
        var hosts: [ModuleHostMapping] = []
        var deviceSettings: [ModuleDeviceSetting] = []
         
        var changes: [ModuleChange] = []

        init(moduleID: String, edits: [ModuleConfigurationEdit] = [], hosts: [ModuleHostMapping] = [],
             deviceSettings: [ModuleDeviceSetting] = [], changes: [ModuleChange] = []) {
            self.moduleID = moduleID
            self.edits = edits
            self.hosts = hosts
            self.deviceSettings = deviceSettings
            self.changes = changes
        }

         
        init?(moduleID: String, ir: ModuleIR) {
            guard !ir.edits.isEmpty || !ir.hosts.isEmpty || !ir.deviceSettings.isEmpty || !ir.changes.isEmpty else { return nil }
            self.init(moduleID: moduleID, edits: ir.edits, hosts: ir.hosts, deviceSettings: ir.deviceSettings, changes: ir.changes)
        }

        private enum CodingKeys: String, CodingKey { case moduleID, edits, hosts, deviceSettings, changes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(moduleID: try c.decode(String.self, forKey: .moduleID),
                      edits: try c.decodeIfPresent([ModuleConfigurationEdit].self, forKey: .edits) ?? [],
                      hosts: try c.decodeIfPresent([ModuleHostMapping].self, forKey: .hosts) ?? [],
                      deviceSettings: try c.decodeIfPresent([ModuleDeviceSetting].self, forKey: .deviceSettings) ?? [],
                      changes: try c.decodeIfPresent([ModuleChange].self, forKey: .changes) ?? [])
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

     
    static func settings(_ modules: [(moduleID: String, ir: ModuleIR)]) -> [ModuleSettings]? {
        let out = modules.compactMap { ModuleSettings(moduleID: $0.moduleID, ir: $0.ir) }
        return out.isEmpty ? nil : out
    }

     
     
     
     
     
     
     
    struct Rule: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
        var head: String
        var policy: ModuleRulePolicy
        var params: [String]
        var choice: String?
         
         
        var appended = false

        init(head: String, policy: ModuleRulePolicy, params: [String] = [], choice: String? = nil, appended: Bool = false) {
            self.head = head
            self.policy = policy
            self.params = params
            self.choice = choice
            self.appended = appended
        }

         
         
        init(_ rule: ModuleRoutingRule, choice: String? = nil) {
            let kernel = rule.policy.kernelName
            self.init(head: rule.head, policy: kernel.map { .builtIn($0) } ?? rule.policy,
                      params: rule.params, choice: kernel == nil ? choice : nil, appended: rule.appended)
        }

         
        init(line: String) {
            self.init(ModuleRoutingRule(line: line, origin: ModuleLineOrigin(section: "", line: 0)))
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
            self.init(head: try c.decode(String.self, forKey: .head), policy: try c.decode(ModuleRulePolicy.self, forKey: .policy),
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

 
 
 
enum ModuleJSON {
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
