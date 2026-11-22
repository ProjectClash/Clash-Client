import AppKit
import ClashMacClient

 
 
 
 
enum ClashMacDeleteKey {
     
     
     
     
     
     
     
     
    @MainActor
    static func belongsToTheShownItem(event: NSEvent?, keyWindow: NSWindow?, mainWindow: NSWindow?) -> Bool {
        let fromKeyboard = event?.type == .keyDown
        guard let key = keyWindow else { return true }
        if let text = key.firstResponder as? NSTextView {
            guard fromKeyboard else { return key === mainWindow }
            if text.isEditable { text.deleteToBeginningOfLine(nil) }
            return false
        }
        return key === mainWindow || mainWindow == nil
    }

     
     
     
    static func target(shown: ClashMacConfigurationCenterItem?) -> ClashMacConfigurationCenterItem? {
        guard let shown else { return nil }
        if case .collection = shown { return nil }
        return shown
    }

     
     
     
     
     
     
    static func asksFirst(_ item: ClashMacConfigurationCenterItem, deletesUndoably: Bool) -> Bool {
        switch item {
        case .source, .scheme: !deletesUndoably
        case .script: false
        case .configuration, .collection: true
        }
    }
}
