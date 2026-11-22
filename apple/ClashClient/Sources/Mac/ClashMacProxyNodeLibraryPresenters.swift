import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
struct ClashMacProxyNodeLibraryPresenters: ViewModifier {
    @ObservedObject var actions: ProxyNodeLibraryActions
    let context: ProxyNodeLibraryContext?

    func body(content: Content) -> some View {
        content
            .onChange(of: actions.showsSource) { shows in
                guard shows, let id = actions.facts?.source?.id else { return }
                actions.showsSource = false
                 
                actions.sourceChangedLibrary()
                actions.sourceDismissed()
                context?.openSource?(id)
            }
            .clashProductModal(isPresented: $actions.showsOriginalEditor, role: .page, onDismiss: { actions.editorDismissed() }) {
                 
                 
                if let facts = actions.facts, let page = context?.originalEditor?(facts.profileID, facts.node, { actions.originalEdited() }, { actions.editorClosed() }) {
                    page
                }
            }
            .clashProductModal(isPresented: $actions.showsEditor, role: .page, onDismiss: { actions.editorDismissed() }) {
                if let built = actions.facts?.selfBuilt, let record = CustomNodesView.record(fromNodeJSON: built.nodeJSON) {
                    ClashFeatureNavigationContainer {
                        ProxyNodeDetailsView(record: record, retest: {},
                                             saveNode: { _, json in try await actions.saveSelfBuilt(json) },
                                             showsTesting: false,
                                             onDone: { actions.editorClosed() },
                                             commitTitle: "Save")
                    }
                    .clashModalPresentation(.page)
                }
            }
    }
}
