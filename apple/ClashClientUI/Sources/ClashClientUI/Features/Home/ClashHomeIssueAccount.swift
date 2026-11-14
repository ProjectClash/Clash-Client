import SwiftUI

private struct ClashHomeIssueOpensAccountKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
     
     
     
     
     
     
     
     
     
    public var clashHomeIssueOpensAccount: Bool {
        get { self[ClashHomeIssueOpensAccountKey.self] }
        set { self[ClashHomeIssueOpensAccountKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
 
struct ClashHomeIssueLineLabel: View {
    let text: ClashDisplayText
     
     
    let offersReason: Bool
    let isAccessibilitySize: Bool
    @Environment(\.clashHomeIssueOpensAccount) private var opensAccount

     
     
    var choosesNode = false

    var showsReason: Bool { choosesNode || (offersReason && opensAccount) }

    var body: some View {
        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(clash: text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if showsReason { reason }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: text)
                    .multilineTextAlignment(.leading)
                     
                     
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                if showsReason {
                    Spacer(minLength: 0)
                     
                    reason
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reason: some View {
        HStack(spacing: 2) {
            Text(clash: .copy(choosesNode ? "Choose Node" : "View Reason"))
            Image(systemName: ClashSymbol.chevronForward.rawValue)
                .font(.footnote.weight(.semibold))
                .imageScale(.small)
        }
         
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    }
}

 
 
 
struct ClashHomeIssueLineHint: ViewModifier {
    let kind: ClashHomeConnectionIssue.Kind
    @Environment(\.clashHomeIssueOpensAccount) private var opensAccount

    func body(content: Content) -> some View {
        content.accessibilityHint(hint)
    }

    private var hint: Text {
        switch kind.lineTapCommand {
        case .resetVPNProfile: return Text(clash: .copy("Reinstalls the VPN profile"))
        case .openOnDemand: return Text(clash: .copy("Opens On Demand"))
        case .openProxies where kind == .globalOnDirect: return Text(clash: .copy("Choose Node"))
        default: return opensAccount ? Text(clash: .copy("Shows why")) : Text("")
        }
    }
}
