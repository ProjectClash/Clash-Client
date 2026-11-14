import AppKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
@MainActor
enum ClashMacGlobalModeQuestion {
    enum Answer: Equatable { case chooseNode, switchAnyway, cancel }

     
    static func alert(for exit: ClashTunnelOutboundMode.GlobalExit, locale: Locale) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ClashCopy.string("Switch to Global Mode?", locale: locale)
        alert.informativeText = ClashCopy.string(ClashTunnelOutboundMode.questionKey(exit), locale: locale)
        alert.addButton(withTitle: ClashCopy.string("Choose Node", locale: locale))
        alert.addButton(withTitle: ClashCopy.string("Switch Anyway", locale: locale))
         
         
        alert.addButton(withTitle: ClashCopy.string("Cancel", locale: locale)).keyEquivalent = "\u{1b}"
        return alert
    }

    static func answer(_ response: NSApplication.ModalResponse) -> Answer {
        switch response {
        case .alertFirstButtonReturn: return .chooseNode
        case .alertSecondButtonReturn: return .switchAnyway
        default: return .cancel
        }
    }

    static func ask(_ exit: ClashTunnelOutboundMode.GlobalExit, on window: NSWindow?, locale: Locale) async -> Answer {
        let alert = alert(for: exit, locale: locale)
        NSApplication.shared.activate(ignoringOtherApps: true)
         
         
        if let window, window.isVisible, window.attachedSheet == nil {
            window.makeKeyAndOrderFront(nil)
            return answer(await alert.beginSheetModal(for: window))
        }
        return answer(alert.runModal())
    }
}
