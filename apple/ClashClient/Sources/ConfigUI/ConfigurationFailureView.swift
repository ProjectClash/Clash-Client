import ClashClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
 
struct ConfigurationFailureView: View {
    @Environment(\.locale) private var locale
    @Environment(\.clashFeedback) private var feedback
    let failure: ConfigurationFailure
    let recover: (ConfigurationRecoveryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
             
             
            ClashStatusMessage(text: .copy(failure.title), kind: .error)
            Text(clash: failure.displayMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
             
             
             
             
             
             
             
            ForEach(
                Array(ClashKernelRefusalHint.lines(for: failure.kernelSentence, locale: locale).enumerated()),
                id: \.offset
            ) { _, line in
                Text(verbatim: line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration.failure.hint")
            }
             
             
            ForEach(
                Array(failure.providerFailures.enumerated()),
                id: \.offset
            ) { _, item in
                Text(verbatim: ProfileSwitchFailureText.detailLine(item, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration.failure.provider")
            }
            if failure.preservesLastKnownGood {
                Text("The last known good configuration remains published.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(actionButtons) { action in
                 
                 
                 
                 
                 
                 
                Button { recover(action) } label: { Text(clash: .copy(action.title)) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("configuration.failure.\(action.rawValue)")
            }
            if failure.recoveryActions.contains(.viewDiagnostics) {
                DisclosureGroup("Safe diagnostics") {
                    Text(failure.diagnosticCode)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("configuration.failure.diagnostic")
                    Button {
                        ClashClipboard.copy(failure.diagnosticCode, feedback: feedback, operation: "diagnostic-code.copy")
                    } label: {
                        Label(
                            "Copy Diagnostic Code",
                            systemImage: ClashSymbol.docOnDoc.name
                        )
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("configuration.failure.copy-diagnostic")
                }
            }
        }
    }

    private var actionButtons: [ConfigurationRecoveryAction] {
        failure.recoveryActions.filter { $0 != .viewDiagnostics }
    }
}
