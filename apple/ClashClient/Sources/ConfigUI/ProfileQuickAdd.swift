import ClashClientKit
import Foundation

 
 
 
 
 
 
struct ProfileQuickAddOutcome: Equatable {
    let id: String
    let isFirstUserProfile: Bool
     
     
    var runsAsOriginal = false
}

enum ProfileQuickAddInput: Equatable {
     
     
     
     
    case link(String, rules: InstallLinkRuleScheme? = nil)
     
     
     
     
    case document(fileName: String, data: Data, rules: InstallLinkRuleScheme? = nil)
     
    case nodeShareLink
     
     
     
     
     
    case nodes(String)
    case nothing

    static let pastedDocumentName = "Configuration.yaml"

    static func classify(_ raw: String) -> ProfileQuickAddInput {
        switch PastedContentClassifier.classify(raw) {
        case .empty:
            return .nothing
        case .link(let url, _, let rules):
            return .link(url, rules: rules)
        case .configText(let body):
            return .document(fileName: pastedDocumentName, data: Data(body.utf8))
        case .nodeShareLinks:
            return .nodeShareLink
        case .unrecognized:
             
             
            return .link(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
