import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
public struct ClashMacNewPolicyGroupSheet: View {
    private let actions: ClashMacRuleEditorActions
    private let close: () -> Void
    @State private var state: ClashMacRuleEditorState?
    @State private var candidates = ConfigurationRuleTargetCandidates(sections: [])
     
    @State private var loadFailure: String?
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale

    public init(actions: ClashMacRuleEditorActions, close: @escaping () -> Void) {
        self.actions = actions
        self.close = close
    }

    public var body: some View {
        Group {
            if let state {
                ClashMacRuleGroupEditor(
                    group: nil, all: state.draft.groups, nodeCandidates: candidates,
                    commit: { document in
                         
                         
                         
                        var draft = state.draft
                        try draft.setGroup(document, groupID: nil)
                        Task { @MainActor in
                            do { _ = try await actions.save(draft) } catch {
                                feedback?.say(ClashMacFeedbackSentences.couldNotSave(reason: ClashErrorCopy.message(error, locale: locale),
                                                                                       id: "proxies.group.new"),
                                              operation: "proxies.group.new")
                            }
                        }
                    },
                    close: close
                )
            } else if let loadFailure {
                VStack(spacing: ClashTheme.Spacing.compact) {
                    Text(verbatim: loadFailure)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("proxies.group.new.load-failure")
                    Button { close() } label: { Text(clash: .copy("Close")) }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("proxies.group.new.close")
                }
                .padding(24)
                .frame(width: 560, height: 640)
            } else {
                ProgressView().frame(width: 560, height: 640)
            }
        }
        .task {
            do { state = try await actions.load() } catch { loadFailure = ClashErrorCopy.message(error, locale: locale) }
            if let read = try? await actions.candidates?() { candidates = read }
        }
    }
}
