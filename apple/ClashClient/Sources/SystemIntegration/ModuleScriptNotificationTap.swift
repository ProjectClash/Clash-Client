#if os(iOS) || os(macOS)
import ClashClientUI
import Foundation
import UserNotifications

 
 
 
 
 
 
 
 
 
 
struct ModuleScriptNotificationTap: Equatable {
     
    enum Refusal: Equatable {
        case notALink(String)
        case file(String)
    }

    var scriptName: String
     
    var copy: String?
     
    var open: URL?
    var refusal: Refusal?
     
     
    var text: ClashScriptNotificationText

     
     
     
     
    var showsText: Bool { open == nil }

     
     
     
     
     
    init?(_ tap: ClashNotificationTap, kept: ModuleScriptNotificationWords? = nil) {
        guard tap.action == UNNotificationDefaultActionIdentifier else { return nil }
        scriptName = tap.info[#"scriptName"#] ?? #""#
        copy = (kept?.clipboardText ?? tap.info[#"clipboardText"#]).flatMap { $0.isEmpty ? nil : $0 }
        text = ClashScriptNotificationText(id: tap.identifier, scriptName: scriptName, title: kept?.title ?? tap.title,
                                           subtitle: kept?.subtitle ?? tap.subtitle, body: kept?.body ?? tap.body,
                                           clipboardText: copy)
         
         
        guard let written = tap.info[#"openURL"#]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !written.isEmpty else { return }
        guard let url = URL(string: written), let scheme = url.scheme, !scheme.isEmpty else {
            refusal = .notALink(written)
            return
        }
        guard !url.isFileURL, scheme.lowercased() != #"file"# else {
            refusal = .file(written)
            return
        }
        open = url
    }

     
     
    static func recordID(of tap: ClashNotificationTap) -> String? {
        if let id = tap.info[#"id"#], !id.isEmpty { return id }
        let prefix = ModuleScriptNotificationPoster.kind + "."
        guard tap.identifier.hasPrefix(prefix) else { return nil }
        return String(tap.identifier.dropFirst(prefix.count))
    }

     
    var refusalLine: String? {
        switch refusal {
        case .notALink(let written)?:
            return #"module script notification from \#(scriptName): its link "\#(written)" is not one; not opened"#
        case .file(let written)?:
            return #"module script notification from \#(scriptName): its link "\#(written)" is a file; not opened"#
        case nil:
            return nil
        }
    }
}

extension ModuleScriptNotificationWordsStore {
     
     
    func take(for tap: ClashNotificationTap, now: Date = Date()) -> ModuleScriptNotificationWords? {
        ModuleScriptNotificationTap.recordID(of: tap).flatMap { take(id: $0, now: now) }
    }
}
#endif
