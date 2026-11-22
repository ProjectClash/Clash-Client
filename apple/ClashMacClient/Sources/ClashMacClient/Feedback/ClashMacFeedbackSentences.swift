import ClashClientUI
import Foundation

 
 
 
public enum ClashMacFeedbackSentences {
    public static func copied(_ what: String? = nil, id: String) -> ClashFeedbackPresentation {
        .success(title: what.map(ClashFeedbackCopy.copied) ?? ClashFeedbackCopy.copied,
                 accessibilityIdentifier: "feedback.\(id).copied")
    }

    public static func updated(_ name: String, id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.updated(name), accessibilityIdentifier: "feedback.\(id).updated")
    }

    public static func upToDate(_ name: String, id: String) -> ClashFeedbackPresentation {
        .information(title: ClashFeedbackCopy.upToDate(name), accessibilityIdentifier: "feedback.\(id).up-to-date")
    }

     
     
     
    public static func putBack(_ title: ClashDisplayText, id: String) -> ClashFeedbackPresentation {
        .warning(title: title, accessibilityIdentifier: "feedback.\(id).put-back")
    }

    public static func couldNotUpdate(_ name: String, reason: String, id: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotUpdate(name), message: .verbatim(reason),
               accessibilityIdentifier: "feedback.\(id).failed")
    }

     
     
    public static func couldNotUpdateScripts(reason: String, id: String) -> ClashFeedbackPresentation {
        .error(title: .copy("Couldn’t Update Scripts"), message: .verbatim(reason), accessibilityIdentifier: "feedback.\(id).failed")
    }

     
     
    public static func reset(_ name: String, id: String) -> ClashFeedbackPresentation {
        .success(title: .format("Reset “%@”", [name]), accessibilityIdentifier: "feedback.\(id).reset")
    }

    public static func deleted(_ name: String, undoable: Bool, id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.deleted(name), action: undoable ? .undo : nil,
                 accessibilityIdentifier: "feedback.\(id).deleted")
    }

    public static func restored(_ name: String, id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.restored(name), accessibilityIdentifier: "feedback.\(id).restored")
    }

    public static func couldNotDelete(_ name: String, reason: String, id: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotDelete(name), message: .verbatim(reason),
               accessibilityIdentifier: "feedback.\(id).failed")
    }

     
     
     
    public static func whyNotDeleted(_ error: Error, locale: Locale) -> String {
        (error as? ClashMacStillUsedRefusal)?.whereUsed(locale: locale) ?? ClashErrorCopy.message(error, locale: locale)
    }

    public static func added(_ name: String, id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.added(name), accessibilityIdentifier: "feedback.\(id).added")
    }

    public static func saved(id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.saved, accessibilityIdentifier: "feedback.\(id).saved")
    }

    public static func couldNotSave(reason: String, id: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotSave, message: .verbatim(reason), accessibilityIdentifier: "feedback.\(id).failed")
    }

    public static func credentialsRemoved(id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.removedLinkCredentials, accessibilityIdentifier: "feedback.\(id).done")
    }

    public static func couldNotSwitch(to name: String, reason: String, id: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.couldNotSwitch(to: name), message: .verbatim(reason),
               accessibilityIdentifier: "feedback.\(id).failed")
    }

    public static func modeNotChanged(reason: String, id: String) -> ClashFeedbackPresentation {
        .error(title: ClashFeedbackCopy.modeNotChanged, message: .verbatim(reason), accessibilityIdentifier: "feedback.\(id).failed")
    }

    public static func exported(_ fileName: String, id: String) -> ClashFeedbackPresentation {
        .success(title: ClashFeedbackCopy.exported(fileName), action: .reveal, accessibilityIdentifier: "feedback.\(id).exported")
    }

     
    public static func batch(updated: Int, failed: Int, unchanged: Int, id: String) -> ClashFeedbackPresentation {
        let title = ClashFeedbackCopy.batch(updated: updated, failed: failed, unchanged: unchanged)
        if failed > 0 {
            return .warning(title: title, action: .details, isBatchSummary: true, accessibilityIdentifier: "feedback.\(id).summary")
        }
        return updated == 0
            ? .information(title: title, isBatchSummary: true, accessibilityIdentifier: "feedback.\(id).summary")
            : .success(title: title, isBatchSummary: true, accessibilityIdentifier: "feedback.\(id).summary")
    }
}
