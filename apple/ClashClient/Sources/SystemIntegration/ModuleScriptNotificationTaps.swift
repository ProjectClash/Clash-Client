#if os(iOS)
import ClashClientUI
import Foundation
import SwiftUI
import UIKit
import UserNotifications

 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ModuleScriptNotificationTaps {
    static func register(
        on delegate: ClashNotificationCenterDelegate = .shared,
        copy: @escaping @MainActor (String) -> Void = { UIPasteboard.general.string = $0 },
        open: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) },
        show: @escaping @MainActor (ClashScriptNotificationText) -> Void = { ModuleScriptNotificationPages.shared.ask($0) },
        log: @escaping @MainActor (String) -> Void = { ClashLogStore.shared.append($0, stream: .app, level: .info) },
        words: ModuleScriptNotificationWordsStore? = ModuleScriptNotificationWordsStore.production
    ) {
        delegate.register(kind: ModuleScriptNotificationPoster.kind) { tap in
            answer(tap, kept: words?.take(for: tap), copy: copy, open: open, show: show, log: log)
        }
    }

     
    static func answer(
        _ tap: ClashNotificationTap,
        kept: ModuleScriptNotificationWords? = nil,
        copy: @MainActor (String) -> Void,
        open: @MainActor (URL) -> Void,
        show: @MainActor (ClashScriptNotificationText) -> Void,
        log: @MainActor (String) -> Void
    ) {
        guard let asked = ModuleScriptNotificationTap(tap, kept: kept) else { return }
        if let line = asked.refusalLine { log(line) }
         
         
        if let text = asked.copy { copy(text) }
        if let url = asked.open { open(url) }
        if asked.showsText { show(asked.text) }
    }
}

 
 
 
 
 
@MainActor
final class ModuleScriptNotificationPages: ObservableObject {
    static let shared = ModuleScriptNotificationPages()

     
    @Published private(set) var shown: ClashScriptNotificationText?
    private var waiting: ClashScriptNotificationText?
    private var isActive = false

    func ask(_ text: ClashScriptNotificationText) {
        waiting = text
        raiseIfActive()
    }

    func sceneBecame(active: Bool) {
        isActive = active
        raiseIfActive()
    }

     
    func close() {
        shown = nil
    }

    private func raiseIfActive() {
        guard isActive, let waiting else { return }
        shown = waiting
        self.waiting = nil
    }
}

 
 
 
struct ModuleScriptNotificationPage: View {
    let text: ClashScriptNotificationText
    let close: () -> Void
    @Environment(\.clashFeedback) private var feedback

    var body: some View {
        ClashFeatureNavigationContainer {
            ClashScriptNotificationView(text: text)
                .clashPageTitle(.verbatim(text.pageTitle), watchAs: "notification.script")
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton { close() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            ClashClipboard.copy(text.copyText, feedback: feedback, operation: #"notification.script.copy"#)
                        } label: {
                            Text("Copy")
                        }
                        .accessibilityIdentifier("notification.script.copy")
                    }
                }
        }
    }
}
#endif
