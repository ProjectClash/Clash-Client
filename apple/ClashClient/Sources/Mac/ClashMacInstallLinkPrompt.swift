import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
 
struct ClashMacInstallLinkPrompt {
     
     
     
    let pending: String
     
    let rules: InstallLinkRuleScheme?

    init(pending: String, rules: InstallLinkRuleScheme? = nil) {
        self.pending = pending
        self.rules = rules
    }

     
     
     
    var isLocalConfiguration: Bool {
        FlClashInstallLink.isLocalOrigin(pending)
    }

    var title: String {
        isLocalConfiguration ? "Add this profile?" : "Add this profile URL?"
    }

     
    var lead: String {
        isLocalConfiguration
            ? "An install link wants to add a profile to Clash.\n\n"
            : "An install link wants to add a profile URL to Clash.\n\n"
    }

     
     
     
    var ruleLine: ClashDisplayText? {
        ProfileImportRouter.confirmationRuleLine(for: rules)
    }

     
    var link: String {
        ProfileImportRouter.confirmationText(for: pending)
    }

     
     
    var message: String {
        lead + (ruleLine.map { $0.rawValue + "\n\n" } ?? "") + link
    }

     
     
     
    static let dismissalDeclines = false
}

 
 
 
 
@MainActor
enum ClashMacModuleInstallLink {
     
    static func open(_ url: URL, request: ModuleAddRequest, pushModulesPage: () -> Void) -> Bool {
        guard let link = ModuleInstallLink.moduleLink(from: url) else { return false }
        request.request(link: link)
        if !request.isPageOnScreen { pushModulesPage() }
        return true
    }
}
