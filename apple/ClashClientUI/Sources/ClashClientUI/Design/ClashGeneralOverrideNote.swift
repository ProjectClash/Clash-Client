import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashGeneralOverrideNote {
     
     
     
     
     
    public static func outboundModeSetOnHome(_ title: String) -> ClashDisplayText {
        .formatCopy("Home is set to “%@”, which runs over this for now.", [title])
    }

     
     
     
     
    public static func logLevelForcedByLogSettings(_ level: String) -> ClashDisplayText {
        .format("Log Settings is set to “%@”, which runs over this.", [level])
    }

     
    public static var followConfiguration: ClashDisplayText { .copy("Follow the Configuration Again") }
}
