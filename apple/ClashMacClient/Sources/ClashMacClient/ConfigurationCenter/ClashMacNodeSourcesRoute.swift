import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
public struct ClashMacNodeSourcesRoute: View {
    @ObservedObject private var library: ClashMacConfigurationLibraryModel
    private let profileID: String
    private let actions: ClashMacConfigurationInspectorActions
    private let addSource: (() -> Void)?
     
    @State private var pending = ClashMacPendingTicks()

    public init(library: ClashMacConfigurationLibraryModel, profileID: String,
                actions: ClashMacConfigurationInspectorActions, addSource: (() -> Void)?) {
        _library = ObservedObject(wrappedValue: library)
        self.profileID = profileID
        self.actions = actions
        self.addSource = addSource
    }

     
    static func chosen(in snapshot: ConfigurationLibrarySnapshot, profileID: String) -> Set<String> {
        Set(snapshot.recipes.first { $0.id == profileID }?.sources.map(\.id) ?? [])
    }

    private var sources: [ConfigurationSourceRecord] { library.snapshot.sources.filter(\.suppliesNodes) }
     
    private var stored: Set<String> { Self.chosen(in: library.snapshot, profileID: profileID) }

    public var body: some View {
        ClashMacConfigurationSourcesPage(
            sources: sources, chosen: .constant(pending.shown(stored)),
            recipe: library.snapshot.recipes.first { $0.id == profileID },
            actions: actions, toggle: toggle, addSource: addSource
        )
        .navigationTitle(Text(clash: .copy("Node Sources")))
         
         
        .onChange(of: stored) { pending.settle($0) }
    }

     
    private func toggle(_ id: String) {
        pending.press(id, on: !pending.shown(stored).contains(id))
        let shown = pending.shown(stored)
        actions.setSources(sources.map(\.id).filter { shown.contains($0) })
    }
}

 
 
 
 
struct ClashMacPendingTicks: Equatable {
    private(set) var pending: [String: Bool] = [:]

    mutating func press(_ id: String, on: Bool) { pending[id] = on }

     
    func shown(_ stored: Set<String>) -> Set<String> {
        var shown = stored
        for (id, on) in pending { if on { shown.insert(id) } else { shown.remove(id) } }
        return shown
    }

     
    mutating func settle(_ stored: Set<String>) {
        pending = pending.filter { id, on in stored.contains(id) != on }
    }
}
