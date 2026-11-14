import ClashClientKit
import ClashClientUI
import ClashMacClient
import SwiftUI

 
struct ClashMacSourceEditorRequest: Hashable, Codable {
    let profileID: String
     
     
    var nodeSourceID: String? = nil
     
     
    var collection: ClashMacCollectionReference? = nil
}

 
 
struct ClashMacCollectionReference: Hashable, Codable {
    let sourceID: String
    let kind: String
    let key: String

    init(_ entry: ConfigurationCollectionEntry) {
        sourceID = entry.id.sourceID
        kind = entry.id.kind.rawValue
        key = entry.id.key
    }

    func matches(_ entry: ConfigurationCollectionEntry) -> Bool {
        entry.id.sourceID == sourceID && entry.id.kind.rawValue == kind && entry.id.key == key
    }
}

 
 
 
 
struct ClashMacSourceEditorWindow: View {
    let request: ClashMacSourceEditorRequest
     
    @ObservedObject var profiles: ProfilesViewModel
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var rawYAML: String??
     
     
     
     
     
     
    @State private var tooLarge = false
     
     
     
     
    @State private var savesIndependentSource = false

     
     
     
    static func savesIndependentSource(profileID: String, in snapshot: ConfigurationLibrarySnapshot) -> Bool {
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return false }
        return recipe.preservesOriginal != true
    }

    var body: some View {
        if let collection = request.collection {
            ClashMacCollectionSourceEditorWindow(reference: collection, profiles: profiles)
        } else if let sourceID = request.nodeSourceID {
            ClashMacNodeSourceEditorWindow(sourceID: sourceID, profiles: profiles)
        } else if let profile = profiles.profiles.first(where: { $0.id == request.profileID }) {
            content(for: profile)
                 
                 
                .task(id: request.profileID) {
                    guard rawYAML == nil, !tooLarge else { return }
                    let workingDir = profiles.workingDir
                    if await Task.detached(priority: .userInitiated, operation: {
                        ProfilesViewModel.sourceIsTooLargeToReadWhole(profile, workingDir: workingDir)
                    }).value {
                        tooLarge = true
                        return
                    }
                    if let library = profiles.configurationLibraryStore {
                        let id = profile.id
                        savesIndependentSource = (try? await Task.detached(priority: .userInitiated) {
                            Self.savesIndependentSource(profileID: id, in: try library.snapshot())
                        }.value) ?? false
                    }
                     
                     
                     
                     
                    rawYAML = .some(await profiles.loadSourceYAML(for: profile))
                }
        } else {
            ClashEmptyState(
                title: "No Profile",
                message: "The profile is no longer available.",
                symbol: .curlybraces
            )
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    @ViewBuilder
    private func content(for profile: Profile) -> some View {
        if tooLarge, let workingDir = profiles.workingDir {
             
             
            ClashMacSourceViewer(
                url: workingDir.appendingPathComponent("store/\(profile.id)/source.yaml"),
                title: profile.label
            )
            .accessibilityIdentifier("source-editor.too-large")
        } else if let rawYAML {
            ClashWindowDepartureHost {
                ProfileEditView(
                    profile: profile,
                    rawYAML: rawYAML,
                    savesIndependentSource: savesIndependentSource
                ) { updated, rawYAML, resources, disablingAutoUpdate in
                    try await profiles.updateEdited(
                        updated,
                        sourceYAML: rawYAML,
                        resourceFiles: resources,
                        disablingAutoUpdate: disablingAutoUpdate
                    )
                }
            } windowGuard: { controller in
                ClashMacWindowCloseGuard(controller: controller)
            }
            .navigationTitle(Text(verbatim: profile.label))
            .navigationSubtitle("Edit Source")
            .frame(minWidth: 640, minHeight: 480)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text(verbatim: profile.label))
                .navigationSubtitle("Edit Source")
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}

 
 
 
struct ClashMacNodeSourceEditorWindow: View {
    let sourceID: String
    @ObservedObject var profiles: ProfilesViewModel
    @State private var loaded: (record: ConfigurationSourceRecord, yaml: String, version: ConfigurationSourceVersion)?
    @State private var errorMessage: String?
    @Environment(\.locale) private var locale

    var body: some View {
        if let loaded {
            ClashWindowDepartureHost {
                ProfileEditView(
                    profile: Profile(
                        id: loaded.record.id, label: loaded.record.label, source: .clipboard, autoUpdate: false,
                        updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil,
                        order: 0, lastUpdatedAt: nil
                    ),
                    rawYAML: loaded.yaml,
                    editorTitle: "Edit Nodes Source"
                ) { _, text, files, _ in
                    guard let text else { return }
                    guard files.isEmpty else { throw CocoaError(.featureUnsupported) }
                    let next = try await profiles.saveConfigurationNodeSource(loaded.version, yaml: text)
                    ClashMacLibraryBridge.apply(next)
                }
            } windowGuard: { controller in
                ClashMacWindowCloseGuard(controller: controller)
            }
            .navigationTitle(Text(clash: ClashConfigurationSourceCopy.name(loaded.record)))
            .navigationSubtitle(Text(clash: .copy("Edit Nodes Source")))
            .frame(minWidth: 640, minHeight: 480)
        } else if let errorMessage {
            ClashEmptyState(title: "Configuration Unavailable", message: errorMessage, symbol: .curlybraces)
                .frame(minWidth: 480, minHeight: 320)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 480, minHeight: 320)
                .task(id: sourceID) { await load() }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = sourceID
            loaded = try await Task.detached {
                guard let current = try store.snapshot().sources.first(where: { $0.id == id }) else {
                    throw ConfigurationLibraryError.missingDependency(id)
                }
                let payload = try store.payload(.init(current))
                guard case .object(let entries) = try OrderedJSON.parse(payload.documentJSON) else {
                    throw ConfigurationLibraryError.unreadable
                }
                let nodes = OrderedJSON.object(entries.filter { ["proxies", "proxy-providers"].contains($0.key) })
                return (current, try ConfigTransforms.jsonToYAML(nodes.serialized()), ConfigurationSourceVersion(current))
            }.value
        } catch {
            errorMessage = ClashErrorCopy.message(error, locale: locale)
        }
    }
}

 
 
 
struct ClashMacCollectionSourceEditorWindow: View {
    let reference: ClashMacCollectionReference
    @ObservedObject var profiles: ProfilesViewModel
    @State private var loaded: (entry: ConfigurationCollectionEntry, yaml: String)?
    @State private var errorMessage: String?
    @Environment(\.locale) private var locale

    var body: some View {
        if let loaded {
            ClashWindowDepartureHost {
                ProfileEditView(
                    profile: Profile(
                        id: loaded.entry.source.id, label: loaded.entry.collection.name, source: .clipboard, autoUpdate: false,
                        updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil,
                        order: 0, lastUpdatedAt: nil
                    ),
                    rawYAML: loaded.yaml,
                    editorTitle: "Edit Source"
                ) { _, text, files, _ in
                    guard let text else { return }
                    guard files.isEmpty else { throw CocoaError(.featureUnsupported) }
                    let json = try ConfigTransforms.yamlToJSON(text)
                    let next = try await profiles.saveConfigurationCollection(loaded.entry, definitionJSON: json)
                    ClashMacLibraryBridge.apply(next)
                }
            } windowGuard: { controller in
                ClashMacWindowCloseGuard(controller: controller)
            }
            .navigationTitle(Text(verbatim: loaded.entry.collection.name))
            .navigationSubtitle(Text(clash: .copy("Edit Source")))
            .frame(minWidth: 640, minHeight: 480)
        } else if let errorMessage {
            ClashEmptyState(title: "Configuration Unavailable", message: errorMessage, symbol: .curlybraces)
                .frame(minWidth: 480, minHeight: 320)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 480, minHeight: 320)
                .task(id: reference) { await load() }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let reference = reference
            loaded = try await Task.detached {
                let snapshot = try store.snapshot()
                guard let entry = try store.collectionCatalog(snapshot).first(where: { reference.matches($0) }) else {
                    throw ConfigurationLibraryError.missingDependency(reference.key)
                }
                return (entry, try ConfigTransforms.jsonToYAML(entry.collection.definition.serialized()))
            }.value
        } catch {
            errorMessage = ClashErrorCopy.message(error, locale: locale)
        }
    }
}
