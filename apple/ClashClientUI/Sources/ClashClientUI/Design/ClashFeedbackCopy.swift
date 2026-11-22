import Foundation

 
 
 
 
 
 
 
 
 
 
 
public enum ClashFeedbackCopy {
     

    public static let copied: ClashDisplayText = .copy("Copied")

     
    public static func copied(_ what: String) -> ClashDisplayText {
        .formatCopy("Copied %@", [what])
    }

     

    public static func updated(_ name: String) -> ClashDisplayText {
        .format("Updated “%@”", [name])
    }

    public static func upToDate(_ name: String) -> ClashDisplayText {
        .format("“%@” Is Up to Date", [name])
    }

    public static func couldNotUpdate(_ name: String) -> ClashDisplayText {
        .format("Couldn’t Update “%@”", [name])
    }

     
    public static func batch(updated: Int, failed: Int, unchanged: Int) -> ClashDisplayText {
        if failed > 0 {
             
            if updated == 0 { return .format("None Updated, %@ Failed", [String(failed)]) }
            return .format("Updated %@, %@ Failed", [String(updated), String(failed)])
        }
        if updated == 0 {
            return unchanged == 1 ? .copy("Up to Date") : .format("All %@ Are Up to Date", [String(unchanged)])
        }
        return .format("Updated %@", [String(updated)])
    }

     
    public static let nothingToUpdate: ClashDisplayText = .copy("Nothing to Update")
     
    public static let updating: ClashDisplayText = .copy("Updating…")

     

    public static func added(_ name: String) -> ClashDisplayText {
        .format("Added “%@”", [name])
    }

    public static func deleted(_ name: String) -> ClashDisplayText {
        .format("Deleted “%@”", [name])
    }

    public static func couldNotDelete(_ name: String) -> ClashDisplayText {
        .format("Couldn’t Delete “%@”", [name])
    }

     
    public static func deleteActionName(_ name: String) -> ClashDisplayText {
        .format("Delete “%@”", [name])
    }

     
     
     
    public static func removeActionName(_ name: String) -> ClashDisplayText {
        .format("Remove “%@”", [name])
    }

     
    public static let couldNotUndo: ClashDisplayText = .copy("Couldn’t Undo")

     
    public static func restored(_ name: String) -> ClashDisplayText {
        .format("Restored “%@”", [name])
    }

     

    public static let saved: ClashDisplayText = .copy("Saved")
    public static let couldNotSave: ClashDisplayText = .copy("Couldn’t Save")

    public static func exported(_ fileName: String) -> ClashDisplayText {
        .format("Exported “%@”", [fileName])
    }

    public static let removedLinkCredentials: ClashDisplayText = .copy("Removed Saved Credentials from the Link")

     

    public static func switched(to name: String) -> ClashDisplayText {
        .format("Switched to “%@”", [name])
    }

    public static func couldNotSwitch(to name: String) -> ClashDisplayText {
        .format("Couldn’t Switch to “%@”", [name])
    }

    public static let modeNotChanged: ClashDisplayText = .copy("Outbound Mode Not Changed")
    public static let couldNotCheckExternalIP: ClashDisplayText = .copy("Couldn’t Check the External IP")

     

     
    public static func title(for action: ClashFeedbackPresentation.Action) -> ClashDisplayText {
        switch action {
        case .details: return .copy("Details")
        case .retry: return .copy("Try Again")
        case .undo: return .copy("Undo")
        case .reveal: return .copy("Show in Finder")
        }
    }

     
    public static let keys: [String] = [
        "Copied", "Copied %@", "Updated “%@”", "“%@” Is Up to Date", "Couldn’t Update “%@”",
        "Updated %@, %@ Failed", "None Updated, %@ Failed", "Up to Date", "All %@ Are Up to Date", "Updated %@", "Nothing to Update", "Updating…",
        "Added “%@”", "Deleted “%@”", "Couldn’t Delete “%@”", "Restored “%@”", "Delete “%@”", "Remove “%@”", "Couldn’t Undo",
        "Saved", "Couldn’t Save", "Exported “%@”", "Removed Saved Credentials from the Link",
        "Switched to “%@”", "Couldn’t Switch to “%@”", "Outbound Mode Not Changed", "Couldn’t Check the External IP",
        "Details", "Try Again", "Undo", "Show in Finder",
    ]

     
    public static let copiedNouns: [String] = ["Profile URL", "Terminal Command", "Link"]
}
