import Foundation

 
 
public enum ClashProxiesAddItem: String, CaseIterable, Equatable, Sendable {
     
    case addNodeSource
     
    case addFromShareLink
     
    case newNode
     
    case newProxyChain

    public var title: ClashDisplayText {
        switch self {
        case .addNodeSource: .copy("Add Node Source…")
        case .addFromShareLink: .copy("Add from a Share Link…")
        case .newNode: .copy("New Node…")
        case .newProxyChain: .copy("New Proxy Chain…")
        }
    }
}
