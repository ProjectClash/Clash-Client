import Foundation

 
 
 
 
public enum ClashProxiesGroupMenuItem: String, CaseIterable, Equatable, Sendable {
     
    case testLatency
     
    case jumpToCurrentNode
     
    case unfix
     
    case viewDetails
     
    case collapseAllGroups
     
    case reorderGroups
     
    case deleteGroup
}

public enum ClashProxiesGroupMenu {
     
     
     
     
     
    public static func items(isConnected: Bool, showsLocate: Bool, showsUnpin: Bool,
                             page: ClashProxiesConfigurationPage?) -> [ClashProxiesGroupMenuItem] {
        guard let page, page.offersGroupDetails else { return [] }
        var items: [ClashProxiesGroupMenuItem] = []
        if isConnected { items.append(.testLatency) }
        if showsLocate { items.append(.jumpToCurrentNode) }
        if showsUnpin { items.append(.unfix) }
        items += [.viewDetails, .collapseAllGroups]
        if page.offersGroupReorder { items.append(.reorderGroups) }
        if page.offersGroupDeletion { items.append(.deleteGroup) }
        return items
    }

     
     
    public static func title(_ item: ClashProxiesGroupMenuItem) -> ClashDisplayText {
        switch item {
        case .testLatency: .copy("Test Latency")
        case .jumpToCurrentNode: .copy("Jump to Current Node")
        case .unfix: .copy("Unfix")
        case .viewDetails: .copy("View Details")
        case .collapseAllGroups: .copy("Collapse All Groups")
        case .reorderGroups: .copy("Reorder Policy Groups")
        case .deleteGroup: .copy("Delete Policy Group")
        }
    }
}
