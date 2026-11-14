import SwiftUI

 
 
 
 
 
 
@MainActor
public final class ClashModulesWrites {
     
     
    public let turns = ClashWriteTurns()
    public let switches: ClashStoredSwitch<String>
     
    public let settings: ClashStoredValues<String, String?>

    public init(readBackTimeout: TimeInterval = 2) {
        switches = ClashStoredSwitch(readBackTimeout: readBackTimeout, turns: turns)
        settings = ClashStoredValues(readBackTimeout: readBackTimeout, turns: turns)
    }

     
    public nonisolated static let decryption = "https-decryption"

     
    public nonisolated static func module(_ id: String) -> String { "module\u{0}" + id }

     
    public nonisolated static func setting(module: String, name: String) -> String { module + "\u{0}" + name }

     
    public nonisolated static func reset(module: String) -> String { module + "\u{0}\u{0}reset" }
}
