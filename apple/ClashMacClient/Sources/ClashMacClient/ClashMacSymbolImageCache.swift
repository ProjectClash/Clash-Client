import AppKit
import ClashClientUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacSymbolImageCache {
    private static var images: [String: NSImage?] = [:]
    private static var lookups: [String: Int] = [:]

    static func image(for symbol: ClashSymbol) -> NSImage? {
        image(named: symbol.rawValue)
    }

    static func image(named name: String) -> NSImage? {
        if let cached = images[name] {
            return cached
        }
        lookups[name, default: 0] += 1
         
         
         
        let found = Bundle.module.image(forResource: NSImage.Name(name)).map { asset -> NSImage in
            let copy = asset.copy() as? NSImage ?? asset
            _ = copy.setName(nil)
            copy.accessibilityDescription = nil
            return copy
        }
        images[name] = found
        return found
    }

     
     
     
    static func drawsSomething(_ symbol: ClashSymbol, fallback: String) -> Bool {
        if image(for: symbol) != nil { return true }
        return NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil
    }

     

    static func resetForTesting() {
        images.removeAll()
        lookups.removeAll()
    }

    static func lookupCountForTesting(_ symbol: ClashSymbol) -> Int {
        lookups[symbol.rawValue] ?? 0
    }

    static func lookupCountForTesting(named name: String) -> Int {
        lookups[name] ?? 0
    }

    static func imageForTesting(named name: String) -> NSImage? {
        image(named: name)
    }

     
    static func probeMissForTesting() -> String {
        "clash.symbol.that.does.not.exist"
    }
}
