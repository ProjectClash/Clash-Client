import AppKit
import ClashClientKit
import ClashClientUI
import ClashMacClient
import Foundation

 
 
 
 
 
 
 
@MainActor
final class ClashMacUndoShelf {
    let feedback: ClashFeedbackCenter
     
    var undoManager: () -> UndoManager?
    var locale: () -> Locale
     
     
     
     
     
    var library: () -> ProfilesViewModel?
     
     
    let lifetime: TimeInterval
    let wait: @MainActor (TimeInterval) async -> Void
    private(set) var tokens: Set<ClashMacUndoToken> = []

    init(feedback: ClashFeedbackCenter, undoManager: @escaping () -> UndoManager?, locale: @escaping () -> Locale,
         library: @escaping () -> ProfilesViewModel? = { nil },
         lifetime: TimeInterval = 600,
         wait: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.feedback = feedback
        self.undoManager = undoManager
        self.locale = locale
        self.library = library
        self.lifetime = lifetime
        self.wait = wait
    }

     
     
     
     
    @discardableResult
    func offer(of label: String, operation: String, title: ClashDisplayText? = nil, actionName: ClashDisplayText? = nil,
               undo: @escaping @MainActor () async -> ClashMacUndoAnswer) -> ClashMacUndoToken {
        let token = ClashMacUndoToken(label: label, operation: operation, actionName: actionName, undo: undo)
        tokens.insert(token)
        let said = title.map { .success(title: $0, action: .undo, accessibilityIdentifier: "feedback.\(operation)") }
            ?? ClashMacFeedbackSentences.deleted(label, undoable: true, id: operation)
        token.resultID = feedback.say(said, operation: operation, perform: { [weak self] in self?.answer(token) })
        register(token)
        let wait = wait, lifetime = lifetime
        Task { @MainActor [weak self] in
            await wait(lifetime)
            self?.retire(token)
        }
        return token
    }

     
     
     
     
     
    func offerRestoring(_ title: ClashDisplayText, _ actionName: ClashDisplayText, _ label: String, _ operation: String,
                        _ restore: @escaping @MainActor () async throws -> Void) {
        let locale = locale, library = library
        offer(of: label, operation: operation, title: title, actionName: actionName) {
            do {
                try await restore()
                 
                library()?.noteLibraryRestored()
                return .restored
            } catch ConfigurationLibraryError.busy {
                return .failed(ClashErrorCopy.message(ConfigurationLibraryError.busy, locale: locale()))
            } catch {
                return .superseded(ClashErrorCopy.message(error, locale: locale()))
            }
        }
    }

     
     
     
     
     
    func offerGroupRestoring(_ deletion: ConfigurationRuleGroupDeletion, actions: ClashMacRuleEditorActions) {
        let locale = locale, library = library
        offer(of: deletion.name, operation: "proxies.group.delete") {
            do {
                _ = try await actions.save(ClashMacPolicyGroupPage.undoing(deletion, in: try await actions.load().draft))
                library()?.noteLibraryRestored()
                return .restored
            } catch ConfigurationLibraryError.busy {
                 
                 
                return .failed(ClashErrorCopy.message(ConfigurationLibraryError.busy, locale: locale()))
            } catch {
                return .superseded(ClashErrorCopy.message(error, locale: locale()))
            }
        }
    }

    func register(_ token: ClashMacUndoToken) {
        guard let undoManager = undoManager() else { return }
        undoManager.registerUndo(withTarget: token) { [weak self] token in
            if let id = token.resultID { self?.feedback.dismiss(id) }
            self?.answer(token)
        }
        undoManager.setActionName(token.actionName.resolved(locale: locale()))
    }

     
     
    func retire(_ token: ClashMacUndoToken) {
        undoManager()?.removeAllActions(withTarget: token)
        tokens.remove(token)
    }

    func answer(_ token: ClashMacUndoToken) {
        guard !token.used else { return }
        token.used = true
        undoManager()?.removeAllActions(withTarget: token)
        Task { @MainActor in
            var answer = await token.undo()
            if case .failed = answer {
                 
                try? await Task.sleep(nanoseconds: 700_000_000)
                answer = await token.undo()
            }
            switch answer {
            case .restored:
                self.retire(token)
                self.feedback.say(ClashMacFeedbackSentences.restored(token.label, id: token.operation), operation: token.operation)
            case .superseded(let reason):
                self.retire(token)
                self.feedback.say(.error(title: ClashFeedbackCopy.couldNotUndo, message: reason.isEmpty ? nil : .copy(reason),
                                         accessibilityIdentifier: "feedback.undo-failed"),
                                  operation: token.operation)
            case .failed(let reason):
                token.used = false
                token.resultID = self.feedback.say(
                    .error(title: ClashFeedbackCopy.couldNotUndo, message: reason.isEmpty ? nil : .verbatim(reason), action: .retry,
                           accessibilityIdentifier: "feedback.undo-failed"),
                    operation: token.operation, perform: { [weak self] in self?.answer(token) })
                self.register(token)
            }
        }
    }
}
