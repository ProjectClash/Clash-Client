import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
public struct ClashMacOriginalProvidersActions {
     
     
    public var load: @MainActor () async throws -> [ClashMacOriginalNode]?
     
     
    public var entrySettings: ClashMacSettingsSectionActions
     
    public var add: @MainActor (_ name: String, _ type: String, _ location: String) async throws -> Void
     
    public var librarySources: @MainActor () async throws -> [ClashMacLibrarySource]
     
     
    public var addFromLibrary: @MainActor (ClashMacLibrarySource) async throws -> ClashDisplayText?
     
     
    public var delete: @MainActor (String) async throws -> Void
     
     
    public var takenNames: @MainActor () async throws -> Set<String>
     
    public var catalog: @MainActor () async -> ConfigurationFieldCatalog?
     
     
    public var updateNote: ClashDisplayText?

    public init(
        load: @escaping @MainActor () async throws -> [ClashMacOriginalNode]?,
        entrySettings: ClashMacSettingsSectionActions,
        add: @escaping @MainActor (String, String, String) async throws -> Void,
        librarySources: @escaping @MainActor () async throws -> [ClashMacLibrarySource],
        addFromLibrary: @escaping @MainActor (ClashMacLibrarySource) async throws -> ClashDisplayText?,
        delete: @escaping @MainActor (String) async throws -> Void,
        takenNames: @escaping @MainActor () async throws -> Set<String>,
        catalog: @escaping @MainActor () async -> ConfigurationFieldCatalog?,
        updateNote: ClashDisplayText? = nil
    ) {
        self.load = load; self.entrySettings = entrySettings; self.add = add; self.librarySources = librarySources
        self.addFromLibrary = addFromLibrary; self.delete = delete; self.takenNames = takenNames
        self.catalog = catalog; self.updateNote = updateNote
    }
}

 
 
 
 
 
 
 
public struct ClashMacOriginalProvidersPage: View {
    private let actions: ClashMacOriginalProvidersActions
    @State private var providers: [ClashMacOriginalNode]?
    @State private var catalog: ConfigurationFieldCatalog?
    @State private var taken: Set<String> = []
    @State private var failure: String?
     
     
    @Environment(\.clashFeedback) private var feedback
     
     
    @State private var busy = false
    @State private var selection = Set<ClashMacOriginalNode.ID>()
    @State private var adding = false
     
    @State private var library: [ClashMacLibrarySource]?
     
     
     
     
     
     
     
     
    @State private var writes = ClashMacPageWrites<ClashMacLibrarySource.ID>()
    @State private var libraryFailure: String?
    @State private var deleting: ClashMacOriginalNode?
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    public init(actions: ClashMacOriginalProvidersActions) {
        self.actions = actions
    }

     
    static func types(_ catalog: ConfigurationFieldCatalog?) -> [String] {
        let offered = catalog?.field(atCatalogPath: "proxy-providers.*.type")?.offeredValues().map(\.value) ?? []
        return offered.isEmpty ? ["http", "file", "inline"] : offered
    }

    public var body: some View {
        let typeNames = ClashMacValueWords.valueNames(path: "proxy-providers.*.type", copy: copy, locale: locale)
        List(selection: $selection) {
            if let failure {
                Section {
                    Text(verbatim: failure).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration-center.original-providers.error")
                }
            }
             
             
             
             
            librarySection
            Section {
                if let providers {
                    let own = Self.ownProviders(providers, library: library ?? [])
                    if providers.isEmpty, Self.offered(library ?? []).isEmpty {
                         
                         
                        Text(clash: .copy("No node sets yet. A node set brings nodes from a link or a file."))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("configuration-center.original-providers.empty")
                    }
                    ForEach(own) { provider in
                        ClashRoutedViewLink(onReturn: { Task { await load() } }) {
                            ClashMacSettingsSectionPage(section: .proxyProviders, basePath: ["proxy-providers", provider.name],
                                                       knownKeys: [], actions: actions.entrySettings)
                                .navigationTitle(Text(verbatim: provider.name))
                        } label: {
                            LabeledContent {
                                Text(verbatim: typeNames[provider.type.lowercased()] ?? provider.type)
                            } label: {
                                Text(verbatim: provider.name).lineLimit(1)
                            }
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.original-providers.provider.\(provider.index)")
                    }
                    newButton
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.original-providers.add")
                } else if failure == nil {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .listStyle(.inset)
         
        .contextMenu(forSelectionType: ClashMacOriginalNode.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let provider = providers?.first(where: { $0.id == id }) {
                Button(role: .destructive) { deleting = provider } label: { Text(clash: .copy("Delete")) }
                    .accessibilityIdentifier("configuration-center.original-providers.delete")
            }
        }
        .clashListRetainsRowSelection()
        .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(.proxyProviders)))
        .accessibilityIdentifier("configuration-center.original-providers")
        .task { await load() }
        .sheet(isPresented: $adding) {
            ClashMacNewProxyProviderSheet(types: Self.types(catalog), taken: taken.union((providers ?? []).map(\.name)), catalog: catalog,
                                         save: { name, type, location in
                try await writes.turns.run {
                    try await actions.add(name, type, location)
                    await load()
                }
            }, close: { adding = false })
        }
         
         
        .alert(Text(clash: .copy("Delete")), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { provider in
            Button(role: .destructive) {
                deleting = nil
                Task { await delete(provider) }
            } label: {
                Text(clash: .copy("Delete"))
            }
            .accessibilityIdentifier("configuration-center.original-providers.delete.confirm")
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: { provider in
            Text(verbatim: provider.name)
        }
    }

    private func say(_ sentence: ClashDisplayText?) {
        guard let sentence else { return }
        feedback?.say(.success(title: sentence, accessibilityIdentifier: "feedback.original-providers.added"), operation: "original-providers.add")
    }

     
    private var newButton: some View {
        Button { adding = true } label: {
            Label { Text(clash: .copy("New…")) } icon: { Image(systemName: "plus") }
        }
    }

     
     
     
     
     
    static func offered(_ sources: [ClashMacLibrarySource]) -> [ClashMacLibrarySource] {
        sources.filter { $0.setKind == .link }
    }

     
     
     
     
    static func title(_ source: ClashMacLibrarySource) -> String {
        source.addedSetName ?? source.label
    }

     
     
     
     
    static func detail(_ source: ClashMacLibrarySource) -> ClashDisplayText {
        let count = String(source.nodes.count)
        guard title(source) != source.label else { return .format("Link · %@ nodes", [count]) }
        return .format("%@ · Link · %@ nodes", [source.label, count])
    }

     
     
    static func ownProviders(_ providers: [ClashMacOriginalNode], library: [ClashMacLibrarySource]) -> [ClashMacOriginalNode] {
        let fromLibrary = Set(offered(library).compactMap(\.addedSetName))
        return providers.filter { !fromLibrary.contains($0.name) }
    }

     
     
     
    @ViewBuilder
    private var librarySection: some View {
        if let library {
            let offered = Self.offered(library)
            if !offered.isEmpty {
                Section {
                    ForEach(offered) { source in
                        ClashStoredToggle(writes.switches, key: source.id, stored: source.addedSetName != nil,
                                          identifier: "configuration-center.library-sources.source",
                                          write: { on in try await writeLibrary(source.id, on) }) {
                            Text(verbatim: Self.title(source)).lineLimit(1)
                            Text(clash: Self.detail(source))
                        }
                        .toggleStyle(.switch)
                    }
                } header: {
                    Text(clash: .copy("Node Library"))
                } footer: {
                    Text(clash: .copy("A link is added whole and updates as the library sets it to. To take single nodes, use Proxies."))
                }
            }
        } else if let libraryFailure {
            Section {
                Text(verbatim: libraryFailure).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.library-sources.error")
            }
        }
    }

    private func load() async {
        do {
            providers = try await actions.load() ?? []
            taken = try await actions.takenNames()
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = ClashErrorCopy.message(error, locale: locale)
        }
         
        do {
            library = try await actions.librarySources()
            libraryFailure = nil
        } catch is CancellationError {
        } catch {
            libraryFailure = ClashErrorCopy.message(error, locale: locale)
        }
        if catalog == nil { catalog = await actions.catalog() }
    }

     
     
     
    enum LibraryWrite: Equatable {
        case add(ClashMacLibrarySource)
        case delete(String)
        case nothing
    }

    static func libraryWrite(_ on: Bool, source: ClashMacLibrarySource?) -> LibraryWrite {
        guard let source else { return .nothing }
        if on, source.addedSetName == nil { return .add(source) }
        if !on, let name = source.addedSetName { return .delete(name) }
        return .nothing
    }

     
     
     
    private func writeLibrary(_ id: ClashMacLibrarySource.ID, _ on: Bool) async throws {
        let written: Bool
        switch Self.libraryWrite(on, source: library?.first { $0.id == id }) {
        case .add(let source): written = await apply { say(try await actions.addFromLibrary(source)) }
        case .delete(let name): written = await apply { try await actions.delete(name) }
        case .nothing: return
        }
        if !written { throw ClashStoredWriteSaidElsewhere() }
    }

     
     
    private func perform(_ work: @escaping @MainActor () async throws -> Void) async {
        await writes.turns.run {
            busy = true
            defer { busy = false }
            _ = await apply(work)
        }
    }

     
     
     
     
    private func apply(_ work: @escaping @MainActor () async throws -> Void) async -> Bool {
        var refusal: String?
        do {
            try await work()
        } catch is CancellationError {
        } catch {
            refusal = ClashErrorCopy.message(error, locale: locale)
        }
        await load()
        if let refusal { failure = refusal }
        return refusal == nil
    }

     
     
     
     
    private func delete(_ provider: ClashMacOriginalNode) async {
        await perform {
            do {
                try await actions.delete(provider.name)
                feedback?.say(ClashMacFeedbackSentences.deleted(provider.name, undoable: false, id: Self.deleteOperation),
                              operation: Self.deleteOperation)
            } catch is CancellationError {
            } catch {
                feedback?.say(ClashMacFeedbackSentences.couldNotDelete(provider.name, reason: ClashErrorCopy.message(error, locale: locale),
                                                                      id: Self.deleteOperation),
                              operation: Self.deleteOperation)
            }
        }
    }

    static let deleteOperation = "original-providers.delete"
}

 
 
 
struct ClashMacNewProxyProviderSheet: View {
     
    let types: [String]
     
    let taken: Set<String>
    let catalog: ConfigurationFieldCatalog?
    let save: @MainActor (String, String, String) async throws -> Void
    let close: @MainActor () -> Void
    @State private var name = ""
    @State private var type = ""
    @State private var location = ""
    @State private var busy = false
    @State private var failure: String?
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

     
     
    static func canSave(name: String, type: String, location: String, taken: Set<String>) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !taken.contains(name) && !type.isEmpty
            && (type == "inline" || !location.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var typeField: ConfigurationField? { catalog?.field(atCatalogPath: "proxy-providers.*.type") }
    private var locationKey: String { type == "http" ? "url" : "path" }
    private var locationField: ConfigurationField? { catalog?.field(atCatalogPath: "proxy-providers.*." + locationKey) }

    var body: some View {
        ClashMacSheetFrame(title: .copy("Add Proxy Provider"), width: 520, height: 340) {
            ClashMacSheetForm {
                Section {
                    TextField(text: $name) { Text(clash: .copy("Name")) }
                        .accessibilityIdentifier("configuration-center.providers.new.name")
                    Picker(selection: $type) {
                        ForEach(types, id: \.self) { value in
                            Text(verbatim: copy.valueLabel(value, for: typeField, locale: locale) ?? value).tag(value)
                        }
                    } label: {
                        Text(verbatim: copy.title(for: typeField, key: "type", locale: locale))
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("configuration-center.providers.new.type")
                    if type == "http" || type == "file" {
                        TextField(text: $location,
                                  prompt: copy.entry(for: locationField, locale: locale)?.example.map { Text(verbatim: $0) }) {
                            Text(verbatim: copy.title(for: locationField, key: locationKey, locale: locale))
                        }
                        .accessibilityIdentifier("configuration-center.providers.new.location")
                    }
                }
                if let failure {
                    Section {
                        Text(verbatim: failure).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("configuration-center.providers.new.error")
                    }
                }
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.providers.new.cancel",
                primaryTitle: .copy("Save"),
                primaryIdentifier: "configuration-center.providers.new.save",
                primaryDisabled: busy || !Self.canSave(name: name, type: type, location: location, taken: taken),
                isBusy: busy,
                onClose: close,
                onPrimary: {
                    let entry = (name.trimmingCharacters(in: .whitespaces), type, location.trimmingCharacters(in: .whitespaces))
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await save(entry.0, entry.1, entry.2)
                            close()
                        } catch is CancellationError {
                        } catch {
                            failure = ClashErrorCopy.message(error, locale: locale)
                        }
                    }
                }
            )
        }
        .onAppear { if type.isEmpty { type = types.first ?? "" } }
    }
}
