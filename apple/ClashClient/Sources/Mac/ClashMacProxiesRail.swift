import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
enum ClashMacProxiesRail {
     
     
    static func page(_ configuration: ProxiesPageConfiguration, selfBuiltNodes: [String] = [],
                     removableNodes: [String] = [], quotesConfigurationName: Bool = false) -> ClashProxiesConfigurationPage {
        var page = configuration.page()
        page.quotesConfigurationName = quotesConfigurationName
         
         
        let held = configuration.sourceNames != nil
        page.offersGroupDetails = held
        page.offersNewGroup = held
        page.offersGroupReorder = held
        page.offersGroupDeletion = held
         
        page.offersNodeRemoval = held
        page.selfBuiltNodes = selfBuiltNodes
         
        page.removableNodes = removableNodes
        return page
    }

     
     
     
     
    static func removableNodes(profileID: String, in snapshot: ConfigurationLibrarySnapshot,
                               store: ConfigurationLibraryStore) -> [String] {
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return [] }
        let document: OrderedJSON?
        if recipe.preservesOriginal == true {
            document = try? OrderedJSON.parse(store.payload(recipe.ruleSource).documentJSON)
        } else {
            document = try? store.composition(ofRecipe: profileID, in: snapshot,
                                              resolveInput: ConfigurationCenterSourceBridge.boundInput).document
        }
        guard case .array(let nodes)? = document?.topLevelValue("proxies") else { return [] }
        return nodes.compactMap { node in
            if case .string(let name)? = node.topLevelValue("name") { return name }
            return nil
        }
    }

     
     
     
     
    static func selfBuiltNodes(profileID: String, in snapshot: ConfigurationLibrarySnapshot,
                               document: (ConfigurationSourceRecord) throws -> OrderedJSON) -> [String] {
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return [] }
        return recipe.sources.compactMap { pin in snapshot.sources.first { $0.id == pin.id } }
            .filter { record in
                guard record.nodeChain == nil, case .customNodes = record.origin else { return false }
                return true
            }
            .flatMap { record -> [String] in
                guard case .array(let nodes)? = (try? document(record))?.topLevelValue("proxies") else { return [] }
                return nodes.compactMap { node in
                    if case .string(let name)? = node.topLevelValue("name") { return name }
                    return nil
                }
            }
    }

     
     
    static func sources(_ chosen: [String], adding id: String) -> [String] {
        chosen.contains(id) ? chosen : chosen + [id]
    }
}

 
 
 
 
@MainActor
final class ClashMacProxiesPageMore: ObservableObject {
    @Published var reorderGroups: (() -> Void)?
    @Published var updateNodeSources: (() -> Void)?
     
     
     
    var openNodeSources: (() -> Void)?
}
