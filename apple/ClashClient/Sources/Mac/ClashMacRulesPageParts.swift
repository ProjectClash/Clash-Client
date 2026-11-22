import ClashClientKit
import ClashClientUI
import ClashMacClient
import Foundation
import SwiftUI

 
 
 
 
 
enum ClashMacRulesPage {
     
     
    static func schemeValue(profileID: String, in library: ConfigurationLibrarySnapshot, isRead: Bool) -> ClashDisplayText? {
        guard isRead else { return nil }
        if let scheme = ConfigurationRulesEditSnapshot.running(profileID, in: library) { return .verbatim(scheme.displayLabel) }
        return .copy(ConfigurationSchemePickerSnapshot.originalTitle)
    }

     
     
     
    static func rulesGroupTitle(profileID: String, in library: ConfigurationLibrarySnapshot, isRead: Bool) -> ClashDisplayText? {
        guard isRead else { return nil }
        if let scheme = ConfigurationRulesEditSnapshot.running(profileID, in: library) { return .verbatim(scheme.displayLabel) }
        return .copy("Rules in the Configuration File")
    }

     
     
     
     
    static func editsInPlace(profileID: String, in library: ConfigurationLibrarySnapshot) -> Bool {
        !ClashMacOriginalRules.keepsRules(profileID: profileID, in: library)
    }

     
     
    static func offersRestore(profileID: String, in library: ConfigurationLibrarySnapshot) -> Bool {
        ConfigurationRulesEditSnapshot.running(profileID, in: library).map(ConfigurationRulesEditSnapshot.isChangedBuiltin) ?? false
    }

     
     
    static func customRules(of profile: Profile?) -> ClashMacCustomRulesState {
        guard let profile else { return .empty }
        let muted = Set(profile.override.disabledAppendRules ?? [])
        let comments = profile.override.appendRuleComments ?? [:]
        return ClashMacCustomRulesState(
            rules: profile.override.appendRules.map {
                ClashMacCustomRule(text: $0, isEnabled: !muted.contains($0), comment: comments[$0])
            },
            prepends: profile.override.prependRules
        )
    }
}

 
 
struct ClashMacSchemeWrites {
    let setScheme: @MainActor (String) -> Void
    let setOriginalUse: @MainActor (Bool) -> Void
    let leaveOriginal: @MainActor (String) -> Void
}

 
 
@MainActor
final class ClashMacRulesPageCommands: ObservableObject {
    @Published private(set) var addRequests = 0

    func addToScheme() { addRequests &+= 1 }
}

 
 
 
 
@MainActor
struct ClashMacRulesPageOwner {
     
    let channels: ClashRegularRootChannels
     
    let commands: ClashMacRulesPageCommands
     
     
    let isConfigurationsPage: Bool
}

 
 
 
struct ClashMacRulesPageLeadingHost: View {
    @ObservedObject var profiles: ProfilesViewModel
    @ObservedObject var library: ClashMacConfigurationLibraryModel
    let profileID: String
    let schemePage: @MainActor () -> AnyView
    let customRules: ClashMacCustomRulesActions
    let addCustomRule: @MainActor () -> Void
     
     
    let readLibrary: @MainActor () async -> Void
    let palette: ClashProductPalette

    var body: some View {
        let profile = profiles.profiles.first { $0.id == profileID }
        ClashMacRulesPageLeading(
            scheme: ClashMacRulesPage.schemeValue(profileID: profileID, in: library.snapshot, isRead: library.phase == .ready),
            schemePage: schemePage,
            customRules: customRules,
            customState: ClashMacRulesPage.customRules(of: profile),
            configurationName: profile?.label ?? "",
            addCustomRule: addCustomRule,
            palette: palette
        )
        .task { await readLibrary() }
    }
}

 
 
 
 
 
struct ClashMacRulesPageEditHost: View {
    @ObservedObject var commands: ClashMacRulesPageCommands
    @ObservedObject var profiles: ProfilesViewModel
    @ObservedObject var library: ClashMacConfigurationLibraryModel
    let profileID: String
    let editor: @MainActor (_ composed: Bool) -> ClashMacRuleEditorActions
    let customRules: ClashMacCustomRulesActions
    let saveAsScheme: @MainActor (String) -> Void
    let syntax: ClashMacEditorSyntax?
    @State private var built: (key: String, actions: ClashMacRuleEditorActions)?

     
     
    private var composed: Bool {
        library.snapshot.recipes.first { $0.id == profileID }.map { $0.preservesOriginal != true } ?? false
    }

    private var key: String { "\(profileID)#\(composed)" }

    var body: some View {
        content
            .task(id: key) { built = (key, editor(composed)) }
            .environment(\.clashMacEditorSyntax, syntax)
             
             
            .environment(
                \.clashGroupIconImages,
                (ClashProxiesDisplayPreferences.uiTestOverride() ?? ClashProxiesDisplayPreferences.load()).groupIconImages
            )
    }

    @ViewBuilder private var content: some View {
        if let built, built.key == key {
            table(built.actions).id(key)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func table(_ actions: ClashMacRuleEditorActions) -> ClashMacRuleEditorSheet {
        let snapshot = library.snapshot
        let isRecipe = snapshot.recipes.contains { $0.id == profileID }
        let profile = profiles.profiles.first { $0.id == profileID }
        let section = ClashMacRulesPageCustomRulesSection(actions: customRules, customState: ClashMacRulesPage.customRules(of: profile))
        let title: ClashDisplayText? = ClashMacRulesPage.rulesGroupTitle(profileID: profileID, in: snapshot, isRead: library.phase == .ready)
         
         
        var saveAs: (@MainActor (String) -> Void)?
        if isRecipe { saveAs = saveAsScheme }
        let restores: Bool = ClashMacRulesPage.offersRestore(profileID: profileID, in: snapshot)
        let page = ClashMacRuleEditorSheet.RulesPage(leading: AnyView(section), title: title, addRequests: commands.addRequests,
                                                     saveAsScheme: saveAs, schemeName: profile?.label ?? "", offersRestore: restores)
        return ClashMacRuleEditorSheet(actions: actions, presentation: .page, rulesPage: page)
    }
}
