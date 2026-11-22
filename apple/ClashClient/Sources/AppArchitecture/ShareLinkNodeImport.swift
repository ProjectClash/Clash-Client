import ClashClientUI
import Foundation

enum ShareLinkNodeImportError: LocalizedError, Equatable {
    case notNodes
    case bridgeReturnedNil

    var errorDescription: String? {
        switch self {
        case .notNodes:
            return "That text does not contain a node share link."
        case .bridgeReturnedNil:
            return "The share link could not be read."
        }
    }
}

 
 
 
 
 
 
 
enum ShareLinkNodeImport {
     
    static func nodes(from raw: String) throws -> [String] {
        try imported(from: raw).nodes
    }

     
     
     
     
     
     
     
     
    static func imported(
        from raw: String
    ) throws -> (nodes: [String], notHonoured: [ProxyImportIssue]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShareLinkNodeImportError.notNodes }

        let report = try ProxyImportBridge.inspect(Data(trimmed.utf8), context: .nodeBundle)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        guard !report.proxies.isEmpty else {
            throw report.issues.isEmpty
                ? ShareLinkNodeImportError.notNodes
                : ProxyImportBridgeError.rejected(report.issues)
        }
        let nodes = try report.proxies.map { proxy in
            let data = try JSONSerialization.data(
                withJSONObject: proxy,
                options: [.sortedKeys]
            )
            return String(decoding: data, as: UTF8.self)
        }
        return (nodes, report.notHonoured)
    }
}

 
 
 
 
 
 
 
struct ShareLinkPasteRefusal: Equatable {
    static let title = "Couldn’t Add This Node"

     
    let reason: ClashDisplayText
     
    let coreSentence: String?

    init(reason: ClashDisplayText, coreSentence: String? = nil) {
        self.reason = reason
        self.coreSentence = coreSentence
    }

     
     
     
     
    init(_ error: Error) {
        switch error {
        case ProxyImportBridgeError.rejected(let issues):
            guard let first = issues.first else {
                self.init(reason: .copy(ShareLinkNodeImportError.notNodes.errorDescription ?? ""))
                return
            }
            self.init(reason: Self.reason(code: first.code, scheme: first.scheme), coreSentence: first.message)
        case ProxyImportBridgeError.bridgeReturnedNil(let words) where words == ShareLinkNodeImportError.bridgeReturnedNil.errorDescription:
             
             
            self.init(reason: .copy(words))
        case ProxyImportBridgeError.bridgeReturnedNil(let words):
            self.init(reason: .copy(words == Self.unreadablePayload ? Self.nothingReadable : Self.neutral),
                      coreSentence: words)
        case ProxyImportBridgeError.refusedConfiguration(let words, _):
            self.init(reason: .copy(Self.neutral), coreSentence: words)
        case let own as LocalizedError:
             
             
            self.init(reason: .copy(own.errorDescription ?? Self.neutral))
        default:
            self.init(reason: .copy(Self.neutral), coreSentence: error.localizedDescription)
        }
    }

     
     
    static let unreadablePayload = "clash: proxy payload format is unknown"
    static let nothingReadable = "There’s no node link Clash can read in this text."
    static let neutral = "This can’t be added as a node."

     
    static func reason(code: String, scheme: String) -> ClashDisplayText {
        switch code {
        case "malformedRecord":
            return .copy("This link is missing something it needs, or isn’t written right.")
        case "coreRejected", "recognizedUnsupportedField":
            return .copy("This link has a setting Clash doesn’t support.")
        case "unknownScheme":
            return .format("Clash doesn’t recognize links that start with “%@://”.", [scheme])
        case "coreUnsupported", "subscriptionWrapper", "semanticReview":
            return .format("Clash doesn’t support “%@://” nodes yet.", [scheme])
        default:
            return .copy(neutral)
        }
    }
}
