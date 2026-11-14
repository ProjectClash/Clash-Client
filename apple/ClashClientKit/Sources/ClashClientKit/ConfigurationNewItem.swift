import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ConfigurationNewItem: Equatable, Sendable {
    public struct Asked: Identifiable, Equatable, Sendable {
        public enum Control: Equatable, Sendable {
             
            case text
             
            case number
             
             
            case choice([String])
             
            case choices([String])
            case flag
             
            case lines
             
            case pair
             
            case group
        }

        public let key: String
        public let field: ConfigurationField
        public let isRequired: Bool
         
        public let children: [Asked]
         
        public var names: [String] = []

        public var id: String { field.path }

        public init(key: String, field: ConfigurationField, isRequired: Bool, children: [Asked], names: [String] = []) {
            self.key = key
            self.field = field
            self.isRequired = isRequired
            self.children = children
            self.names = names
        }

         
         
        public var control: Control {
            switch field.kind {
            case .number: return .number
            case .select: return .choice(field.offeredValues().map(\.value))
            case .reference: return .choice(names)
            case .multiSelect: return .choices(field.offeredValues().map(\.value))
            case .toggle: return .flag
            case .textList: return .lines
            case .map: return .pair
            case .object, .objectList: return .group
            default: return .text
            }
        }

         
         
         
        var defaultsOn: Bool { field.defaultFlag }

        public var initialValue: Value {
            switch control {
            case .text, .number: return .text("")
            case .choice: return .choice("")
            case .choices: return .choices([])
            case .flag: return .flag(defaultsOn)
            case .lines: return .lines([""])
            case .pair: return .pair(key: "", value: "")
            case .group: return .group(Dictionary(uniqueKeysWithValues: children.map { ($0.key, $0.initialValue) }))
            }
        }

         
         
        public func isComplete(_ value: Value?) -> Bool {
            let value = value ?? initialValue
            if !isRequired, isEmpty(value) { return true }
            switch (control, value) {
            case (.text, .text(let text)):
                return !Self.trimmed(text).isEmpty
            case (.number, .text(let text)):
                guard let number = Double(Self.trimmed(text)) else { return false }
                 
                 
                 
                 
                if field.zeroMeansUnset, number == 0 { return !isRequired }
                if let min = field.min, number < min { return false }
                if let max = field.max, number > max { return false }
                return true
            case (.choice, .choice(let choice)):
                return !choice.isEmpty
            case (.choices, .choices(let chosen)):
                return !chosen.isEmpty
            case (.flag, .flag):
                return true
            case (.lines, .lines(let lines)):
                return lines.contains { !Self.trimmed($0).isEmpty }
            case (.pair, .pair(let key, let value)):
                return !Self.trimmed(key).isEmpty && !Self.trimmed(value).isEmpty
            case (.group, .group(let values)):
                return children.allSatisfy { $0.isComplete(values[$0.key]) }
            default:
                return false
            }
        }

         
        public func isEmpty(_ value: Value) -> Bool {
            switch value {
            case .text(let text), .choice(let text): return Self.trimmed(text).isEmpty
            case .choices(let chosen): return chosen.isEmpty
             
             
             
             
            case .flag(let on): return !isRequired && on == defaultsOn
            case .lines(let lines): return !lines.contains { !Self.trimmed($0).isEmpty }
            case .pair(let key, let value): return Self.trimmed(key).isEmpty && Self.trimmed(value).isEmpty
            case .group(let values): return children.allSatisfy { child in values[child.key].map(child.isEmpty) ?? true }
            }
        }

         
         
         
        public func hasProblem(_ value: Value?) -> Bool {
            switch value ?? initialValue {
            case .text(let text):
                return ConfigurationFieldValidation.problem(text, field: field) != nil
            case .lines(let lines):
                let entries = lines.map(Self.trimmed).filter { !$0.isEmpty }
                return entries.indices.contains { index in
                    var others = entries
                    others.remove(at: index)
                    return ConfigurationFieldValidation.problem(entries[index], format: field.format, path: field.path,
                                                                allowed: field.values ?? [], siblings: others) != nil
                }
            case .group(let values):
                return children.contains { $0.hasProblem(values[$0.key]) }
            default:
                return false
            }
        }

         
        public func node(_ value: Value?) -> OrderedJSON? {
            let value = value ?? initialValue
            if isEmpty(value) { return nil }
            switch (control, value) {
            case (.text, .text(let text)):
                return .string(Self.trimmed(text))
            case (.number, .text(let text)):
                return .scalar(Self.trimmed(text))
            case (.choice, .choice(let choice)):
                return .string(choice)
            case (.choices(let order), .choices(let chosen)):
                let ordered = order.filter(chosen.contains) + chosen.filter { !order.contains($0) }
                if let separator = field.separator { return .string(ordered.joined(separator: separator)) }
                return .array(ordered.map(OrderedJSON.string))
            case (.flag, .flag(let on)):
                return .scalar(on ? "true" : "false")
            case (.lines, .lines(let lines)):
                return .array(lines.map(Self.trimmed).filter { !$0.isEmpty }.map(OrderedJSON.string))
            case (.pair, .pair(let key, let value)):
                let text = Self.trimmed(value)
                let node: OrderedJSON = field.value?.kind == .number && Double(text) != nil ? .scalar(text) : .string(text)
                return .object([(key: Self.trimmed(key), value: node)])
            case (.group, .group(let values)):
                let object = OrderedJSON.object(children.compactMap { child in
                    child.node(values[child.key]).map { (key: child.key, value: $0) }
                })
                return field.kind == .objectList ? .array([object]) : object
            default:
                return nil
            }
        }

        static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

     
    public enum Value: Equatable, Sendable {
        case text(String)
        case choice(String)
        case choices([String])
        case flag(Bool)
        case lines([String])
        case pair(key: String, value: String)
        case group([String: Value])
    }

    public let type: String?
    public let asked: [Asked]

    public init(type: String?, asked: [Asked]) {
        self.type = type
        self.asked = asked
    }

     
     
    public static let commonKeys: Set<String> = ["port", "listen"]

     
     
     
     
     
     
     
    public static func asksForItsGroup(_ field: ConfigurationField) -> Bool {
        field.requiredOneOf?.first == key(of: field)
    }

     
    public static func key(of field: ConfigurationField) -> String {
        field.path.split(separator: ".").last.map(String.init) ?? field.path
    }

     
    public static func fields(under catalogPath: String, catalog: ConfigurationFieldCatalog) -> [ConfigurationField] {
        let base = catalogPath + "."
        return catalog.fields.filter { field in
            guard field.path.hasPrefix(base) else { return false }
            let rest = field.path.dropFirst(base.count)
            return !rest.isEmpty && !rest.contains(".") && !rest.contains("[") && rest != "*"
        }
    }

     
     
     
     
     
    public static func types(ofList listPath: String, catalog: ConfigurationFieldCatalog) -> [String] {
        let prefix = listPath + "["
        var named: [String] = []
        for field in catalog.fields where field.path.hasPrefix(prefix) {
            let rest = field.path.dropFirst(prefix.count)
            guard let close = rest.firstIndex(of: "]") else { continue }
            let type = String(rest[..<close])
            guard !type.isEmpty, !type.contains("."), !type.contains("[") else { continue }
            if rest[rest.index(after: close)...] == ".type", field.kind == .select, let values = field.values, !values.isEmpty {
                return field.offeredValues().map(\.value)
            }
            if !named.contains(type) { named.append(type) }
        }
        return named
    }

     
     
    public static func make(listPath: String, type: String?, in document: OrderedJSON,
                            catalog: ConfigurationFieldCatalog) -> ConfigurationNewItem {
        let fields = Self.fields(under: listPath + (type.map { "[" + $0 + "]" } ?? "[]"), catalog: catalog)
            .filter { key(of: $0) != "type" }
        let describesRequired = fields.contains(where: \.isRequired)
        var asked: [Asked] = []
        for field in fields {
            let key = key(of: field)
            let required: Bool
            if describesRequired {
                if field.isRequired || asksForItsGroup(field) {
                    required = true
                } else if commonKeys.contains(key) {
                    required = false
                } else {
                    continue
                }
            } else {
                switch field.kind {
                case .text, .number, .select, .multiSelect, .suggest: required = true
                case .reference: required = false
                default: continue
                }
            }
            asked.append(Self.asked(field, key: key, isRequired: required, in: document, catalog: catalog))
        }
        return ConfigurationNewItem(type: type, asked: asked)
    }

    private static func asked(_ field: ConfigurationField, key: String, isRequired: Bool, in document: OrderedJSON,
                              catalog: ConfigurationFieldCatalog) -> Asked {
        var children: [Asked] = []
        switch field.kind {
        case .object:
            children = requiredChildren(under: field.path, in: document, catalog: catalog)
        case .objectList:
            children = requiredChildren(under: field.path + "[]", in: document, catalog: catalog)
        default:
            break
        }
        var asked = Asked(key: key, field: field, isRequired: isRequired, children: children)
        if field.kind == .reference {
            asked.names = ConfigurationReferenceNames.names(field.refers ?? [.policy], in: document)
        }
        return asked
    }

     
    private static func requiredChildren(under catalogPath: String, in document: OrderedJSON,
                                         catalog: ConfigurationFieldCatalog) -> [Asked] {
        fields(under: catalogPath, catalog: catalog).filter(\.isRequired).map { field in
            asked(field, key: key(of: field), isRequired: true, in: document, catalog: catalog)
        }
    }

    public var initialValues: [String: Value] {
        Dictionary(uniqueKeysWithValues: asked.map { ($0.key, $0.initialValue) })
    }

     
    public func isComplete(_ values: [String: Value]) -> Bool {
        asked.allSatisfy { $0.isComplete(values[$0.key]) }
    }

     
     
    public func hasProblem(_ values: [String: Value]) -> Bool {
        asked.contains { $0.hasProblem(values[$0.key]) }
    }

     
     
     
    public func canAdd(_ values: [String: Value]) -> Bool {
        guard isComplete(values), !hasProblem(values), case .object(let entries) = item(values) else { return false }
        return entries.contains { $0.key != "type" }
    }

     
     
    public func item(_ values: [String: Value]) -> OrderedJSON {
        var entries: [(key: String, value: OrderedJSON)] = []
        if let name = asked.first(where: { $0.key == "name" }), let node = name.node(values["name"]) {
            entries.append((key: "name", value: node))
        }
        if let type { entries.append((key: "type", value: .string(type))) }
        for field in asked where field.key != "name" {
            if let node = field.node(values[field.key]) { entries.append((key: field.key, value: node)) }
        }
        return .object(entries)
    }
}
