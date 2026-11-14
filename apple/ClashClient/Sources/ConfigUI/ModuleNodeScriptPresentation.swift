#if os(iOS) || os(macOS)
import ClashClientUI
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

 
 
 
 
enum ModuleNodeScriptPresentation {
     
     
     
    static func menu(_ scripts: [ModuleAppScriptEntry],
                     drawsSymbol: (String) -> Bool = systemDrawsSymbol) -> [ClashProxyNodeScript] {
        scripts.filter { $0.kind == .generic }.map { entry in
            let symbol = entry.imageURL.flatMap { written -> String? in
                let name = written.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !name.contains("/"), drawsSymbol(name) else { return nil }
                return name
            }
            return ClashProxyNodeScript(id: entry.id, name: entry.name, symbol: symbol)
        }
    }

    static func systemDrawsSymbol(_ name: String) -> Bool {
#if canImport(UIKit)
        UIImage(systemName: name) != nil
#elseif canImport(AppKit)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
#else
        false
#endif
    }

     
     
     
     
     
    static func state(_ result: ModuleAppScriptResult) -> ClashNodeScriptResult.State {
        switch result.outcome {
        case .done:
             
             
             
             
             
            func written(_ text: String?) -> String? {
                text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            }
            let message = written(result.htmlMessage).map(ClashScriptHTML.render)
                ?? written(result.panel?.content).map(ClashScriptHTML.plainText)
            return .finished(title: result.title, message: message)
        case .aborted(let message):
            return .failed("The script stopped with an error.", detail: message)
        case .timedOut(let seconds):
            return .failed(.format("The script didn't finish in %@ seconds.", [String(format: "%g", seconds)]), detail: nil)
        case .skipped(.quarantined):
            return .failed("Update the module, then try again.", detail: nil)
        case .skipped(.paused):
            return .failed("Scripts are paused for now. Try again later.", detail: nil)
        case .skipped(.lowMemory):
            return .failed("There isn't enough memory to run this script right now. Try again later.", detail: nil)
        case .skipped(.other):
            return .failed("The script didn't run.", detail: nil)
        case .notRun(.tunnelNotConnected):
            return .failed("Connect Clash to run scripts.", detail: nil)
        case .notRun(.notFound):
            return .failed("This script's module is off or removed.", detail: nil)
        case .notRun(.busy):
            return .failed("This script is still running.", detail: nil)
        case .notRun(.bodyMissing), .notRun(.bodyMismatch):
            return .failed("Update the module, then try again.", detail: nil)
        }
    }
}
#endif
