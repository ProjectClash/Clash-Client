import ClashClientKit
import ClashClientUI
import ClashMacClient
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
struct MacQuickAddCard: View {
    @ObservedObject var controller: ProfileQuickAddController
    let identifiers: ClashMacQuickAddIdentifiers
    let doors: ClashMacQuickAddDoors
    @Environment(\.locale) private var locale

    var body: some View {
        ClashMacQuickAddCard(
            header: .copy(controller.headerKey),
            text: Binding(
                get: { controller.state.text },
                set: { controller.state.text = $0 }
            ),
            placeholder: Self.placeholder,
            status: Self.status(controller.state, locale: locale),
             
             
             
            offer: controller.state.nodesOnly.map { offer in
                ClashMacQuickAddOffer(title: AddProfileView.nodesOnlyOfferTitle(nodes: offer.nodes, locale: locale)) {
                    controller.importNodesOnly()
                }
            },
            isBusy: controller.state.isBusy,
            doors: doors,
            identifiers: identifiers,
            submit: { controller.submitTyped() },
            scan: { controller.showsQRCapture = true },
            importFile: { controller.showsImporter = true }
        ) {
            ClashPasteControl(style: .square) { pasted in
                controller.acceptPasted(pasted)
            }
        }
         
         
        .profileQuickAddPresenters(controller)
    }

     
     
    static let placeholder = "https://example.com/config.yaml"

     
     
     
    static func status(_ state: ProfileQuickAddState, locale: Locale = .current) -> ClashMacQuickAddStatus? {
        switch state.phase {
        case .idle:
            return nil
        case .busy(let host):
            return .busy(host)
        case .busyNodes:
            return .busy(ConfigurationSourceRecord.displayLabel(ConfigurationBuiltins.customNodesName, origin: .customNodes, locale: locale))
        case .failed(let message):
             
             
            return .failure(state.failure.map { ProfileSwitchFailureText.cardText(for: $0, locale: locale) } ?? message)
        case .notice(.nodeBelongsInCustomNodes):
            return .notice(
                .copy("That is a node, not a profile URL. Add it under a profile's Custom Nodes.")
            )
        }
    }
}

extension ClashMacQuickAddIdentifiers {
     
     
     
     
     
     
     
     
     
     
    static let configurations = ClashMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.configurations.quick-add.link",
        scanIdentifier: "configuration.library.configurations.quick-add.scan",
        fileIdentifier: "configuration.library.configurations.quick-add.file",
        statusIdentifier: "configuration.library.configurations.quick-add.status",
        nodesOnlyIdentifier: "configuration.library.configurations.quick-add.nodes-only"
    )
    static let nodes = ClashMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.nodes.quick-add.link",
        scanIdentifier: "configuration.library.nodes.quick-add.scan",
        fileIdentifier: "configuration.library.nodes.quick-add.file",
        statusIdentifier: "configuration.library.nodes.quick-add.status",
        nodesOnlyIdentifier: "configuration.library.nodes.quick-add.nodes-only"
    )
    static let rules = ClashMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.rules.quick-add.link",
        scanIdentifier: "configuration.library.rules.quick-add.scan",
        fileIdentifier: "configuration.library.rules.quick-add.file",
        statusIdentifier: "configuration.library.rules.quick-add.status",
        nodesOnlyIdentifier: "configuration.library.rules.quick-add.nodes-only"
    )
    static let scripts = ClashMacQuickAddIdentifiers(
        linkIdentifier: "configuration.library.scripts.quick-add.link",
        scanIdentifier: "configuration.library.scripts.quick-add.scan",
        fileIdentifier: "configuration.library.scripts.quick-add.file",
        statusIdentifier: "configuration.library.scripts.quick-add.status",
        nodesOnlyIdentifier: "configuration.library.scripts.quick-add.nodes-only"
    )
}
