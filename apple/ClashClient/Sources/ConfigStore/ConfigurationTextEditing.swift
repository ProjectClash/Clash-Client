import Foundation
import Clash

 
enum ConfigurationTextPathStep: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case key(String)
    case index(Int)

    init(stringLiteral value: String) { self = .key(value) }
    init(integerLiteral value: Int) { self = .index(value) }
}

 
 
enum ConfigurationTextEdit: Equatable, Sendable {
     
    case set(json: String)
     
     
    case insert(json: String)
     
    case insertBefore(key: String, json: String)
    case delete
     
    case move(to: Int)
     
    case rename(to: String)
}

 
 
enum ConfigurationReferenceKind: String, Sendable, CaseIterable {
    case proxyGroup, ruleProvider, proxyProvider
}

 
 
 
struct ConfigurationTextEditRefusal: LocalizedError, Equatable, Sendable {
    enum Code: String, Sendable, CaseIterable {
        case anchor, encrypted, multiDocument, notFound, typeMismatch, unsupportedStyle
        case invalidRequest, unsafeEdit, unsafeReference
    }

     
    let code: Code?
    let rawCode: String
     
    let message: String

    init(rawCode: String, message: String) {
        self.code = Code(rawValue: rawCode)
        self.rawCode = rawCode
        self.message = message
    }

     
    var editTheSourceInstead: Bool {
        switch code {
        case .anchor, .encrypted, .multiDocument, .unsupportedStyle, .unsafeEdit, .unsafeReference: return true
        case .notFound, .typeMismatch, .invalidRequest, nil: return false
        }
    }

     
    var errorDescription: String? {
        switch code {
        case .anchor: return "This part uses YAML anchors or aliases. Edit it in the source."
        case .encrypted: return "This configuration is encrypted. Edit it in the source."
        case .multiDocument: return "This file holds more than one YAML document. Edit it in the source."
        case .notFound: return "That item is no longer in the configuration."
        case .typeMismatch: return "That item is not the kind of value this change is for."
        case .unsupportedStyle: return "This part is written in a way the editor cannot change safely. Edit it in the source."
        case .invalidRequest: return "The configuration cannot take this change."
        case .unsafeEdit: return "This change would reach further than it should, so nothing was saved. Edit it in the source."
        case .unsafeReference: return "A place that names it cannot be rewritten safely, so nothing was renamed. Edit it in the source."
        case nil: return "The core refused this change."
        }
    }

     
    var failureReason: String? { message.isEmpty ? nil : message }
}

 
 
struct ConfigurationRuleMatch: Decodable, Equatable, Sendable {
    let matched: Bool
     
    let index: Int?
    let rule: String?
    let policy: String?
    let undecided: Bool?
     
     
    let reason: String?
}

 
struct ConfigurationRuleQuery: Encodable, Equatable, Sendable {
    var host: String?
    var ip: String?
    var port: Int?
    var network: String?
    var srcIP: String?
    var srcPort: Int?
     
     
     
    var inPort: Int?
    var `protocol`: String?
}

 
 
 
 
enum ConfigurationTextEditing {
     
     
     
     
     
     
    static func edit(_ original: String, at path: [ConfigurationTextPathStep], _ edit: ConfigurationTextEdit) throws -> String {
        try editAnswering(original, at: path, edit).text
    }

     
     
    struct EditAnswer {
        let text: String
        let documentJSON: String?
        let shapeError: String?
    }

    static func editAnswering(_ original: String, at path: [ConfigurationTextPathStep],
                              _ edit: ConfigurationTextEdit) throws -> EditAnswer {
         
         
         
         
        if let cut = largeRulesCut(original, editing: path) {
            let answer = try editAnswering(cut.rest, at: path, edit)
            if let spliced = cut.splicing(into: answer.text) {
                return EditAnswer(text: spliced, documentJSON: nil, shapeError: answer.shapeError)
            }
        }
        let (op, value) = try operation(edit)
        var error: NSError?
        let box = AppCore.editYAMLWithOptions(original, try pathJSON(path), op, value,
                                              #"{"document":true,"validateShape":true}"#, &error)
        let answer = try answerText(box, error, operation: "EditYAMLForIOSWithOptions")
         
         
        let members = JSONMembers.rawValues(["ok", "text", "code", "message", "document", "documentError", "shapeError"],
                                            in: answer)
        let text = try editedText(members)
        let shapeError = JSONMembers.string(members["shapeError"])
        let document = members["documentError"] == nil ? members["document"] : nil
        if let document {
            ConfigTransforms.KnownDocuments.shared.remember(document, for: text)
            if shapeError == nil {
                ConfigTransforms.AcceptedSources.shared.insert(ConfigTransforms.AcceptedSources.digest(text))
            }
        }
        return EditAnswer(text: text, documentJSON: document, shapeError: shapeError)
    }

     
     
     
    static func editAlone(_ original: String, at path: [ConfigurationTextPathStep],
                          _ edit: ConfigurationTextEdit) throws -> String {
        if let cut = largeRulesCut(original, editing: path),
           let spliced = cut.splicing(into: try editAlone(cut.rest, at: path, edit)) {
            return spliced
        }
        let (op, value) = try operation(edit)
        var error: NSError?
        let box = AppCore.editYAML(original, try pathJSON(path), op, value, &error)
        let answer = try answerText(box, error, operation: "EditYAMLForIOS")
        return try editedText(JSONMembers.rawValues(["ok", "text", "code", "message"], in: answer))
    }

     
     
     
    private static func largeRulesCut(_ original: String, editing path: [ConfigurationTextPathStep])
        -> TopLevelYAMLSections.Cut? {
        guard path.first != .key("rules"), !path.isEmpty, ConfigTransforms.keepsLargeRuleLines(original) else { return nil }
        return TopLevelYAMLSections.cutting(["rules"], from: original)
    }

     
     
     
    static func rename(_ original: String, kind: ConfigurationReferenceKind, from oldName: String,
                       to newName: String) throws -> (text: String, changed: Int) {
         
         
         
         
         
         
         
         
         
         
        if ConfigTransforms.hasLargeRuleSection(original), let cut = TopLevelYAMLSections.cutting(["rules"], from: original),
           let section = cut.sectionText("rules"), let lines = RuleLines(section) {
            if kind != .proxyProvider {
                let naming = try lines.indexedRules(whoseLinesHold: [oldName]).map(\.rule).filter {
                    kind == .ruleProvider ? OriginalListEdits.namesRuleSet($0, oldName) : OriginalListEdits.namesTarget($0, oldName)
                }
                if !naming.isEmpty {
                    throw OriginalEditingError.keptRulesName(Array(naming.prefix(OriginalListEdits.keptPlacesShown)))
                }
            }
            let renamed = try rename(cut.rest, kind: kind, from: oldName, to: newName)
            if let spliced = cut.splicing(into: renamed.text) { return (spliced, renamed.changed) }
        }
        var error: NSError?
        let box = AppCore.renameReferences(original, kind.rawValue, oldName, newName, &error)
        let answer = try textAnswer(box, error, operation: "RenameReferencesForIOS")
        return (answer.text, answer.changed ?? 0)
    }

     
     
     
    static func check(kind: String, itemJSON: String, contextJSON: String) throws -> String? {
        var error: NSError?
        let box = AppCore.validateItem(kind, itemJSON, contextJSON, &error)
        let data = Data(try answerText(box, error, operation: "ValidateItemForIOS").utf8)
        struct Answer: Decodable { let ok: Bool; let message: String? }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        return answer.ok ? nil : (answer.message ?? "")
    }

     
     
     
     
     
    static func checkGroupPattern(key: String, pattern: String) throws -> String? {
        let item: [String: Any] = ["name": "G", "type": "select", "proxies": ["DIRECT"], key: pattern]
        let itemJSON = String(decoding: try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]), as: UTF8.self)
        return try check(kind: "proxyGroup", itemJSON: itemJSON, contextJSON: "{}")
    }

     
    static func match(_ query: ConfigurationRuleQuery, in document: String, resourceMapJSON: String) throws -> ConfigurationRuleMatch {
        var error: NSError?
        let queryJSON = String(decoding: try JSONEncoder().encode(query), as: UTF8.self)
        let box = AppCore.matchRule(document, resourceMapJSON, queryJSON, &error)
        return try JSONDecoder().decode(ConfigurationRuleMatch.self,
                                        from: Data(try answerText(box, error, operation: "MatchRuleForIOS").utf8))
    }

     

    static func pathJSON(_ path: [ConfigurationTextPathStep]) throws -> String {
        let steps: [Any] = path.map {
            switch $0 {
            case .key(let key): return key
            case .index(let index): return index
            }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: steps, options: [.fragmentsAllowed]), as: UTF8.self)
    }

    private static func jsonString(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]), as: UTF8.self)
    }

    private static func operation(_ edit: ConfigurationTextEdit) throws -> (op: String, value: String) {
        switch edit {
        case .set(let json): return ("set", json)
        case .insert(let json): return ("insert", json)
        case .insertBefore(let key, let json): return ("insertBefore", "{\"key\":\(try jsonString(key)),\"value\":\(json)}")
        case .delete: return ("delete", "")
        case .move(let index): return ("move", String(index))
        case .rename(let key): return ("rename", try jsonString(key))
        }
    }

    private static func answerText(_ box: ClashStringBox?, _ error: NSError?, operation: String) throws -> String {
        if let error {
            if (error as Error) is CancellationError { throw CancellationError() }
            throw error
        }
        guard let box else { throw ConfigTransformsError.bridgeReturnedNil(operation) }
        return box.value
    }

     
    private static func editedText(_ members: [String: String]) throws -> String {
        guard members["ok"] == "true", let text = JSONMembers.string(members["text"]) else {
            throw ConfigurationTextEditRefusal(rawCode: JSONMembers.string(members["code"]) ?? "",
                                               message: JSONMembers.string(members["message"]) ?? "")
        }
        return text
    }

    private static func textAnswer(_ box: ClashStringBox?, _ error: NSError?, operation: String) throws -> (text: String, changed: Int?) {
        try textAnswer(try answerText(box, error, operation: operation))
    }

    private static func textAnswer(_ json: String) throws -> (text: String, changed: Int?) {
        struct Answer: Decodable { let ok: Bool; let text: String?; let changed: Int?; let code: String?; let message: String? }
        let answer = try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        guard answer.ok, let text = answer.text else {
            throw ConfigurationTextEditRefusal(rawCode: answer.code ?? "", message: answer.message ?? "")
        }
        return (text, answer.changed)
    }
}
