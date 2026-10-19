import Foundation

/// The prelude, read once.
enum ScriptPrelude {
    static let source: String = {
        // `Bundle.module` is what SwiftPM generates for the copied resource; in
        // the tunnel the package is linked the same way, so one lookup works in
        // both places.
        if let url = Bundle.module.url(forResource: "ScriptPrelude", withExtension: "js"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return "throw new Error('the script prelude is missing from the bundle');"
    }()
}
