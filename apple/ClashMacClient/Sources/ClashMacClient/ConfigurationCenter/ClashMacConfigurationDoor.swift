import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
public enum ClashMacConfigurationDoor: Hashable, Sendable, Identifiable {
    public var id: Self { self }
     
    case network
     
    case trust
     
     
    case scheme(String)
}


 
 
struct ClashMacDoorRow: View {
    let title: ClashDisplayText
    let identifier: String
    let open: () -> Void

    init(_ title: ClashDisplayText, identifier: String, open: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.open = open
    }

    var body: some View {
        Button(action: open) {
            HStack {
                Text(clash: title)
                Spacer()
                ClashSymbolImage(symbol: .chevronForward)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

 
public struct ClashMacLibrarySelection: Identifiable, Equatable {
    public let id: String
     
     
     
    public var pane: ClashMacRuleEditorSheet.Pane = .rules
    public init(id: String, pane: ClashMacRuleEditorSheet.Pane = .rules) {
        self.id = id; self.pane = pane
    }
}
