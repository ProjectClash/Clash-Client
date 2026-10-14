import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
public struct ClashMacPageObject: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case group, ruleSet, listener }
    public let kind: Kind
    public let name: String
     
    public let type: String
     
    public let port: String?
     
    public let index: Int
    public var id: String { kind.rawValue + "-" + String(index) }

    public init(kind: Kind, name: String, type: String, port: String? = nil, index: Int) {
        self.kind = kind; self.name = name; self.type = type; self.port = port; self.index = index
    }
}

 
 
 
 
 
public struct ClashMacPageObjects: Equatable, Sendable {
    public var groups: [ClashMacPageObject] = []
    public var ruleSets: [ClashMacPageObject] = []
    public var listeners: [ClashMacPageObject] = []

    public init(groups: [ClashMacPageObject] = [], ruleSets: [ClashMacPageObject] = [], listeners: [ClashMacPageObject] = []) {
        self.groups = groups; self.ruleSets = ruleSets; self.listeners = listeners
    }

     
     
     
     
    static func read(_ running: OrderedJSON, listsOriginal: Bool,
                     schemeGroups: [(name: String, type: String)]?) -> ClashMacPageObjects {
        var objects = read(running, listsOriginal: listsOriginal)
        if let schemeGroups {
            objects.groups = schemeGroups.enumerated().map { index, group in
                ClashMacPageObject(kind: .group, name: group.name, type: group.type, index: index)
            }
        }
        return objects
    }

     
    static func read(_ running: OrderedJSON, listsOriginal: Bool) -> ClashMacPageObjects {
        func word(_ value: OrderedJSON?) -> String? {
            switch value {
            case .string(let text)?: return text
            case .scalar(let token)?: return token == "null" ? nil : token
            default: return nil
            }
        }
        var objects = ClashMacPageObjects()
        if listsOriginal {
            if case .array(let items)? = running.node(at: ["proxy-groups"]) {
                objects.groups = items.enumerated().compactMap { index, item in
                    guard let name = word(item.topLevelValue("name")), !name.isEmpty else { return nil }
                    return ClashMacPageObject(kind: .group, name: name, type: word(item.topLevelValue("type")) ?? "",
                                             port: nil, index: index)
                }
            }
            if case .object(let entries)? = running.node(at: ["rule-providers"]) {
                objects.ruleSets = entries.enumerated().map { index, entry in
                    ClashMacPageObject(kind: .ruleSet, name: entry.key, type: word(entry.value.topLevelValue("type")) ?? "",
                                      port: nil, index: index)
                }
            }
        }
        if case .array(let items)? = running.node(at: ["listeners"]) {
            objects.listeners = items.enumerated().map { index, item in
                 
                ClashMacPageObject(kind: .listener,
                                  name: word(item.topLevelValue("name")).flatMap { $0.isEmpty ? nil : $0 }
                                      ?? ClashMacObjectListPage.title(of: item, at: index),
                                  type: word(item.topLevelValue("type")) ?? "", port: word(item.topLevelValue("port")),
                                  index: index)
            }
        }
        return objects
    }
}

 
enum ClashMacPageObjectRows {
     
     
    static func detail(_ item: ClashMacPageObject, copy: ConfigurationFieldCopy, locale: Locale) -> String {
        let path: String
        switch item.kind {
        case .group: path = "proxy-groups[*].type"
        case .ruleSet: path = "rule-providers.*.type"
        case .listener: path = "listeners[*].type"
        }
        let words = copy.entry(forPath: path, language: ConfigurationFieldCopy.Language(locale: locale))?
            .presets.first { $0.value == item.type }?.label ?? item.type
        return [words, item.port].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

     
     
    static func push(_ page: AnyView?, with pushRoute: ClashRoutePusher?, onReturn: @escaping () -> Void) {
        guard let page, let pushRoute else { return }
        let token = UUID()
        ClashViewRouteRegistry.set(token, ownership: .oneShot, onReturn: onReturn) { page }
        pushRoute(ClashViewRoute(id: token))
    }
}

 
 
 
struct ClashMacSearchField: Hashable, Identifiable {
    let path: String
    let section: ConfigurationOutlineSection
     
    let basePath: [String]
    let key: String
    let title: String
     
     
    var onLANShare = false
    var id: String { path }

     
     
     
     
    static func index(_ catalog: ConfigurationFieldCatalog, copy: ConfigurationFieldCopy, locale: Locale,
                      lanShareKeys: Set<String> = []) -> [ClashMacSearchField] {
        let pages: Set<ConfigurationOutlineSection> = [.general, .dns, .sniffer, .mitm, .inbound, .ntp, .experimental]
        return catalog.fields.compactMap { field in
            guard !field.path.contains("["), !field.path.contains("*") else { return nil }
            let parts = field.path.split(separator: ".").map(String.init)
            guard let top = parts.first, let key = parts.last else { return nil }
            let section = ConfigurationOutline.section(forTopLevelKey: top)
            guard pages.contains(section) else { return nil }
            return ClashMacSearchField(path: field.path, section: section, basePath: Array(parts.dropLast()), key: key,
                                      title: copy.title(for: field, key: key, locale: locale),
                                      onLANShare: parts.count == 1 && lanShareKeys.contains(key))
        }
    }

     
     
    func matches(_ needle: String) -> Bool {
        title.lowercased().contains(needle) || key.lowercased().contains(needle) || path.lowercased().contains(needle)
    }
}

 
 
 
 
struct ClashMacConfigurationSearchResults: View {
    let query: String
    let objects: ClashMacPageObjects
    let fields: [ClashMacSearchField]
    let page: @MainActor (ClashMacPageObject) -> AnyView?
    let fieldPage: @MainActor (ClashMacSearchField) -> AnyView?
    var onReturn: () -> Void = {}
    @Environment(\.clashPushRoute) private var pushRoute
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

     
    static let shownAtMost = 30

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var body: some View {
        let needle = needle
        let groups = objects.groups.filter { $0.name.lowercased().contains(needle) }
        let ruleSets = objects.ruleSets.filter { $0.name.lowercased().contains(needle) }
        let listeners = objects.listeners.filter { $0.name.lowercased().contains(needle) }
        let settings = fields.filter { $0.matches(needle) }
        if groups.isEmpty, ruleSets.isEmpty, listeners.isEmpty, settings.isEmpty {
            Section {
                Text(clash: .copy("No results")).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.configuration.search.none")
            }
        }
        objectSection(groups, title: ClashMacConfigurationOutlineCard.title(.proxyGroups))
        objectSection(ruleSets, title: ClashMacConfigurationOutlineCard.title(.ruleProviders))
        objectSection(listeners, title: .copy("Inbound Listeners"))
        if !settings.isEmpty {
            Section {
                ForEach(settings.prefix(Self.shownAtMost)) { field in
                    Button { ClashMacPageObjectRows.push(fieldPage(field), with: pushRoute, onReturn: onReturn) } label: {
                        resultRow(title: field.title, detail: Self.detail(field, locale: locale))
                    }
                    .buttonStyle(.plain)
                        .accessibilityIdentifier("configuration-center.configuration.search.field.\(field.path)")
                }
            } header: {
                Text(clash: .copy("Settings"))
            }
        }
    }

    @ViewBuilder
    private func objectSection(_ items: [ClashMacPageObject], title: ClashDisplayText) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items.prefix(Self.shownAtMost)) { item in
                    Button { ClashMacPageObjectRows.push(page(item), with: pushRoute, onReturn: onReturn) } label: {
                        resultRow(title: item.name, detail: Self.detail(item, copy: copy, locale: locale))
                    }
                    .buttonStyle(.plain)
                        .accessibilityIdentifier("configuration-center.configuration.search.object.\(item.id)")
                }
            } header: {
                Text(clash: title)
            }
        }
    }

     
     
     
    static func detail(_ field: ClashMacSearchField, locale: Locale) -> String {
        ClashCopy.string(for: field.onLANShare ? .copy("LAN Proxy Share") : ClashMacConfigurationOutlineCard.title(field.section),
                        locale: locale)
    }

     
     
    static func detail(_ item: ClashMacPageObject, copy: ConfigurationFieldCopy, locale: Locale) -> String {
        ClashMacPageObjectRows.detail(item, copy: copy, locale: locale)
    }

    private func resultRow(title: String, detail: String) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Text(verbatim: title).lineLimit(1)
            Spacer(minLength: ClashTheme.Spacing.compact)
            Text(verbatim: detail).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
