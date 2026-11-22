import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
public struct ClashMacPolicyGroupDetailPage: View {
    private let actions: ClashMacRuleEditorActions
    private let group: String

    public init(actions: ClashMacRuleEditorActions, group: String) {
        self.actions = actions
        self.group = group
    }

    public var body: some View {
        ClashMacRuleEditorSheet(actions: actions, initialPane: .groups, presentation: .page, singleGroup: group)
    }
}

 
 
public enum ClashMacPolicyGroupPage {
     
     
    public static func refusal(deleting id: UUID, in draft: ConfigurationRuleDraft, locale: Locale) -> String? {
        guard let group = draft.groups.first(where: { $0.id == id }) else { return nil }
        return ClashTowerGroupDeletionCopy.refusal(draft.groupUsers(id), group: group.name, locale: locale)
    }

     
     
    public static func applying(_ document: OrderedJSON, to id: UUID, in draft: ConfigurationRuleDraft) throws -> ConfigurationRuleDraft {
        var draft = draft
        try draft.setGroup(document, groupID: id)
        return draft
    }

     
    public static func undoing(_ deletion: ConfigurationRuleGroupDeletion, in draft: ConfigurationRuleDraft) throws -> ConfigurationRuleDraft {
        var draft = draft
        try draft.restoreGroupDeletion(deletion)
        return draft
    }
}

 
 
 
 
 
public struct ClashMacGroupExcludesHook {
    public var title: @MainActor () -> ClashDisplayText
    public var summary: @MainActor (OrderedJSON) -> ClashDisplayText
    public var page: @MainActor (_ group: String, _ document: OrderedJSON,
                                 _ write: @escaping @MainActor (String, OrderedJSON?) async -> String?) -> AnyView

    public init(title: @escaping @MainActor () -> ClashDisplayText,
                summary: @escaping @MainActor (OrderedJSON) -> ClashDisplayText,
                page: @escaping @MainActor (String, OrderedJSON, @escaping @MainActor (String, OrderedJSON?) async -> String?) -> AnyView) {
        self.title = title
        self.summary = summary
        self.page = page
    }
}

 
 
 
 
 
public enum ClashMacGroupIncludeAll {
    public static let keys = ["include-all", "include-all-proxies", "include-all-providers"]

     
    public static func isOn(_ key: String, in document: OrderedJSON) -> Bool {
        switch document.topLevelValue(key) {
        case .scalar(let value)?, .string(let value)?: return value.lowercased() == "true"
        default: return false
        }
    }

     
    public static func setting(_ key: String, on: Bool, in document: OrderedJSON) -> OrderedJSON {
        guard on || document.topLevelValue(key) != nil else { return document }
        return document.settingTopLevel(key, to: .scalar(on ? "true" : "false"))
    }
}

 
 
 
 
enum ClashMacGroupExcludesSync {
    static func extra(_ extra: OrderedJSON, writing key: String, _ value: OrderedJSON?) -> OrderedJSON {
        value.map { extra.settingTopLevel(key, to: $0) } ?? extra.removingTopLevel(key)
    }
}
