import Foundation

 
 
 
 
 
 
 
enum ClashModuleCountLine {
     
     
     
     
     
     
     
     
     
    static func parts(kept: Int, waiting: Int, unavailable: Int = 0, waitsFor: ClashModuleDecryptionWait?,
                      enabled: Bool, skipped: Int = 0, details: Bool, locale: Locale) -> [ClashDisplayText] {
        let skippedPart: [ClashDisplayText] = details && skipped > 0
            ? [.format("%@ skipped", [ClashCopy.count(skipped, locale: locale)])] : []
         
        guard enabled else { return [entries(kept, locale: locale)] + skippedPart }
        let inUse = max(0, kept - waiting - unavailable)
        if waiting > 0, let waitsFor {
            let waitingCount = ClashCopy.count(waiting, locale: locale)
            if inUse == 0 {
                let key: String
                switch waitsFor {
                case .off: key = waiting == 1 ? "%@ entry · in use once HTTPS Decryption is on"
                    : "%@ entries · in use once HTTPS Decryption is on"
                case .notReady: key = waiting == 1 ? "%@ entry · in use once HTTPS Decryption is ready"
                    : "%@ entries · in use once HTTPS Decryption is ready"
                case .onHold: key = waiting == 1 ? "%@ entry · on hold for now" : "%@ entries · on hold for now"
                }
                return [.format(key, [waitingCount])] + skippedPart
            }
            let key: String
            switch waitsFor {
            case .off: key = "%@ in use · %@ more once HTTPS Decryption is on"
            case .notReady: key = "%@ in use · %@ more once HTTPS Decryption is ready"
            case .onHold: key = "%@ in use · %@ more on hold for now"
            }
            return [.format(key, [ClashCopy.count(inUse, locale: locale), waitingCount])] + skippedPart
        }
        guard details else { return [entries(inUse, locale: locale)] }
        return [.format("%@ in use", [ClashCopy.count(inUse, locale: locale)])] + skippedPart
    }

     
    static func string(_ parts: [ClashDisplayText], locale: Locale) -> String {
        parts.map { ClashCopy.string(for: $0, locale: locale) }.joined(separator: " · ")
    }

    private static func entries(_ count: Int, locale: Locale) -> ClashDisplayText {
        .format(count == 1 ? "%@ entry" : "%@ entries", [ClashCopy.count(count, locale: locale)])
    }
}
