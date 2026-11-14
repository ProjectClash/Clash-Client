import AppKit
import ClashClientUI
import Foundation
import UserNotifications

 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacScriptNotifications {
     
    struct Actions {
        var open: (URL) -> Void
        var copy: (String) -> Void
        var log: (String) -> Void
         
         
        var show: @MainActor (ClashScriptNotificationText) -> Void = { _ in }
         
         
        var words: ModuleScriptNotificationWordsStore? = nil

        static let system = Actions(
            open: { NSWorkspace.shared.open($0) },
            copy: pasteboard,
            log: { ClashLogStore.shared.append($0, stream: .app, level: .info) },
            show: { ClashMacScriptNotificationPresenter.shared.ask($0) },
            words: ModuleScriptNotificationWordsStore.production
        )

        static let pasteboard: (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

     
     
     
     
    static func start(
        delegate: ClashNotificationCenterDelegate = .shared,
        actions: Actions = .system,
        startRelay: () -> Void = { ModuleScriptNotificationRelay.shared.start() }
    ) {
        delegate.register(kind: ModuleScriptNotificationPoster.kind) { tap in handle(tap, actions) }
        startRelay()
    }

     
     
     
     
    static func handle(_ tap: ClashNotificationTap, _ actions: Actions) {
        let kept = actions.words?.take(for: tap)
        guard let asked = ModuleScriptNotificationTap(tap, kept: kept) else { return }
        if let text = asked.copy { actions.copy(text) }
        if let line = asked.refusalLine { actions.log(line) }
        if let url = asked.open { actions.open(url) }
        if asked.showsText { actions.show(asked.text) }
    }

     
     
     
     
     
     
    static func present(_ text: ClashScriptNotificationText, copy: @escaping (String) -> Void,
                        done: @escaping @MainActor () -> Void) {
        let locale = AppPreferences.language().locale
        let alert = NSAlert()
        alert.messageText = text.title.isEmpty ? text.pageTitle : text.title
        alert.informativeText = text.subtitle
        let words = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        if !text.body.isEmpty {
            words.append(NSAttributedString(string: text.body, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        }
        if let copied = text.copied {
            if words.length > 0 { words.append(NSAttributedString(string: #"\#n\#n"#, attributes: [.font: font])) }
            words.append(NSAttributedString(string: ClashCopy.string("Copied", locale: locale) + #"\#n"#, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            words.append(NSAttributedString(string: copied, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        if words.length > 0 {
            let scroll = NSTextView.scrollableTextView()
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            if let view = scroll.documentView as? NSTextView {
                view.textStorage?.setAttributedString(words)
                view.isEditable = false
                view.isSelectable = true
                view.drawsBackground = false
                view.textContainerInset = NSSize(width: 4, height: 4)
                view.setAccessibilityIdentifier("notification.script.body")
            }
            let width: CGFloat = 380
            let measured = words.boundingRect(with: NSSize(width: width - 16, height: .greatestFiniteMagnitude),
                                              options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            scroll.frame = NSRect(x: 0, y: 0, width: width, height: min(max(measured + 16, 44), 260))
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: ClashCopy.string("Copy", locale: locale))
            .setAccessibilityIdentifier("notification.script.copy")
        alert.addButton(withTitle: ClashCopy.string("Close", locale: locale)).keyEquivalent = #"\#u{1b}"#
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { copy(text.copyText) }
            MainActor.assumeIsolated { done() }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.keyWindow.flatMap({ $0.isVisible && $0.level == .normal ? $0 : nil })
            ?? NSApplication.shared.windows.first(where: { $0.level == .normal && $0.canBecomeKey && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacScriptNotificationPresenter {
    static let shared = ClashMacScriptNotificationPresenter()

     
    typealias Present = @MainActor (ClashScriptNotificationText, @escaping @MainActor () -> Void) -> Void
     
    typealias Schedule = @MainActor (@escaping @MainActor () -> Void) -> Void

     
     
     
    static let waitingLimit = ClashNotificationCenterDelegate.heldTapsLimit

    static let systemPresent: Present = { text, done in
        ClashMacScriptNotifications.present(text, copy: ClashMacScriptNotifications.Actions.pasteboard, done: done)
    }

    static let laterTurn: Schedule = { work in
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { work() } }
    }

    private let present: Present
    private let schedule: Schedule
    private var waiting: [ClashScriptNotificationText] = []
    private var prepared = false
    private var showing = false

    init(present: @escaping Present = ClashMacScriptNotificationPresenter.systemPresent,
         schedule: @escaping Schedule = ClashMacScriptNotificationPresenter.laterTurn) {
        self.present = present
        self.schedule = schedule
    }

     
     
    func ask(_ text: ClashScriptNotificationText) {
        if let index = waiting.firstIndex(where: { $0.id == text.id }) {
            waiting[index] = text
        } else {
            waiting.append(text)
            if waiting.count > Self.waitingLimit { waiting.removeFirst(waiting.count - Self.waitingLimit) }
        }
        showNextLater()
    }

     
     
    func appIsPrepared() {
        prepared = true
        showNextLater()
    }

    private func showNextLater() {
        guard prepared, !showing, !waiting.isEmpty else { return }
        showing = true
        schedule { [weak self] in self?.showNext() }
    }

    private func showNext() {
        guard !waiting.isEmpty else {
            showing = false
            return
        }
        let text = waiting.removeFirst()
        present(text) { [weak self] in
            guard let self else { return }
            self.showing = false
            self.showNextLater()
        }
    }
}
