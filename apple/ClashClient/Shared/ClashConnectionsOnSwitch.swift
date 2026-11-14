import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
enum ClashConnectionsOnSwitch {
    static let key = "nodes.autoCloseOnSwitch"

    static func isOn(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

     
     
     
    static func closesAfterModeSwitch(from before: String?, to after: String, settingIsOn: Bool) -> Bool {
        guard settingIsOn, let before else { return false }
        return before.lowercased() != after.lowercased()
    }
}
