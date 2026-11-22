#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 

 
@MainActor
final class ConfigurationOnlineRuleLibrary: ObservableObject {
    let session: ConfigurationSchemeDraftSession
     
     
    let switches = ClashStoredSwitch<String>()
     
     
    @Published private(set) var loading: Set<String> = []
     
     
    @Published private(set) var failure: String?
    private let download: @Sendable (String) async throws -> ConfigurationRuleSetContent

    init(session: ConfigurationSchemeDraftSession,
         download: @escaping @Sendable (String) async throws -> ConfigurationRuleSetContent = {
             try await ConfigurationTowerRuleReader.ruleSet($0)
         }) {
        self.session = session
        self.download = download
    }

     
    static func entries(category: ConfigurationRuleCatalogCategory?, search: String) -> [ConfigurationRuleCatalogEntry] {
        ConfigurationRuleCatalog.builtIn.entries.filter { (category == nil || $0.category == category) && $0.matches(search) }
    }

    static func key(_ entry: ConfigurationRuleCatalogEntry) -> String { "catalog-" + entry.id }

     
    static func route(_ value: ConfigurationRuleCatalogDefaultRoute, locale: Locale) -> String {
        ClashCopy.string(value == .direct ? "Direct" : value == .reject ? "Block" : "Proxy", locale: locale)
    }

    func isOn(_ entry: ConfigurationRuleCatalogEntry) -> Bool {
        session.draft?.referencedRuleSets.contains(Self.key(entry)) == true
    }

    func isLoading(_ entry: ConfigurationRuleCatalogEntry) -> Bool { loading.contains(Self.key(entry)) }

     
     
     
     
     
    @discardableResult
    func toggle(_ entry: ConfigurationRuleCatalogEntry) async -> Bool {
        let key = Self.key(entry)
        guard !loading.contains(key), session.draft != nil else { return false }
        if isOn(entry) {
            let taken = await session.change { $0.removeRuleSet(key) }
            failure = taken ? nil : session.failure
            return taken
        }
        loading.insert(key)
        defer { loading.remove(key) }
        let content: ConfigurationRuleSetContent
        do {
            content = try await download(entry.sourceURLString)
        } catch {
            failure = ClashErrorCopy.message(error, locale: session.locale)
            return false
        }
        let name = entry.displayName, route = entry.defaultRoute.rawValue
        let added = await session.change { draft in
            try draft.addRuleSet(key: key, name: name, rules: content.rules, defaultRoute: route,
                                 link: content.link, behavior: content.behavior)
        }
        failure = added ? nil : session.failure
        return added
    }
}

 
struct ConfigurationOnlineRuleLibraryPage: View {
    @StateObject private var library: ConfigurationOnlineRuleLibrary
    @ObservedObject private var session: ConfigurationSchemeDraftSession
    @Environment(\.locale) private var locale
    @State private var category: ConfigurationRuleCatalogCategory?
    @State private var search = ""

    init(session: ConfigurationSchemeDraftSession) {
        _session = ObservedObject(wrappedValue: session)
        _library = StateObject(wrappedValue: ConfigurationOnlineRuleLibrary(session: session))
    }

    private var entries: [ConfigurationRuleCatalogEntry] {
        ConfigurationOnlineRuleLibrary.entries(category: category, search: search)
    }

    var body: some View {
        Form {
            Section {
                ForEach(entries) { entry in row(entry) }
                if entries.isEmpty { Text("No results").foregroundStyle(.secondary) }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Spacer()
                    Picker("Category", selection: $category) {
                        Text("All").tag(Optional<ConfigurationRuleCatalogCategory>.none)
                        ForEach(ConfigurationRuleCatalogCategory.allCases, id: \.self) { item in
                            Text(verbatim: item.displayName).tag(Optional(item))
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().textCase(nil)
                    .accessibilityIdentifier("configuration.online-rule-library.category")
                }
            } footer: {
                if let failure = library.failure {
                    Text(verbatim: failure).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration.online-rule-library.failure")
                }
            }
        }
        .clashProductModalSearchable(text: $search)
        .clashPageTitle(.copy("Online Rule Library"), watchAs: "Online Rule Library")
         
         
         
         
        .clashOnScreen { session.pageOnScreen($0) }
    }

     
     
    private func row(_ entry: ConfigurationRuleCatalogEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.emoji).font(.title3).frame(width: 36, height: 36)
                .background(.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.name).font(.body)
                Text(verbatim: entry.provider.displayName + " · " + ConfigurationOnlineRuleLibrary.route(entry.defaultRoute, locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if library.isLoading(entry) {
                ProgressView().accessibilityIdentifier("configuration.online-rule-library.loading")
            } else {
                 
                 
                 
                ClashStoredToggle(library.switches, key: ConfigurationOnlineRuleLibrary.key(entry), stored: library.isOn(entry),
                                  identifier: "configuration.online-rule-library.toggle", write: { on in
                    guard on != library.isOn(entry) else { return }
                    guard await library.toggle(entry) else { throw ClashStoredWriteSaidElsewhere() }
                }) { Text(verbatim: entry.name) }
                    .labelsHidden()
                    .disabled(session.draft == nil)
            }
        }
    }
}
#endif
