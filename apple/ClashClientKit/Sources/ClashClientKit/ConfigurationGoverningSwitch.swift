import Foundation

 
 
public struct ConfigurationGoverningSwitch: Equatable, Sendable {
    public let field: ConfigurationField
    public let steps: [ConfigurationDocumentStep]

    public init(field: ConfigurationField, steps: [ConfigurationDocumentStep]) {
        self.field = field
        self.steps = steps
    }
}

 
 
 
 
public struct ConfigurationOffSwitchSummary: Equatable, Sendable {
    public let control: ConfigurationGoverningSwitch
    public let waiting: [ConfigurationField]
    public let working: Int

    public init(control: ConfigurationGoverningSwitch, waiting: [ConfigurationField], working: Int) {
        self.control = control
        self.waiting = waiting
        self.working = working
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public extension ConfigurationFieldCatalog {
     
    static let switchKeys = ["enable", "enabled"]

     
     
     
    static let partialSwitches: [String: Set<String>] = [
         
         
         
         
         
        "proxy-providers.*.health-check.enable": ["interval"],
    ]

     
     
     
    static let auditedSwitchPaths: Set<String> = ["sniffer.enable", "mitm.enable", "ntp.enable", "tuic-server.enable", "iptables.enable"]
    static let auditedSwitchSuffixes = [
        ".smux.enabled", ".smux.brutal-opts.enabled", ".ech-opts.enable", ".realm-opts.enable", ".ss-opts.enabled",
        ".transport-layer-padding.enabled", ".mux-option.brutal.enabled", ".shadow-tls.enable", ".res-tls.enable",
        ".jls-config.enable", ".kcp-tun.enable", ".simple-obfs.enable", ".mekya-config.enable", ".mekya-config.kcp.enable",
        ".mkcp-config.enable", ".ss-option.enabled",
    ]

     
     
     
    static func isAuditedSwitch(_ path: String) -> Bool {
        partialSwitches[path] != nil || auditedSwitchPaths.contains(path)
            || auditedSwitchSuffixes.contains { path.hasSuffix($0) }
    }

     
     
    static func governs(switchAt path: String, child: String) -> Bool {
        partialSwitches[path].map { $0.contains(child) } ?? true
    }

     
     
     
     
     
     
     
    func governingSwitches(of field: ConfigurationField, at steps: [ConfigurationDocumentStep]) -> [ConfigurationGoverningSwitch] {
        var components = Self.catalogComponents(field.path)
        var documentSteps = steps
        var switches: [ConfigurationGoverningSwitch] = []
        while components.count >= 2, !documentSteps.isEmpty {
            let dropped = components.removeLast()
            documentSteps.removeLast()
            let parent = components.joined(separator: ".")
            for key in Self.switchKeys {
                let path = parent + "." + key
                guard path != field.path, let candidate = self.field(atCatalogPath: path), candidate.kind == .toggle,
                      candidate.platformDecision?.when != .always else { continue }
                 
                 
                 
                if dropped != key, Self.governs(switchAt: path, child: dropped) {
                    switches.append(ConfigurationGoverningSwitch(field: candidate, steps: documentSteps + [.key(key)]))
                }
            }
             
             
            if let next = components.last, next.contains("[") { break }
        }
        return switches
    }

     
     
     
    func offSwitch(for field: ConfigurationField, at steps: [ConfigurationDocumentStep],
                   in document: OrderedJSON) -> ConfigurationGoverningSwitch? {
        governingSwitches(of: field, at: steps).first { control in
            switch Self.value(at: control.steps, in: document) {
            case .scalar(let token)?: return token.lowercased() != "true"
            case .string(let text)?: return text.lowercased() != "true"
            case nil: return control.field.defaultText?.lowercased() != "true"
            default: return false
            }
        }
    }

     
     
    func isInactive(_ field: ConfigurationField, at steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> Bool {
        offSwitch(for: field, at: steps, in: document) != nil
    }

     
     
     
     
    func offSwitchSummary(over rows: [(field: ConfigurationField, steps: [ConfigurationDocumentStep])],
                          in document: OrderedJSON) -> ConfigurationOffSwitchSummary? {
        let offs = rows.map { offSwitch(for: $0.field, at: $0.steps, in: document) }
        guard let control = offs.compactMap({ $0 }).first else { return nil }
        var waiting: [ConfigurationField] = []
        var working = 0
        for (row, off) in zip(rows, offs) where row.field.path != control.field.path {
            if off == control { waiting.append(row.field) } else if off == nil { working += 1 }
        }
        return ConfigurationOffSwitchSummary(control: control, waiting: waiting, working: working)
    }

     
     
     
    static func catalogComponents(_ path: String) -> [String] {
        var components: [String] = []
        var current = ""
        var depth = 0
        for character in path {
            switch character {
            case "[": depth += 1; current.append(character)
            case "]": depth -= 1; current.append(character)
            case "." where depth == 0: components.append(current); current = ""
            default: current.append(character)
            }
        }
        components.append(current)
        return components
    }

     
    static func value(at steps: [ConfigurationDocumentStep], in document: OrderedJSON) -> OrderedJSON? {
        var node: OrderedJSON? = document
        for step in steps {
            switch (step, node) {
            case (.key(let key), .object(let entries)?): node = entries.first { $0.key == key }?.value
            case (.index(let index), .array(let items)?): node = items.indices.contains(index) ? items[index] : nil
            default: return nil
            }
        }
        return node
    }
}
