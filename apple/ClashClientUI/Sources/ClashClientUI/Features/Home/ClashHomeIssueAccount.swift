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
     
     
     
    var saysWords = false

     
    static let wordsLineLimit = 3

    static func lineLimit(saysWords: Bool) -> Int { saysWords ? wordsLineLimit : 1 }

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
            HStack(alignment: saysWords ? .top : .center, spacing: ClashTheme.Spacing.compact) {
                Text(clash: text)
                    .multilineTextAlignment(.leading)
                     
                     
                     
                     
                    .lineLimit(Self.lineLimit(saysWords: saysWords))
                    .minimumScaleFactor(saysWords ? 1 : 0.75)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: saysWords)
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
         
        case .performPrimaryAction(.none): return Text("")
        default: return opensAccount ? Text(clash: .copy("Shows why")) : Text("")
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
public struct ClashCoreRefusalAccount: View {
    private let issue: ClashHomeConnectionIssue

    public init(issue: ClashHomeConnectionIssue) {
        self.issue = issue
    }

     
    nonisolated public static func lead(refusesConfiguration: Bool) -> ClashDisplayText {
        refusesConfiguration
            ? "This configuration can’t be used. Fix the problem below and connect again, or switch to another configuration."
            : "Clash didn’t connect because the core couldn’t start. You can try again."
    }

     
     
    nonisolated public static let wordsHeader: ClashDisplayText = "The Core’s Reason"

    public var body: some View {
        Section {
            Text(clash: Self.lead(refusesConfiguration: issue.refusesConfiguration))
                .font(.subheadline)
                .accessibilityIdentifier("connection.issue.reason")
        }
        if let words = issue.coreWords {
            Section {
                selectable(
                    Text(verbatim: words)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                )
                .accessibilityIdentifier("connection.issue.core-words")
            } header: {
                Text(clash: Self.wordsHeader)
            }
        }
    }

    @ViewBuilder
    private func selectable(_ text: Text) -> some View {
#if os(tvOS)
        text
#else
        text.textSelection(.enabled)
#endif
    }
}
