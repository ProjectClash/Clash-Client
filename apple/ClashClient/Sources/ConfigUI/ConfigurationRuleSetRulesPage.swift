#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 

 

 
 
 
 
 
@MainActor
final class ConfigurationLocalRuleSetLines: ObservableObject {
    let model: ProfilesViewModel
     
    @Published private(set) var set: ConfigurationLocalRuleSet
     
     
    @Published private(set) var failure: ClashDisplayText?
    @Published private(set) var isSaving = false
     
    var changed: (ConfigurationLibrarySnapshot) -> Void = { _ in }

    init(model: ProfilesViewModel, set: ConfigurationLocalRuleSet) {
        self.model = model
        self.set = set
    }

     
     
    nonisolated static func isWrittenHere(_ set: ConfigurationLocalRuleSet) -> Bool {
        set.link == nil && !looksLikeLink(set.input)
    }

     
    nonisolated static func looksLikeLink(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains("\n") && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
    }

     
     
    nonisolated static func lines(of input: String) -> [String] {
        input.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }

    var lines: [String] { Self.lines(of: set.input) }

     
     
    @discardableResult
    func setLine(_ line: String, at index: Int?) async -> Bool {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        var lines = self.lines
        if let index, lines.indices.contains(index) { lines[index] = line } else { lines.append(line) }
        return await save(lines)
    }

    @discardableResult
    func delete(at offsets: IndexSet) async -> Bool {
        var lines = self.lines
        lines.remove(atOffsets: offsets)
        return await save(lines)
    }

     
     
     
    private func save(_ lines: [String]) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let input = lines.joined(separator: "\n")
            let read = try await ConfigurationTowerRuleReader.ruleSet(input)
            let value = ConfigurationLocalRuleSet(id: set.id, name: set.name, input: input, rules: read.rules,
                                                  link: read.link, behavior: read.behavior)
            let now = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
             
            guard now.localRuleSets?.first(where: { $0.id == set.id }) == set else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let library = try await model.saveConfigurationLocalRuleSet(value, deleting: nil, generation: now.generation)
            set = library.localRuleSets?.first { $0.id == value.id } ?? value
            failure = nil
            changed(library)
            return true
        } catch {
            failure = ClashErrorCopy.text(error)
            return false
        }
    }
}

 

 
struct ConfigurationRuleSetRulesPage: View {
    enum Source {
        case mine(ConfigurationLocalRuleSet)
        case collection(ConfigurationCollectionEntry)
    }

    let model: ProfilesViewModel
    let source: Source
    let title: String
     
     
    let sharedNote: String?
    let changed: (ConfigurationLibrarySnapshot) -> Void

    init(model: ProfilesViewModel, source: Source, title: String, sharedNote: String?,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.model = model; self.source = source; self.title = title; self.sharedNote = sharedNote; self.changed = changed
    }

     
     
     
     
    static func sharedNote(users: [String], locale: Locale) -> String? {
        guard users.count > 1 else { return nil }
        return ClashCopy.format(ConfigurationSchemeChangeNote.alsoChangesKey, locale: locale,
                                ConfigurationSchemeDetailSnapshot.names(users, locale: locale))
    }

    var body: some View {
        Group {
            switch source {
            case .mine(let set) where ConfigurationLocalRuleSetLines.isWrittenHere(set):
                ConfigurationRuleSetWrittenRules(model: model, set: set, sharedNote: sharedNote, changed: changed)
            case .mine(let set):
                ConfigurationRuleSetLinkedRules(set: set)
            case .collection(let entry):
                ConfigurationRuleSetCollectionRules(model: model, entry: entry)
            }
        }
        .clashPageTitle(.verbatim(title), watchAs: "rule-set-rules")
    }
}

 
 
 
private struct ConfigurationRuleSetWrittenRules: View {
    let sharedNote: String?
    @StateObject private var lines: ConfigurationLocalRuleSetLines
     
    @State private var open: LineRoute?

    private struct LineRoute: Identifiable {
        let id = UUID()
        let index: Int?
        let raw: String
    }

    init(model: ProfilesViewModel, set: ConfigurationLocalRuleSet, sharedNote: String?,
         changed: @escaping (ConfigurationLibrarySnapshot) -> Void) {
        self.sharedNote = sharedNote
        let lines = ConfigurationLocalRuleSetLines(model: model, set: set)
        lines.changed = changed
        _lines = StateObject(wrappedValue: lines)
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(lines.lines.enumerated()), id: \.offset) { index, line in
                    Button { open = LineRoute(index: index, raw: line) } label: {
                        ConfigurationRuleRow(line, hasTarget: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("configuration.rule-set-rules.row")
                }
                .onDelete { offsets in Task { await lines.delete(at: offsets) } }
                Button { open = LineRoute(index: nil, raw: "") } label: {
                    Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: ClashSymbol.plus.name) }
                }
                .disabled(lines.isSaving)
                .accessibilityIdentifier("configuration.rule-set-rules.add")
            } footer: {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    if let failure = lines.failure {
                        Text(clash: failure).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration.rule-set-rules.failure")
                    }
                    if let sharedNote {
                        Text(verbatim: sharedNote).accessibilityIdentifier("configuration.rule-set-rules.shared-note")
                    }
                }
            }
        }
        .clashProductModal(item: $open, role: .form) { route in
            RuleBuilderAdapter(raw: route.raw, showsPersonalMetadata: false, showsTarget: false) { line in
                Task { await lines.setLine(line, at: route.index) }
            }
            .clashModalPresentation(.page)
        }
    }
}

 
 
private struct ConfigurationRuleSetLinkedRules: View {
    let set: ConfigurationLocalRuleSet

    var body: some View {
        Form {
            Section {
                ForEach(Array(set.rules.enumerated()), id: \.offset) { _, line in
                    ConfigurationRuleRow(line, hasTarget: false)
                        .accessibilityIdentifier("configuration.rule-set-rules.row")
                }
            }
        }
    }
}

 
 
 
private struct ConfigurationRuleSetCollectionRules: View {
    @StateObject private var reader: ConfigurationCollectionReader
    @Environment(\.locale) private var locale

    init(model: ProfilesViewModel, entry: ConfigurationCollectionEntry) {
        _reader = StateObject(wrappedValue: ConfigurationCollectionReader(model: model, entry: entry))
    }

    var body: some View {
        Form {
            Section {
                ForEach(reader.rows) { row in
                    Text(verbatim: row.title).textSelection(.enabled)
                        .accessibilityIdentifier("configuration.rule-set-rules.row")
                }
                if reader.rows.isEmpty && !reader.loading && !reader.query.isEmpty { Text("No results") }
                if let offset = reader.page.nextOffset {
                    Button("Load More") { Task { await reader.load(offset: offset) } }
                        .disabled(reader.loading)
                        .accessibilityIdentifier("configuration.rule-set-rules.more")
                }
            } footer: {
                if reader.rows.isEmpty, let message = reader.page.statusMessage(locale: locale) {
                    Text(verbatim: message).accessibilityIdentifier("configuration.rule-set-rules.status")
                } else if let error = reader.shownError {
                    Text(verbatim: error).foregroundStyle(.red)
                }
            }
        }
        .clashProductModalSearchable(text: $reader.query)
        .task(id: reader.query) {
            reader.locale = locale
            if !reader.query.isEmpty { try? await Task.sleep(nanoseconds: 180_000_000) }
            guard !Task.isCancelled else { return }
            await reader.load()
        }
    }
}
#endif
