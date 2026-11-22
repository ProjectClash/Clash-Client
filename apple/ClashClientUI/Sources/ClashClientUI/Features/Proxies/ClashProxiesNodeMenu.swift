import Foundation

 
 
 
public enum ClashProxiesNodeMenuItem: String, CaseIterable, Equatable, Sendable {
    case use
    case testLatency
    case viewDetails
    case editNode
    case copyYAML
    case remove
    case deleteNode
}

public enum ClashProxiesNodeMenu {
     
     
     
     
     
     
     
     
    public static func items(choosable: Bool, measures: Bool, isNode: Bool, isEditable: Bool,
                             isSelfBuilt: Bool, isRemovable: Bool = true,
                             page: ClashProxiesConfigurationPage?) -> [ClashProxiesNodeMenuItem] {
        guard let page, page.offersNodeRemoval else { return isEditable ? [.editNode] : [] }
        var items: [ClashProxiesNodeMenuItem] = []
        if choosable { items.append(.use) }
        if measures { items.append(.testLatency) }
        if isNode { items.append(.viewDetails) }
        if isEditable { items.append(.editNode) }
        if isNode { items.append(.copyYAML) }
        if isNode, isRemovable { items.append(.remove) }
        if isNode, isSelfBuilt { items.append(.deleteNode) }
        return items
    }

    public static func title(_ item: ClashProxiesNodeMenuItem, configurationName: String) -> ClashDisplayText {
        switch item {
        case .use: .copy("Use")
        case .testLatency: .copy("Test Latency")
        case .viewDetails: .copy("View Details")
        case .editNode: .copy("Edit Node…")
        case .copyYAML: .copy("Copy YAML")
        case .remove: .format("Remove from “%@”", [configurationName])
        case .deleteNode: .copy("Delete Node")
        }
    }
}
