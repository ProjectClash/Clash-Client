import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVOutboundModeScreen: View {
    @Binding var state: ClashTVProductState
     
     
     
    var onSelect: ((ClashTVOutboundMode) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Outbound mode")
                .font(.largeTitle)
            Spacer(minLength: 0)
            cards
            let footer = Self.footer(state: state)
            if !footer.isEmpty {
                Text(footer)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            ClashTVObservationNote(observation: state.observations.mode)
             
             
            if let feedback = state.feedback(for: [.mode]) {
                ClashTVFeedbackLine(presentation: feedback)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cards: some View {
        HStack(alignment: .top, spacing: 40) {
            ForEach(ClashTVOutboundMode.allCases, id: \.self) { mode in
                card(for: mode)
            }
        }
         
         
         
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(for mode: ClashTVOutboundMode) -> some View {
        Button {
            if let onSelect {
                onSelect(mode)
            } else {
                Self.select(mode, in: &state)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(mode.title)
                        .font(.title2)
                    if state.outboundMode == mode && state.observations.mode.hasValue {
                         
                         
                         
                        Image(systemName: ClashSymbol.checkmark.rawValue)
                            .font(.title3)
                            .accessibilityLabel(state.observations.mode.confirmsCurrentValue ? String(localized: "In force") : String(localized: "Last known choice"))
                    }
                }
                Text(mode.kernelToken)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Text(mode.explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                     
                     
                     
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("tvos.outbound.\(mode.rawValue)")
        .accessibilityAddTraits(state.outboundMode == mode && state.observations.mode.hasValue ? .isSelected : [])
    }

     

     
     
    static func select(_ mode: ClashTVOutboundMode, in state: inout ClashTVProductState) {
        state.outboundMode = mode
        state.observations.mode.selectLocally()
    }

     
     
     
     
    static func footer(state: ClashTVProductState) -> String {
        guard state.observations.mode.hasValue else { return "" }
        if state.isConnected && !state.observations.mode.confirmsCurrentValue { return "" }
        return footer(mode: state.outboundMode, isConnected: state.isConnected)
    }

    static func footer(mode: ClashTVOutboundMode, isConnected: Bool) -> String {
        if isConnected {
            return String(localized: "Currently in force: \(mode.title) · changing this takes effect immediately, without reconnecting")
        }
        return String(localized: "\(mode.title) · applies when you connect")
    }
}

 
 
 
 
 
enum ClashTVGlobalModeQuestion {
    static let title = "Switch to Global Mode?"

    static func message(_ exit: ClashTunnelOutboundMode.GlobalExit) -> String {
        ClashTunnelOutboundMode.questionKey(exit)
    }

     
    static let groupName = "GLOBAL"
}
