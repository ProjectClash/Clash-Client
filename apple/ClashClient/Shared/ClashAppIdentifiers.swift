import Foundation
 
 
 
 
 
 
 
 

enum ClashAppIdentifiers {
     
    static let base = "org.example.clash"

     
    static let appBundleID = "org.example.clash"

     
    static let macAppBundleID = "org.example.clash"

     
    static let tvAppBundleID = "org.example.clash"

     
    static let packetTunnelExtensionBundleID = "org.example.clash.extension"

     
    static let macPacketTunnelExtensionBundleID = "org.example.clash.packet-tunnel"

     
    static let controlsExtensionBundleID = "org.example.clash.controls"

     
    static let shareExtensionBundleID = "org.example.clash.share"

     
    static let tvPacketTunnelExtensionBundleID = "org.example.clash.tvextension"

     
     
     
     
     
     
     
     
    static var appGroup: String {


        return "group.org.example.clash"
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static var defaultsSuite: String {


        return appGroup
    }



     
    static let iCloudContainer = "iCloud.org.example.clash"

     
    static let backgroundRefreshTask = "org.example.clash.refresh"

     
    static let keychainService = "org.example.clash.credentials"
}
