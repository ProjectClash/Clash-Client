import ClashClientKit
import ClashClientUI
import Combine
import SwiftUI

 
 
 
 
public struct ClashMacSectionLayout {
    public enum Control {
         
        case inline
         
        case page
         
        case drill
         
        case owned(ClashMacKeyOwner)
         
        case platform(String)
    }

    public struct Row: Identifiable {
        public let key: String
        public let path: [String]
        public let field: ConfigurationField?
        public let value: OrderedJSON?
        public let control: Control
         
        public let conditionalEffective: String?
        public var id: String { path.joined(separator: ".") }
        public init(key: String, path: [String], field: ConfigurationField?, value: OrderedJSON?, control: Control,
                    conditionalEffective: String? = nil) {
            self.key = key; self.path = path; self.field = field; self.value = value; self.control = control
            self.conditionalEffective = conditionalEffective
        }
    }

    public struct Group: Identifiable {
        public let id: String
        public let title: ClashDisplayText?
        public let rows: [Row]
         
        public let footer: String?
        public init(id: String, title: ClashDisplayText?, rows: [Row], footer: String? = nil) {
            self.id = id; self.title = title; self.rows = rows; self.footer = footer
        }
    }

    public var groups: [Group]
     
     
     
    public var platformDecided: [Row]
    public init(groups: [Group], platformDecided: [Row] = []) { self.groups = groups; self.platformDecided = platformDecided }
}

 
 
 
public struct ClashMacSettingsSectionDocument: Equatable {
     
     
    public var page: OrderedJSON
     
     
     
    public var ownLayer: OrderedJSON?
     
     
    public var scheme: String?
     
     
     
     
    public var scope: ClashDisplayText?

     
     
     
     
     
     
     
     
     
     
    public static func scope(running scheme: ConfigurationRuleScheme?, ownership: ConfigurationSchemePageOwnership,
                             ownLayer: Bool) -> ClashDisplayText {
        if !ownLayer, case .own(_, let label, let count) = ownership, count > 1, scheme?.ownViewBaseID == nil {
            return all(count, on: label)
        }
        return thisConfigurationOnly
    }

     
    public static func all(_ count: Int, on scheme: String) -> ClashDisplayText {
        .format("Changes here apply to all %@ configurations on rule scheme “%@”.", [String(count), scheme])
    }

    public static let thisConfigurationOnly = ClashDisplayText.copy("Changes here apply to this configuration only.")
     
    public var elsewhere: Set<String>
     
     
     
     
    public var owners: [String: ClashMacKeyOwner] = [:]
     
     
    public var platformReasons: [String: String]
     
     
     
     
     
    public var platformKeysKnown = false
     
     
     
    public var catalogVersion = 0
     
     
    public var activeConditions: Set<String> = []
     
     
    public var layout: ((_ basePath: [String]) -> ClashMacSectionLayout)? = nil
     
     
    public var ownDNSSwitch: Bool? = nil
     
    public var choices: [String: [String]]
     
     
     
    public var catalog: ConfigurationFieldCatalog?

    public init(page: OrderedJSON, ownLayer: OrderedJSON? = nil, scheme: String?,
                scope: ClashDisplayText? = nil, elsewhere: Set<String> = [],
                platformReasons: [String: String] = [:], choices: [String: [String]] = [:],
                catalog: ConfigurationFieldCatalog? = nil) {
        self.page = page; self.ownLayer = ownLayer; self.scheme = scheme; self.scope = scope
        self.elsewhere = elsewhere; self.platformReasons = platformReasons; self.choices = choices
        self.catalog = catalog
    }

     
    func field(at path: [String]) -> ConfigurationField? {
        catalog?.field(at: path.map(ConfigurationDocumentStep.key), in: running)
    }

     
    func control(at path: [String]) -> ClashMacFieldControl? {
        guard let field = field(at: path) else { return nil }
        let running = running
        return ClashMacFieldControl.make(field, value: running.node(at: path)) { ConfigurationReferenceNames.names($0, in: running) }
    }

     
    func control(for field: ConfigurationField) -> ClashMacFieldControl? {
        let running = running
        return ClashMacFieldControl.make(field, value: nil) { ConfigurationReferenceNames.names($0, in: running) }
    }

     
     
    func platformReason(at path: [String]) -> String? {
        let dotted = path.joined(separator: ".")
        if catalogVersion >= 3 {
             
             
             
             
             
             
            guard let decision = catalog?.platformDecision(forPath: path, in: running), decision.overridesTheFile else { return nil }
            return decision.reason ?? ""
        }
        if let reason = platformReasons[dotted] { return reason }
        guard !platformKeysKnown, let field = field(at: path), field.isPlatformDecided else { return nil }
        return field.platformReason ?? ""
    }

     
     
    func platformNote(at path: [String]) -> ClashDisplayText? {
         
         
        guard catalogVersion >= 3, let field = field(at: path),
              catalog?.conditionalDecision(forPath: path, in: running, conditions: activeConditions) != nil else { return nil }
        return ConfigurationValueWords.conditionalLine(for: field, conditions: activeConditions)
    }

     
    func items(at listPath: [String]) -> [OrderedJSON] {
        if case .array(let items)? = running.node(at: listPath) { return items }
        return []
    }

     
     
    func itemFields(of listPath: [String], at index: Int) -> [ConfigurationField] {
        guard let catalog else { return [] }
        return catalog.children(of: listPath.map(ConfigurationDocumentStep.key) + [.index(index)], in: running)
    }

     
     
     
    func newItemFields(of listPath: [String], type: String?) -> [ConfigurationField] {
        guard let catalog else { return [] }
        let prefix = listPath.joined(separator: ".") + "[" + (type ?? "") + "]."
        return catalog.fields.filter { $0.path.hasPrefix(prefix) && !$0.path.dropFirst(prefix.count).contains(".") }
    }

     
     
    func knownKeys(under path: [String]) -> [String] {
        guard let catalog else { return [] }
        return catalog.children(of: path.map(ConfigurationDocumentStep.key), in: running).compactMap {
            $0.path.split(separator: ".").last.map(String.init)
        }
    }

     
     
     
     
    func rows(section: ConfigurationOutlineSection, under basePath: [String], fallback: [String]) -> [ClashMacSectionRow] {
        let running = running
        var known = knownKeys(under: basePath)
        if catalog == nil { known = fallback }
        if basePath.isEmpty {
            known = known.filter { ConfigurationOutline.section(forTopLevelKey: $0) == section && !elsewhere.contains($0) }
        }
        var written: [String] = []
        if basePath.isEmpty {
            if case .object(let items) = running {
                written = items.map(\.key).filter {
                    ConfigurationOutline.section(forTopLevelKey: $0) == section && !elsewhere.contains($0)
                }
            }
        } else if case .object(let items)? = running.node(at: basePath) {
            written = items.map(\.key)
        }
        var seen = Set<String>()
        return (known + written).filter { seen.insert($0).inserted }.map { key in
            let path = basePath + [key]
            let value = running.node(at: path)
            let field = field(at: path)
            return ClashMacSectionRow(
                key: key, path: path, value: value, field: field,
                control: field.flatMap { field in
                    ClashMacFieldControl.make(field, value: value) { ConfigurationReferenceNames.names($0, in: running) }
                },
                owner: owners[path.joined(separator: ".")],
                platformReason: platformReason(at: path),
                platformNote: platformNote(at: path),
                usesDefault: value == nil,
                removable: value != nil && removes(path)
            )
        }
    }

     
     
    func row(for shared: ClashMacSectionLayout.Row) -> ClashMacSectionRow {
        let running = running
         
         
        let value = shows(shared.path) ? running.node(at: shared.path) : shared.value
        var owner: ClashMacKeyOwner?
        var reason: String?
        var drills = false
        switch shared.control {
        case .owned(let pageOwner): owner = pageOwner
        case .platform(let why): reason = why
        case .drill: drills = true
        case .inline, .page: break
        }
        var row = ClashMacSectionRow(
            key: shared.key, path: shared.path, value: value, field: shared.field,
            control: shared.field.flatMap { field in
                ClashMacFieldControl.make(field, value: value) { ConfigurationReferenceNames.names($0, in: running) }
            },
            owner: owner,
            platformReason: reason,
             
            platformNote: shared.conditionalEffective == nil ? nil : shared.field.flatMap { field in
                field.platformDecision?.condition.flatMap { ConfigurationValueWords.conditionalLine(for: field, conditions: [$0]) }
            },
            usesDefault: value == nil,
            removable: value != nil && removes(shared.path)
        )
        row.opensLevel = drills
        return row
    }

     
    @MainActor
    func noted(_ row: ClashMacSectionRow, by runsOver: ClashMacRunsOver?) -> ClashMacSectionRow {
        guard let runsOver else { return row }
        var row = row
        row.runsOver = runsOver(row.path, row.field, row.drillsIn, running)
        return row
    }

     
     
     
    public var running: OrderedJSON {
        let written = ownLayer.map { page.mergingAsTheCoreMerges($0) } ?? page
        return shownEdits.reduce(written) { (try? $0.applying($1)) ?? $0 }
    }

     
     
     
     
     
     
    public var shownEdits: [ConfigurationPageEdit] = []

     
    func shows(_ path: [String]) -> Bool {
        shownEdits.contains { edit in
            let written = edit.writtenPath
            return written.starts(with: path) || path.starts(with: written)
        }
    }

     
     
     
    func removes(_ path: [String]) -> Bool {
        guard let ownLayer else { return true }
         
         
        if removesFileText, page.node(at: path) != nil { return true }
        return ownLayer.node(at: path) != nil
    }

     
     
    public var removesFileText = false

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.page == rhs.page && lhs.ownLayer == rhs.ownLayer && lhs.scheme == rhs.scheme
            && lhs.scope == rhs.scope
            && lhs.elsewhere == rhs.elsewhere && lhs.platformReasons == rhs.platformReasons && lhs.choices == rhs.choices
            && lhs.platformKeysKnown == rhs.platformKeysKnown && lhs.catalogVersion == rhs.catalogVersion
            && lhs.activeConditions == rhs.activeConditions && lhs.removesFileText == rhs.removesFileText
            && lhs.catalog?.fields.count == rhs.catalog?.fields.count && lhs.shownEdits == rhs.shownEdits
    }
}

 
 
public struct ClashMacKeyOwner {
    public let title: ClashDisplayText
    public let push: (@MainActor () -> AnyView)?
    public let open: (@MainActor () -> Void)?
    public init(title: ClashDisplayText, push: (@MainActor () -> AnyView)? = nil, open: (@MainActor () -> Void)? = nil) {
        self.title = title; self.push = push; self.open = open
    }
}

 
struct ClashMacSectionRow: Identifiable {
    let key: String
     
    let path: [String]
     
     
    let value: OrderedJSON?
    let field: ConfigurationField?
    let control: ClashMacFieldControl?
    let owner: ClashMacKeyOwner?
    let platformReason: String?
     
    var platformNote: ClashDisplayText? = nil
     
     
    var runsOver: ClashDisplayText? = nil
     
    var caption: ClashDisplayText? { runsOver ?? platformNote }
     
     
    var opensLevel = false
    let usesDefault: Bool
     
    let removable: Bool
    var id: String { path.joined(separator: ".") }

     
     
     
    var expandsInPlace: Bool {
        if let kind = field?.kind { return kind == .object }
        if case .object? = value { return true }
        return false
    }

     
     
     
    var drillsIn: Bool { opensLevel || field?.kind == .map || field?.kind == .objectList }

     
     
    func summary(locale: Locale, copy: ConfigurationFieldCopy = .shared) -> ClashDisplayText {
        ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy)
    }
}

 
 
 
 
 
 
public typealias ClashMacRunsOver = @MainActor (_ path: [String], _ field: ConfigurationField?, _ opensPage: Bool,
                                               _ running: OrderedJSON) -> ClashDisplayText?

 
 
 
public enum ClashMacListenOff {
    case edits([ConfigurationPageEdit])
    case written
    case nothing
}

 
 
 
 
 
 
struct ClashMacSectionWrites: Equatable {
    enum Step: Equatable {
         
        case edits([ConfigurationPageEdit])
         
        case ownDNS(Bool)
         
        case turnOff([String])
    }

     
    private(set) var running: Step?
     
    private(set) var waiting: [Step] = []

    var busy: Bool { running != nil }

     
     
    mutating func take(_ step: Step) -> Step? {
        guard running == nil else {
            waiting.append(step)
            return nil
        }
        running = step
        return step
    }

     
     
    mutating func finish() -> Step? {
        guard !waiting.isEmpty else {
            running = nil
            return nil
        }
        var next = waiting.removeFirst()
        if case .edits(var edits) = next {
            while case .edits(let more)? = waiting.first {
                edits += more
                waiting.removeFirst()
            }
            next = .edits(edits)
        }
        running = next
        return next
    }

     
     
    var shownEdits: [ConfigurationPageEdit] {
        ((running.map { [$0] } ?? []) + waiting).flatMap { step -> [ConfigurationPageEdit] in
            switch step {
            case .edits(let edits): return edits
            case .turnOff(let path): return [.set(path: path, to: .string(""))]
            case .ownDNS: return []
            }
        }
    }

     
    var ownDNSPressed: Bool? {
        ((running.map { [$0] } ?? []) + waiting).reduce(nil) { pressed, step in
            if case .ownDNS(let on) = step { return on }
            return pressed
        }
    }
}

 
public struct ClashMacSettingsSectionActions {
     
     
    public var load: @MainActor (ConfigurationOutlineSection) async throws -> ClashMacSettingsSectionDocument
     
     
    public var save: @MainActor ([ConfigurationPageEdit], String?) async throws -> Void
     
    public var setOwnDNSSwitch: (@MainActor (Bool) async throws -> Void)? = nil
     
     
    public var geoValues: ClashMacGeoValueLoader? = nil
     
     
     
     
    public var lanShare: ClashMacLANShareEntry? = nil
     
     
     
     
    public var turnOff: (@MainActor ([String]) async throws -> ClashMacListenOff)? = nil
     
     
    public var runsOver: (@MainActor () async -> ClashMacRunsOver?)? = nil
     
     
     
     
     
     
    public var generalOverrides: (@MainActor () async -> ClashMacGeneralOverrides?)? = nil
     
     
     
     
    public var generalOverridesChanged: AnyPublisher<Void, Never>? = nil
    public init(load: @escaping @MainActor (ConfigurationOutlineSection) async throws -> ClashMacSettingsSectionDocument,
                save: @escaping @MainActor ([ConfigurationPageEdit], String?) async throws -> Void) {
        self.load = load; self.save = save
    }
}

 
 
 
 
public struct ClashMacGeneralOverrides {
    public let outboundMode: ClashDisplayText?
    public let logLevel: ClashDisplayText?
     
     
    public let followConfiguration: (@MainActor () async -> Void)?
    public init(outboundMode: ClashDisplayText? = nil, logLevel: ClashDisplayText? = nil,
                followConfiguration: (@MainActor () async -> Void)? = nil) {
        self.outboundMode = outboundMode
        self.logLevel = logLevel
        self.followConfiguration = followConfiguration
    }
}

 
 
struct ClashMacValueDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case text, number, toggle, list
        var id: String { rawValue }
        var title: ClashDisplayText {
            switch self {
            case .text: .copy("Text")
            case .number: .copy("Number")
            case .toggle: .copy("On/Off")
            case .list: .copy("List")
            }
        }
    }
    var kind: Kind
    var text = ""
    var flag = false
    var lines = ""
     
     
    var pendingItem = ""

    init(kind: Kind) { self.kind = kind }

     
    init?(_ value: OrderedJSON) {
        switch value {
         
         
        case .string(let text) where !text.contains(where: \.isNewline):
            kind = .text; self.text = text
        case .scalar(let token) where token == "true" || token == "false":
            kind = .toggle; flag = token == "true"
        case .scalar(let token) where Double(token) != nil:
            kind = .number; text = token
        case .array(let items):
            var strings: [String] = []
            for item in items {
                switch item {
                 
                 
                 
                case .string(let text) where !text.contains(where: \.isNewline): strings.append(text)
                case .scalar(let token) where token != "null": strings.append(token)
                default: return nil
                }
            }
            kind = .list; lines = strings.joined(separator: "\n")
        default:
            return nil
        }
    }

    var isValid: Bool {
        kind != .number || Double(text.trimmingCharacters(in: .whitespaces)) != nil
    }

     
    var items: [String] {
        get { lines.isEmpty ? [] : lines.components(separatedBy: "\n") }
        set { lines = newValue.joined(separator: "\n") }
    }

    var value: OrderedJSON {
        switch kind {
        case .text: return .string(text)
        case .number: return .scalar(text.trimmingCharacters(in: .whitespaces))
        case .toggle: return .scalar(flag ? "true" : "false")
        case .list:
            return .array(ClashMacFieldDraft.withPending(lines.split(whereSeparator: \.isNewline).map(String.init), pendingItem)
                .map(OrderedJSON.string))
        }
    }

     
    static func summary(_ value: OrderedJSON) -> String {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        case .array(let items): return String(items.count)
        case .object(let items): return String(items.count)
        }
    }
}

 
 
 
 
 
 
 
 
 
struct ClashMacSettingsSectionPage: View {
    let section: ConfigurationOutlineSection
     
     
    let basePath: [String]
     
    let knownKeys: [String]
    let actions: ClashMacSettingsSectionActions
     
     
    var readOnly = false
     
    var editSource: (@MainActor () -> Void)? = nil
    @State private var document: ClashMacSettingsSectionDocument?
     
    @State private var loadFailure: String?
     
     
     
    @State private var writeFailures: [[String]: String] = [:]
     
    @State private var dnsSwitchFailure: String?
     
     
     
     
     
     
    @State private var writes = ClashMacSectionWrites()
    @State private var editing: ClashMacKeyEdit?
    @State private var adding = false
     
     
    @State private var runsOver: ClashMacRunsOver?
     
     
    @State private var generalOverrides: ClashMacGeneralOverrides?
     
     
    @State private var following = false
    @State private var reads = 0
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy

    private var rows: [ClashMacSectionRow] {
        guard let document else { return [] }
        return document.rows(section: section, under: basePath, fallback: basePath.isEmpty ? knownKeys : [])
            .map { document.noted($0, by: runsOver) }
    }

     
     
    private var entryKind: ClashMacMapEntryKind? {
        guard !basePath.isEmpty, let document, let map = document.field(at: basePath), map.kind == .map else { return nil }
        return ClashMacMapEntryKind(map: map, entry: document.field(at: basePath + [""])) { document.control(for: $0) }
    }

    private var taken: Set<String> { Set(rows.map(\.key)) }

     
     
     
    private var laidOut: (blocks: [(title: ClashDisplayText?, rows: [ClashMacSectionRow], footer: String?)], platform: [ClashMacSectionRow]) {
        guard let document else { return ([], []) }
        if let layout = document.layout?(basePath) {
             
             
             
            var kept: [(title: ClashDisplayText?, rows: [ClashMacSectionRow], footer: String?)] = []
            var platform = layout.platformDecided.map { document.row(for: $0) }
            for group in layout.groups {
                let rows = group.rows.map { document.noted(document.row(for: $0), by: runsOver) }
                platform += rows.filter { $0.platformReason != nil }
                let shown = rows.filter { $0.platformReason == nil }
                if !shown.isEmpty { kept.append((group.title, shown, group.footer)) }
            }
            return (kept, platform)
        }
        let blocks = Self.blocks(rows, section: section, basePath: basePath) { row in
            document.rows(section: section, under: row.path, fallback: []).map { document.noted($0, by: runsOver) }
        }
        let split = Self.separatingPlatformKeys(blocks)
        return (split.blocks.map { ($0.title, $0.rows, nil) }, split.platform)
    }

     
     
     
    static func separatingPlatformKeys(_ blocks: [(title: ClashDisplayText?, rows: [ClashMacSectionRow])],
                                       platform: [ClashMacSectionRow] = [])
        -> (blocks: [(title: ClashDisplayText?, rows: [ClashMacSectionRow])], platform: [ClashMacSectionRow]) {
        var decided = platform
        var kept: [(title: ClashDisplayText?, rows: [ClashMacSectionRow])] = []
        for block in blocks {
            decided += block.rows.filter { $0.platformReason != nil }
            let rows = block.rows.filter { $0.platformReason == nil }
            if !rows.isEmpty { kept.append((block.title, rows)) }
        }
        return (kept, decided)
    }

    var body: some View {
        Form {
            let laidOut = laidOut
            let stray = strayFailures(laidOut.blocks.flatMap(\.rows))
            if let loadFailure {
                Section { Text(verbatim: loadFailure).foregroundStyle(.red) }
            }
             
             
            if entryKind == nil, !stray.isEmpty {
                Section { ForEach(stray, id: \.self) { ClashMacRowFailure(message: $0) } }
            }
             
             
            if section == .dns, basePath.isEmpty, let on = document?.ownDNSSwitch, actions.setOwnDNSSwitch != nil {
                Section {
                    Toggle(isOn: Binding(get: { writes.ownDNSPressed ?? on }, set: { perform(.ownDNS($0)) })) {
                        Text(clash: .copy("Use custom DNS"))
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("configuration-center.section.dns.custom")
                    if let dnsSwitchFailure { ClashMacRowFailure(message: dnsSwitchFailure) }
                }
            }
             
            if Self.showsLANShareRow(section: section, basePath: basePath), let lanShare = actions.lanShare {
                Section {
                    ClashRoutedViewLink(onReturn: { Task { @MainActor in await reload() } }) { lanShare.page() } label: {
                        LabeledContent {
                            Text(clash: lanShare.status(document?.running ?? .object([])))
                        } label: {
                            Text(clash: .copy("LAN Proxy Share"))
                        }
                    }
                    .accessibilityIdentifier("configuration-center.section.lan-share")
                }
            }
            if readOnly, let editSource {
                Section {
                    Button(action: editSource) { Text(clash: .copy("Edit Source…")) }
                        .accessibilityIdentifier("configuration-center.section.edit-source")
                } footer: {
                    Text(clash: .copy("Change this one in the source."))
                }
            }
            ForEach(Array(laidOut.blocks.enumerated()), id: \.offset) { _, block in
                 
                 
                 
                let off = offSummary(block.rows)
                Section {
                    ForEach(block.rows) { row in
                        if readOnly {
                            LabeledContent { Text(clash: row.summary(locale: locale, copy: copy)) } label: { ClashMacSectionKeyLabel(row: row) }
                        } else {
                            rowView(row)
                                .disabled(offSwitch(for: row) != nil)
                            if let reason = failure(under: row) { ClashMacRowFailure(message: reason) }
                        }
                    }
                    generalOverrideRows(block)
                } header: {
                    if let title = block.title { Text(clash: title) }
                } footer: {
                    ClashMacGroupFooter(words: block.footer, off: off)
                }
            }
             
             
            if !laidOut.platform.isEmpty {
                Section {
                    ClashRoutedViewLink {
                        ClashMacPlatformDecidedPage(rows: laidOut.platform)
                    } label: {
                        Text(clash: ConfigurationValueWords.notApplyingRow(count: laidOut.platform.count,
                                                                          device: ClashMacValueWords.device, locale: locale))
                    }
                    .accessibilityIdentifier("configuration-center.section.platform-decided")
                }
            }
             
             
             
             
             
            if !readOnly, let entry = entryKind {
                Section {
                    Button { adding = true } label: { Text(clash: .copy("Add…")) }
                        .disabled(document == nil || writes.busy || entry.choices.map { $0.allSatisfy(taken.contains) } == true)
                        .accessibilityIdentifier("configuration-center.section.key.add")
                     
                    ForEach(stray, id: \.self) { ClashMacRowFailure(message: $0) }
                }
            }
             
             
             
            if !readOnly, let scope = document?.scope {
                Section {} footer: { Text(clash: scope) }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .task(id: reads) {
            guard reads > 0 else { return }
            if let read = actions.runsOver { runsOver = await read() }
            if let read = actions.generalOverrides { generalOverrides = await read() }
        }
         
         
         
         
         
         
         
         
        .onReceive(actions.generalOverridesChanged ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in
            Task { if let read = actions.generalOverrides { generalOverrides = await read() } }
        }
        .sheet(item: $editing) { edit in
            ClashMacValueEditSheet(edit: edit, save: { value in
                request([.set(path: edit.path, to: value)])
            }, useDefault: edit.removable ? { request([.remove(path: edit.path)]) } : nil, geoValues: actions.geoValues,
               turnOff: edit.value != nil && actions.turnOff != nil ? { turnOff(edit.path) } : nil)
        }
        .sheet(isPresented: $adding) {
            if let entry = entryKind {
                ClashMacNewEntrySheet(
                    entry: entry, taken: taken,
                    policyKeys: ConfigurationPolicyKey.isPolicyMap(basePath),
                    ruleSets: document.map { ConfigurationReferenceNames.names([.ruleProvider], in: $0.running) } ?? [],
                    geoValues: actions.geoValues
                ) { key, value in
                    request([.set(path: basePath + [key], to: value)])
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: ClashMacSectionRow) -> some View {
        let path = row.path
        let control = row.control ?? Self.shapeControl(row.value)
        HStack(spacing: ClashTheme.Spacing.compact) {
        Group {
            if let owner = row.owner {
                ownedRow(row, owner: owner)
            } else if row.drillsIn {
                 
                 
                ClashRoutedViewLink(onReturn: { Task { @MainActor in await reload() } }) {
                    if row.field?.kind == .objectList {
                        ClashMacObjectListPage(section: section, listPath: path, actions: actions)
                            .navigationTitle(Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale)))
                    } else {
                        ClashMacSettingsSectionPage(section: section, basePath: path, knownKeys: [], actions: actions)
                            .navigationTitle(Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale)))
                    }
                } label: {
                    LabeledContent { Text(clash: row.summary(locale: locale, copy: copy)) } label: { ClashMacSectionKeyLabel(row: row) }
                }
            } else if row.platformReason != nil {
                 
                EmptyView()
            } else if actions.geoValues != nil, ConfigurationFieldExamples.knownSet(for: row.field) != nil {
                 
                 
                 
                 
                LabeledContent {
                    Button { open(row, path: path) } label: { Text(clash: row.summary(locale: locale, copy: copy)) }
                        .accessibilityIdentifier("configuration-center.section.row.known")
                } label: {
                    ClashMacSectionKeyLabel(row: row)
                }
            } else if case .toggle? = control {
                Toggle(isOn: Binding(get: { Self.isOn(row) }, set: { request([.set(path: path, to: .scalar($0 ? "true" : "false"))]) })) {
                    ClashMacSectionKeyLabel(row: row)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("configuration-center.section.row.toggle")
            } else if case .choose(let options, _)? = control {
                choiceRow(row, path: path, control: control ?? .choose(options, caseInsensitive: false))
            } else if let field = row.field, ClashMacAddressMenuRow<EmptyView>.applies(to: field, control: control) {
                 
                 
                 
                ClashMacAddressMenuRow(path: field.path, value: row.value,
                                      offersOff: row.removable || (row.value != nil && actions.turnOff != nil),
                                      identifier: "configuration-center.section.row.address",
                                      write: { value in
                                          if let value { request([.set(path: path, to: value)]) } else { turnOff(path) }
                                      },
                                      custom: { open(row, path: path) }) {
                    ClashMacSectionKeyLabel(row: row)
                }
            } else if let field = row.field, let unit = ClashMacTimeMenuRow<EmptyView>.unit(of: control, field: field) {
                 
                 
                timeRow(row, field: field, path: path, unit: unit)
            } else if let control, Self.typesInline(control, value: row.value) {
                ClashMacInlineValueRow(row: row, control: control) { value in
                    request([value.map { .set(path: path, to: $0) } ?? .remove(path: path)])
                }
            } else {
                 
                LabeledContent {
                    Button { open(row, path: path) } label: { Text(clash: row.summary(locale: locale, copy: copy)) }
                        .accessibilityIdentifier("configuration-center.section.row.edit")
                } label: {
                    ClashMacSectionKeyLabel(row: row)
                }
            }
        }
         
         
        if row.removable { useDefaultInline(row, path: path) }
        }
        .contextMenu { useDefaultButton(row, path: path) }
        .accessibilityIdentifier("configuration-center.section.key.\(row.key)")
    }

     
     
    private func useDefaultInline(_ row: ClashMacSectionRow, path: [String]) -> some View {
        Button { request([.remove(path: path)]) } label: {
            ClashSymbolImage(symbol: .arrowUturnBackward)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(Text(clash: .copy("Use Default")))
        .accessibilityLabel(Text(clash: .copy("Use Default")))
        .accessibilityIdentifier("configuration-center.section.key.use-default.inline")
    }

     
     
     
     
    static let generalGroups: [(title: ClashDisplayText, keys: Set<String>)] = [
        (.copy("Outbound"), ["mode"]),
        (.copy("Log"), ["log-level"]),
        (.copy("Connection"), ["ipv6", "unified-delay", "tcp-concurrent", "keep-alive-interval", "keep-alive-idle", "disable-keep-alive"]),
        (.copy("Share on the Local Network"), ["allow-lan", "bind-address", "port", "socks-port", "mixed-port", "redir-port",
                                               "tproxy-port", "authentication", "skip-auth-prefixes", "lan-allowed-ips",
                                               "lan-disallowed-ips", "inbound-tfo", "inbound-mptcp"]),
        (.copy("Process Lookup"), ["find-process-mode"]),
    ]

    static func groups(_ rows: [ClashMacSectionRow], section: ConfigurationOutlineSection,
                       basePath: [String]) -> [(title: ClashDisplayText?, rows: [ClashMacSectionRow])] {
        guard section == .general, basePath.isEmpty else { return rows.isEmpty ? [] : [(nil, rows)] }
        var groups: [(title: ClashDisplayText?, rows: [ClashMacSectionRow])] = []
        var placed = Set<String>()
        for group in generalGroups {
            let members = rows.filter { group.keys.contains($0.key) }
            placed.formUnion(members.map(\.key))
            if !members.isEmpty { groups.append((group.title, members)) }
        }
        let rest = rows.filter { !placed.contains($0.key) }
        if !rest.isEmpty { groups.append((groups.isEmpty ? nil : .copy("Other Fields"), rest)) }
        return groups
    }

     
     
    static func blocks(_ rows: [ClashMacSectionRow], section: ConfigurationOutlineSection, basePath: [String],
                       children: (ClashMacSectionRow) -> [ClashMacSectionRow]) -> [(title: ClashDisplayText?, rows: [ClashMacSectionRow])] {
        let expands: (ClashMacSectionRow) -> Bool = { $0.owner == nil && $0.expandsInPlace }
        var cards = groups(rows.filter { !expands($0) }, section: section, basePath: basePath)
        func expand(_ row: ClashMacSectionRow, title: String) {
            let inner = children(row)
            let plain = inner.filter { !expands($0) }
            if !plain.isEmpty { cards.append((.verbatim(title), plain)) }
            for object in inner where expands(object) { expand(object, title: title + " · " + object.key) }
        }
        for row in rows where expands(row) { expand(row, title: row.key) }
        return cards
    }

     
    private static func shapeControl(_ value: OrderedJSON?) -> ClashMacFieldControl? {
        if case .scalar(let token)? = value, token == "true" || token == "false" { return .toggle }
        if let value, let draft = ClashMacValueDraft(value) {
            switch draft.kind {
            case .text: return .text(format: nil, suggestions: [])
            case .number: return .number(min: nil, max: nil, unit: nil)
            case .toggle: return .toggle
            case .list: return .lines(format: nil)
            }
        }
        return nil
    }

     
     
     
    static func typesInline(_ control: ClashMacFieldControl, value: OrderedJSON?) -> Bool {
        switch control {
        case .text(.ipPort?, _), .text(.password?, _), .text(.uuid?, _):
            return false
        case .text, .number:
            if case .string(let text)? = value, text.contains(where: \.isNewline) { return false }
            return true
        default:
            return false
        }
    }

     
    private func timeRow(_ row: ClashMacSectionRow, field: ConfigurationField, path: [String], unit: String) -> some View {
        ClashMacTimeMenuRow(field: field, unit: unit,
                           value: row.value, offersDefault: row.removable, defaultLine: defaultLine(row),
                           identifier: "configuration-center.section.row.time",
                           write: { value in request([value.map { .set(path: path, to: $0) } ?? .remove(path: path)]) },
                           custom: { open(row, path: path) }) {
            ClashMacSectionKeyLabel(row: row)
        }
    }

     
     
    private func offSummary(_ rows: [ClashMacSectionRow]) -> ConfigurationOffSwitchSummary? {
        guard let document, let catalog = document.catalog else { return nil }
        let governed = rows.compactMap { row in row.field.map { (field: $0, steps: row.path.map(ConfigurationDocumentStep.key)) } }
        return catalog.offSwitchSummary(over: governed, in: document.running)
    }

     
     
    private func offSwitch(for row: ClashMacSectionRow) -> ConfigurationGoverningSwitch? {
        guard let document, let catalog = document.catalog, let field = row.field else { return nil }
        return catalog.offSwitch(for: field, at: row.path.map(ConfigurationDocumentStep.key), in: document.running)
    }

     
     
    static func showsLANShareRow(section: ConfigurationOutlineSection, basePath: [String]) -> Bool {
        section == .inbound && basePath.isEmpty
    }

    private static func isOn(_ row: ClashMacSectionRow) -> Bool {
        row.value.flatMap(token).map { $0 == "true" } ?? (row.field?.defaultFlag ?? false)
    }

     
     
     
    private func choiceRow(_ row: ClashMacSectionRow, path: [String], control: ClashMacFieldControl) -> some View {
        let draft = ClashMacFieldDraft(control: control, value: row.value)
        let selection = Binding<String?>(
            get: { row.value == nil ? nil : draft.text },
            set: { chosen in request([chosen.map { .set(path: path, to: .string($0)) } ?? .remove(path: path)]) }
        )
        return Picker(selection: selection) {
            Text(clash: defaultLine(row)).tag(String?.none)
            ForEach(draft.options, id: \.self) { option in
                Text(verbatim: copy.valueLabel(option, for: row.field, locale: locale) ?? option).tag(String?.some(option))
            }
        } label: {
            ClashMacSectionKeyLabel(row: row)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("configuration-center.section.row.choice")
    }

     
     
    private func defaultLine(_ row: ClashMacSectionRow) -> ClashDisplayText {
        ClashMacValueWords.defaultLine(row.field, locale: locale, copy: copy)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private func generalOverrideRows(_ block: (title: ClashDisplayText?, rows: [ClashMacSectionRow], footer: String?)) -> some View {
        if section == .general, basePath.isEmpty, let overrides = generalOverrides {
            if let note = overrides.outboundMode, block.rows.contains(where: { $0.key == "mode" }) {
                Text(clash: note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.section.general.runs-over.mode")
                if let follow = overrides.followConfiguration, !readOnly {
                    Button {
                         
                         
                         
                         
                         
                        guard !following else { return }
                        following = true
                        Task {
                            defer { following = false }
                            await follow()
                            if let read = actions.generalOverrides { generalOverrides = await read() }
                            await reload()
                        }
                    } label: {
                        Text(clash: ClashGeneralOverrideNote.followConfiguration)
                    }
                    .disabled(writes.busy || following)
                    .accessibilityIdentifier("configuration-center.section.general.follow-configuration")
                }
            } else if let note = overrides.logLevel, block.rows.contains(where: { $0.key == "log-level" }) {
                 
                 
                 
                 
                Text(clash: note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configuration-center.section.general.runs-over.log-level")
            }
        }
    }

     
    @ViewBuilder
    private func ownedRow(_ row: ClashMacSectionRow, owner: ClashMacKeyOwner) -> some View {
        let title = Text(clash: .format("Change in %@", [ClashCopy.string(for: owner.title, locale: locale)]))
        if let push = owner.push {
            ClashRoutedViewLink(onReturn: { Task { @MainActor in await reload() } }) { push() } label: {
                LabeledContent { Text(clash: row.summary(locale: locale, copy: copy)) } label: {
                    Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale))
                    title
                }
            }
            .accessibilityIdentifier("configuration-center.section.row.owner")
        } else {
            LabeledContent {
                if let open = owner.open {
                    Button(action: open) { title }
                        .accessibilityIdentifier("configuration-center.section.row.owner")
                } else {
                    Text(clash: row.summary(locale: locale, copy: copy))
                }
            } label: {
                Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale))
                if owner.open == nil { title }
            }
        }
    }

    private func open(_ row: ClashMacSectionRow, path: [String]) {
        editing = ClashMacKeyEdit(path: path, value: row.value,
                                 platformReason: row.platformReason,
                                 choices: document?.choices[path.joined(separator: ".")],
                                 control: row.control, removable: row.removable, isDefault: row.usesDefault,
                                 field: row.field)
    }

     
     
     
    @ViewBuilder
    private func useDefaultButton(_ row: ClashMacSectionRow, path: [String]) -> some View {
        if row.removable {
            Button { request([.remove(path: path)]) } label: { Text(clash: .copy("Use Default")) }
                .accessibilityIdentifier("configuration-center.section.key.use-default")
        }
    }

    private static func token(_ value: OrderedJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return nil
        }
    }

     
     
     
     
     
    private func request(_ edits: [ConfigurationPageEdit]) {
        guard !edits.isEmpty else { return }
        perform(.edits(edits))
    }

     
     
     
     
    private func turnOff(_ path: [String]) {
        guard actions.turnOff != nil else { return request([.remove(path: path)]) }
        perform(.turnOff(path))
    }

     
     
    private func perform(_ step: ClashMacSectionWrites.Step) {
        let now = writes.take(step)
        document?.shownEdits = writes.shownEdits
        guard let now else { return }
        Task { await write(from: now) }
    }

    private func write(from first: ClashMacSectionWrites.Step) async {
        var step: ClashMacSectionWrites.Step? = first
        while let current = step {
            await run(current)
            await reload()
            step = writes.finish()
             
             
            document?.shownEdits = writes.shownEdits
        }
    }

     
    private func run(_ step: ClashMacSectionWrites.Step) async {
        switch step {
        case .edits(let edits):
            await save(edits)
        case .ownDNS(let on):
            guard let setSwitch = actions.setOwnDNSSwitch else { return }
            do { try await setSwitch(on); dnsSwitchFailure = nil } catch { dnsSwitchFailure = ClashErrorCopy.message(error, locale: locale) }
        case .turnOff(let path):
            guard let off = actions.turnOff else { return }
            do {
                switch try await off(path) {
                case .edits(let edits):
                    await save(edits)
                case .written: clearFailures(at: [path])
                case .nothing: break
                }
            } catch is CancellationError {
            } catch {
                writeFailures[path] = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }

    private func save(_ edits: [ConfigurationPageEdit]) async {
        let paths = edits.map(\.writtenPath)
        do {
            try await actions.save(edits, document?.scheme)
            clearFailures(at: paths)
        } catch is CancellationError {
        } catch {
            for path in paths { writeFailures[path] = ClashErrorCopy.message(error, locale: locale) }
        }
    }

     
    private func clearFailures(at paths: [[String]]) {
        writeFailures = writeFailures.filter { failed, _ in !paths.contains { failed.starts(with: $0) } }
    }

     
    private func failure(under row: ClashMacSectionRow) -> String? {
        writeFailures.first { $0.key.starts(with: row.path) }?.value
    }

     
     
    private func strayFailures(_ rows: [ClashMacSectionRow]) -> [String] {
        var said = Set<String>()
        return writeFailures
            .filter { failed, _ in !rows.contains { failed.starts(with: $0.path) } }
            .sorted { $0.key.joined(separator: ".") < $1.key.joined(separator: ".") }
            .map(\.value)
            .filter { said.insert($0).inserted }
    }

    private func reload() async {
        do {
            var read = try await actions.load(section)
             
             
            read.shownEdits = writes.shownEdits
            document = read
            loadFailure = nil
            reads += 1
        } catch is CancellationError {
        } catch {
            loadFailure = ClashErrorCopy.message(error, locale: locale)
        }
    }
}

 
 
 
 
 
 
struct ClashMacObjectListPage: View {
    let section: ConfigurationOutlineSection
    let listPath: [String]
    let actions: ClashMacSettingsSectionActions
     
     
    var only: Int? = nil
    @State private var document: ClashMacSettingsSectionDocument?
     
    @State private var loadFailure: String?
     
     
     
    @State private var writeFailures: [WritePlace: String] = [:]
     
     
     
     
     
    @State private var writes = ClashMacSectionWrites()
     
    @State private var runningPlaces: [WritePlace] = []
    @State private var waitingPlaces: [WritePlace] = []
     
    @State private var runsOver: ClashMacRunsOver?
    @State private var reads = 0
    @State private var adding = false
    @State private var editing: ClashMacListItemEdit?
    @Environment(\.locale) private var locale
    @Environment(\.configurationFieldCopy) private var copy

     
     
    enum WritePlace: Hashable {
        case field(index: Int, key: String)
        case item(Int)
        case add
    }

    private var items: [OrderedJSON] { document?.items(at: listPath) ?? [] }

    var body: some View {
         
        let typeNames = ClashMacValueWords.valueNames(path: listPath.joined(separator: ".") + "[*].type", copy: copy, locale: locale)
        return Form {
            if let loadFailure {
                Section { Text(verbatim: loadFailure).foregroundStyle(.red) }
            }
            if document != nil, items.isEmpty, only == nil {
                 
                Section {
                    Text(clash: Self.emptySentence(listPath)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("configuration-center.section.item.empty")
                }
            }
            ForEach(Array(items.enumerated()).filter { only == nil || $0.offset == only }, id: \.offset) { index, item in
                let rows = fields(at: index, item: item)
                 
                 
                let off = offSummary(rows, in: item)
                Section {
                     
                    if let reason = writeFailures[.item(index)] { ClashMacRowFailure(message: reason) }
                    ForEach(rows, id: \.key) { entry in
                        itemRow(index: index, item: item, key: entry.key, field: entry.field)
                            .disabled(offSwitch(key: entry.key, field: entry.field, in: item) != nil)
                        if let reason = writeFailures[.field(index: index, key: entry.key)] { ClashMacRowFailure(message: reason) }
                    }
                } header: {
                    HStack {
                        Text(verbatim: Self.title(of: item, at: index, typeNames: typeNames))
                        Spacer()
                        Menu {
                            Button(role: .destructive) { remove(index) } label: { Text(clash: .copy("Delete")) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityIdentifier("configuration-center.section.item.menu")
                    }
                } footer: {
                    ClashMacGroupFooter(words: nil, off: off)
                }
            }
            if only == nil {
                Section {
                     
                     
                    Button { adding = true } label: { Text(clash: .copy("Add…")) }
                        .disabled(document?.catalog == nil || writes.busy)
                        .accessibilityIdentifier("configuration-center.section.item.add")
                    if let reason = writeFailures[.add] { ClashMacRowFailure(message: reason) }
                } footer: {
                    if let footer = Self.listFooter(listPath) { Text(clash: footer) }
                     
                     
                    if let document, let note = runsOver?(listPath, nil, false, document.running) {
                        Text(clash: note).accessibilityIdentifier("configuration-center.section.item.runs-over")
                    }
                }
            }
             
             
             
            if let scope = document?.scope, only.map(items.indices.contains) ?? true {
                Section {} footer: { Text(clash: scope) }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .task(id: reads) { if reads > 0, let read = actions.runsOver { runsOver = await read() } }
        .sheet(isPresented: $adding) {
             
            if let document, let catalog = document.catalog,
               let list = catalog.catalogPath(of: listPath.map(ConfigurationDocumentStep.key), in: document.running) {
                ClashMacNewItemSheet(
                    list: list,
                    types: ClashMacNewItemSheet.types(ofList: list, catalog: catalog),
                    taken: Set(items.compactMap(Self.name)),
                    form: { type in ConfigurationNewItem.make(listPath: list, type: type, in: document.running, catalog: catalog) }
                ) { item in
                    write(items + [item], at: .add)
                }
            }
        }
        .sheet(item: $editing) { edit in
            ClashMacValueEditSheet(edit: edit.edit, save: { value in
                set(edit.key, to: value, at: edit.index)
            }, useDefault: edit.edit.removable ? { set(edit.key, to: nil, at: edit.index) } : nil, geoValues: actions.geoValues)
        }
    }

     
     
    private func offSummary(_ rows: [(key: String, field: ConfigurationField?)], in item: OrderedJSON) -> ConfigurationOffSwitchSummary? {
        guard let catalog = document?.catalog else { return nil }
        return catalog.offSwitchSummary(over: rows.compactMap { row in row.field.map { (field: $0, steps: [ConfigurationDocumentStep.key(row.key)]) } },
                                        in: item)
    }

     
    private func offSwitch(key: String, field: ConfigurationField?, in item: OrderedJSON) -> ConfigurationGoverningSwitch? {
        guard let field, let catalog = document?.catalog else { return nil }
        return catalog.offSwitch(for: field, at: [.key(key)], in: item)
    }

    static func name(_ item: OrderedJSON) -> String? {
        if case .string(let name)? = item.topLevelValue("name") { return name }
        return nil
    }

     
     
    static func emptySentence(_ listPath: [String]) -> ClashDisplayText {
        switch listPath.joined(separator: ".") {
        case "listeners": .copy("No listeners yet. A listener opens a port that other apps or devices connect through.")
        case "tunnels": .copy("No tunnels yet. A tunnel forwards a port on this device to an address, through a proxy.")
        default: .copy("Nothing added yet.")
        }
    }

     
     
     
    static func listFooter(_ listPath: [String]) -> ClashDisplayText? {
        guard listPath == ["listeners"] else { return nil }
        return .copy("Extra ports, each with its own protocol, account and route. The proxy ports this device and the LAN use by default are in LAN Proxy Share.")
    }

     
     
    static func title(of item: OrderedJSON, at index: Int, typeNames: [String: String] = [:]) -> String {
        let type: String? = { if case .string(let type)? = item.topLevelValue("type") { return typeNames[type.lowercased()] ?? type }; return nil }()
        switch (name(item), type) {
        case (let name?, let type?): return name + " · " + type
        case (let name?, nil): return name
        case (nil, let type?): return type
        case (nil, nil): return "#\(index + 1)"
        }
    }

     
     
    private func fields(at index: Int, item: OrderedJSON) -> [(key: String, field: ConfigurationField?)] {
        var rows: [(key: String, field: ConfigurationField?)] = (document?.itemFields(of: listPath, at: index) ?? []).map {
            (($0.path.split(separator: ".").last.map(String.init) ?? $0.path), Optional($0))
        }
        var seen = Set(rows.map(\.key))
        if case .object(let entries) = item {
            for entry in entries where seen.insert(entry.key).inserted { rows.append((entry.key, nil)) }
        }
        return rows
    }

    @ViewBuilder
    private func itemRow(index: Int, item: OrderedJSON, key: String, field: ConfigurationField?) -> some View {
        let value = item.topLevelValue(key)
        let control = field.flatMap { field in
            ClashMacFieldControl.make(field, value: value) { reference in
                document.map { ConfigurationReferenceNames.names(reference, in: $0.running) } ?? []
            }
        }
        switch control {
        case .toggle?:
            Toggle(isOn: Binding(
                get: { value.flatMap(Self.token).map { $0 == "true" } ?? (field?.defaultFlag ?? false) },
                set: { set(key, to: .scalar($0 ? "true" : "false"), at: index) }
            )) { Text(verbatim: copy.title(for: field, key: key, locale: locale)) }
            .toggleStyle(.switch)
            .accessibilityIdentifier("configuration-center.section.item.toggle")
        case .number(_, _, let unit?, _)? where field != nil && ClashMacTimeMenuRow<EmptyView>.unit(of: control, field: field) != nil:
             
            if let field {
                ClashMacTimeMenuRow(field: field, unit: unit, value: value, offersDefault: true,
                                   defaultLine: ClashMacValueWords.defaultLine(field, locale: locale, copy: copy),
                                   identifier: "configuration-center.section.item.time",
                                   write: { set(key, to: $0, at: index) },
                                   custom: { openSheet(index: index, key: key, value: value, control: control, field: field) }) {
                    keyLabel(key, value: value, field: field)
                }
            }
        case .choose(let options, let caseInsensitive)?:
            let draft = ClashMacFieldDraft(control: .choose(options, caseInsensitive: caseInsensitive), value: value)
            Picker(selection: Binding<String?>(
                get: { value == nil ? nil : draft.text },
                set: { chosen in set(key, to: chosen.map(OrderedJSON.string), at: index) }
            )) {
                Text(clash: ClashMacValueWords.defaultLine(field, locale: locale, copy: copy)).tag(String?.none)
                ForEach(draft.options, id: \.self) {
                    Text(verbatim: copy.valueLabel($0, for: field, locale: locale) ?? $0).tag(String?.some($0))
                }
            } label: { keyLabel(key, value: value, field: field) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-center.section.item.choice")
        default:
            LabeledContent {
                Button {
                    openSheet(index: index, key: key, value: value, control: control, field: field)
                } label: {
                    Text(clash: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy))
                }
                .accessibilityIdentifier("configuration-center.section.item.edit")
            } label: {
                keyLabel(key, value: value, field: field)
            }
        }
    }

    private static func token(_ value: OrderedJSON) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token
        default: return nil
        }
    }

     
    private func openSheet(index: Int, key: String, value: OrderedJSON?, control: ClashMacFieldControl?, field: ConfigurationField?) {
        editing = ClashMacListItemEdit(index: index, key: key, edit: ClashMacKeyEdit(
            path: listPath + [key], value: value, platformReason: nil,
            choices: nil, control: control, removable: value != nil, isDefault: value == nil, field: field
        ))
    }

     
    @ViewBuilder
    private func keyLabel(_ key: String, value: OrderedJSON?, field: ConfigurationField?) -> some View {
        Text(verbatim: copy.title(for: field, key: key, locale: locale))
        if let why = ClashMacSectionKeyLabel.unavailableWords(value, field: field, copy: copy, locale: locale) {
            Text(verbatim: why).foregroundStyle(.orange)
        }
    }

    private func set(_ key: String, to value: OrderedJSON?, at index: Int) {
        var next = items
        guard next.indices.contains(index) else { return }
        next[index] = value.map { next[index].settingTopLevel(key, to: $0) } ?? next[index].removingTopLevel(key)
        write(next, at: .field(index: index, key: key))
    }

    private func remove(_ index: Int) {
        var next = items
        guard next.indices.contains(index) else { return }
        next.remove(at: index)
        write(next, at: .item(index))
    }

     
     
    private func write(_ next: [OrderedJSON], at place: WritePlace) {
        request([next.isEmpty && document?.removes(listPath) == true ? .remove(path: listPath) : .set(path: listPath, to: .array(next))],
                at: place)
    }

     
    private func request(_ edits: [ConfigurationPageEdit], at place: WritePlace) {
        guard !edits.isEmpty else { return }
        perform(edits, at: place)
    }

     
    private func perform(_ edits: [ConfigurationPageEdit], at place: WritePlace) {
        let now = writes.take(.edits(edits))
        document?.shownEdits = writes.shownEdits
        guard let now else {
            waitingPlaces.append(place)
            return
        }
        runningPlaces = [place]
        Task { await write(from: now) }
    }

    private func write(from first: ClashMacSectionWrites.Step) async {
        var step: ClashMacSectionWrites.Step? = first
        while case .edits(let edits)? = step {
            await save(edits, at: runningPlaces)
            await reload()
             
             
            step = writes.finish()
            runningPlaces = waitingPlaces
            waitingPlaces = []
            document?.shownEdits = writes.shownEdits
        }
    }

    private func save(_ edits: [ConfigurationPageEdit], at places: [WritePlace]) async {
        do {
            try await actions.save(edits, document?.scheme)
             
             
            if places.contains(where: { if case .item = $0 { return true }; return false }) {
                writeFailures = [:]
            } else {
                for place in places { writeFailures[place] = nil }
            }
        } catch is CancellationError {
        } catch {
            let message = ClashErrorCopy.message(error, locale: locale)
            for place in places { writeFailures[place] = message }
        }
    }

    private func reload() async {
        do {
            var read = try await actions.load(section)
            read.shownEdits = writes.shownEdits
            document = read
            loadFailure = nil
            reads += 1
        } catch is CancellationError {
        } catch {
            loadFailure = ClashErrorCopy.message(error, locale: locale)
        }
    }
}

 
struct ClashMacListItemEdit: Identifiable {
    let index: Int
    let key: String
    let edit: ClashMacKeyEdit
    var id: String { "\(index).\(key)" }
}

 
 
 
 
 
 
 
 
 
struct ClashMacNewItemSheet: View {
     
    let list: String
    let types: [String]
    let taken: Set<String>
     
    let form: (String?) -> ConfigurationNewItem
     
     
     
    var requiresAValue = false
    let save: (OrderedJSON) -> Void
    @State private var type = ""
    @State private var values: [String: ConfigurationNewItem.Value] = [:]
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    private var model: ConfigurationNewItem { form(types.isEmpty ? nil : type) }

     
     
     
    static func typeLabel(_ type: String, list: String, copy: ConfigurationFieldCopy, locale: Locale) -> String {
        copy.entry(forPath: list + "[*].type", language: ConfigurationFieldCopy.Language(locale: locale))?
            .presets.first { $0.value == type }?.label ?? type
    }

     
     
     
    static func types(ofList list: String, catalog: ConfigurationFieldCatalog) -> [String] {
         
        ConfigurationNewItem.types(ofList: list, catalog: catalog)
    }

     
     
    static func canAdd(_ model: ConfigurationNewItem, values: [String: ConfigurationNewItem.Value], typeChosen: Bool,
                       taken: Set<String>, requiresAValue: Bool = false) -> Bool {
        guard typeChosen, model.isComplete(values), !hasProblem(model.asked, values: values) else { return false }
         
         
        if requiresAValue, !values.contains(where: { key, value in value != model.asked.first { $0.key == key }?.initialValue }) {
            return false
        }
        guard model.asked.contains(where: { $0.key == "name" }), case .text(let name)? = values["name"] else { return true }
        return !taken.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

     
     
    static func hasProblem(_ asked: [ConfigurationNewItem.Asked], values: [String: ConfigurationNewItem.Value]) -> Bool {
        asked.contains { asked in
            switch values[asked.key] ?? asked.initialValue {
            case .text(let text): return ConfigurationFieldValidation.problem(text, field: asked.field) != nil
            case .group(let inner): return hasProblem(asked.children, values: inner)
            default: return false
            }
        }
    }

    var body: some View {
        ClashMacSheetFrame(title: .copy("Add"), width: 500, height: 480) {
            ClashMacSheetForm {
                if !types.isEmpty {
                    Section {
                        Picker(selection: $type) {
                            ForEach(types, id: \.self) { Text(verbatim: Self.typeLabel($0, list: list, copy: copy, locale: locale)).tag($0) }
                        } label: { Text(clash: .copy("Type")) }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("configuration-center.section.new-item.type")
                    }
                }
                ForEach(model.asked) { asked in
                    ClashMacNewItemField(asked: asked, value: binding(asked))
                }
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.section.new-item.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.section.new-item.add",
                primaryDisabled: !Self.canAdd(model, values: values, typeChosen: types.isEmpty || !type.isEmpty, taken: taken,
                                              requiresAValue: requiresAValue),
                onClose: { dismiss() },
                onPrimary: {
                    save(model.item(values))
                    dismiss()
                }
            )
        }
        .clashCapturesDismiss(dismiss)
        .onAppear {
            if type.isEmpty, let first = types.first { type = first }
            values = model.initialValues
        }
         
        .onChange(of: type) { _ in values = model.initialValues }
    }

    private func binding(_ asked: ConfigurationNewItem.Asked) -> Binding<ConfigurationNewItem.Value> {
        Binding(get: { values[asked.key] ?? asked.initialValue }, set: { values[asked.key] = $0 })
    }
}

 
 
 
struct ClashMacNewItemField: View {
    let asked: ConfigurationNewItem.Asked
    @Binding var value: ConfigurationNewItem.Value
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

     
    private var title: String { copy.title(for: asked.field, key: asked.key, locale: locale) }
     
    @State private var pendingLine = ""
     
    @State private var entries: [String]?

    var body: some View {
        switch asked.control {
        case .group:
            groupRows
        case .choices, .lines, .pair:
            Section { rows } header: { Text(verbatim: title) }
        default:
            Section { rows }
        }
    }

     
    private func entryProblem(_ item: String) -> ConfigurationFieldProblem? {
        ClashMacFieldDraft.itemProblem(item, format: asked.field.format, path: asked.field.path, allowed: asked.field.values ?? [])
    }

     
     
    private var placeholder: String? {
        ClashMacValueWords.placeholder(asked.field, locale: locale, copy: copy) ?? ConfigurationFieldExamples.example(for: asked.field.format)
    }


    @ViewBuilder
    private var rows: some View {
        switch (asked.control, value) {
        case (.text, .text(let text)), (.number, .text(let text)):
            TextField(text: Binding(get: { text }, set: { value = .text($0) }), prompt: placeholder.map { Text(verbatim: $0) }) {
                Text(verbatim: title)
                if case .number = asked.control, let range = ClashMacFieldDraft.range(min: asked.field.min, max: asked.field.max) {
                    Text(clash: range)
                }
            }
            .disableAutocorrection(true)
            .accessibilityIdentifier("configuration-center.section.new-item.text")
            if let problem = ConfigurationFieldValidation.problem(text, field: asked.field) {
                ClashMacProblemLine(problem: problem)
            }
        case (.choice(let options), .choice(let chosen)):
            Picker(selection: Binding(get: { chosen }, set: { value = .choice($0) })) {
                Text(clash: .copy("Choose…")).tag("")
                ForEach(options, id: \.self) { Text(verbatim: copy.valueLabel($0, for: asked.field, locale: locale) ?? $0).tag($0) }
            } label: { Text(verbatim: title) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-center.section.new-item.choice")
        case (.choices(let options), .choices(let chosen)):
            ForEach(options, id: \.self) { option in
                Toggle(isOn: Binding(get: { chosen.contains(option) }, set: { on in
                    value = .choices(on ? chosen + [option] : chosen.filter { $0 != option })
                })) { Text(verbatim: copy.valueLabel(option, for: asked.field, locale: locale) ?? option) }
                .accessibilityIdentifier("configuration-center.section.new-item.option")
            }
        case (.flag, .flag(let on)):
            Toggle(isOn: Binding(get: { on }, set: { value = .flag($0) })) { Text(verbatim: title) }
                .toggleStyle(.switch)
                .accessibilityIdentifier("configuration-center.section.new-item.flag")
        case (.lines, .lines(let lines)):
             
             
            ClashMacListValueEditor(
                items: Binding(get: { entries ?? lines.filter { !$0.isEmpty } },
                               set: { added in
                                   entries = added
                                   value = .lines(ClashMacFieldDraft.withPending(added, pendingLine, problem: entryProblem))
                               }),
                format: asked.field.format,
                field: asked.field,
                pending: Binding(get: { pendingLine }, set: { typed in
                     
                     
                    let kept = entries ?? lines.filter { !$0.isEmpty }
                    entries = kept
                    pendingLine = typed
                    value = .lines(ClashMacFieldDraft.withPending(kept, typed, problem: entryProblem))
                })
            )
            .accessibilityIdentifier("configuration-center.section.new-item.lines")
        case (.pair, .pair(let key, let entry)):
            TextField(text: Binding(get: { key }, set: { value = .pair(key: $0, value: entry) })) { Text(clash: .copy("Name")) }
                .disableAutocorrection(true)
                .accessibilityIdentifier("configuration-center.section.new-item.pair-key")
            TextField(text: Binding(get: { entry }, set: { value = .pair(key: key, value: $0) })) { Text(clash: .copy("Value")) }
                .disableAutocorrection(true)
                .accessibilityIdentifier("configuration-center.section.new-item.pair-value")
        default:
            EmptyView()
        }
    }

     
     
    private var groupRows: some View {
        ForEach(asked.children) { child in
            AnyView(ClashMacNewItemField(asked: child, value: Binding(
                get: {
                    if case .group(let values) = value { return values[child.key] ?? child.initialValue }
                    return child.initialValue
                },
                set: { new in
                    guard case .group(var values) = value else { return }
                    values[child.key] = new
                    value = .group(values)
                }
            )))
        }
    }
}

 
 
 
 
 
struct ClashMacPlatformDecidedPage: View {
    let rows: [ClashMacSectionRow]
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    LabeledContent {
                        EmptyView()
                    } label: {
                        Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale))
                        Text(clash: ConfigurationValueWords.categoryLine(for: row.field?.platformDecision, device: ClashMacValueWords.device))
                        if let words = copy.platformWords(for: row.field, locale: locale) {
                            Text(verbatim: words).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("configuration-center.section.platform-decided.row")
                }
            } footer: {
                Text(clash: ConfigurationValueWords.notApplyingFooter(device: ClashMacValueWords.device))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(clash: ConfigurationValueWords.notApplyingTitle))
    }
}

 
 
struct ClashMacSectionKeyLabel: View {
    let row: ClashMacSectionRow
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    var body: some View {
         
         
        Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale))
         
         
        if let why = ClashMacSectionKeyLabel.unavailableWords(row.value, field: row.field, copy: copy, locale: locale) {
            Text(verbatim: why).foregroundStyle(.orange)
        }
        if let note = row.caption {
            Text(clash: note)
        }
    }
}

extension ClashMacSectionKeyLabel {
     
     
     
     
     
    static func unavailableWords(_ value: OrderedJSON?, field: ConfigurationField?, copy: ConfigurationFieldCopy,
                                 locale: Locale) -> String? {
        guard let field, !field.unavailableValues.isEmpty else { return nil }
        let written: [String]
        switch value {
        case .string(let text)?: written = field.separator.map { text.components(separatedBy: $0) } ?? [text]
        case .scalar(let token)?: written = [token]
        case .array(let items)?: written = items.compactMap { if case .string(let text) = $0 { return text }; return nil }
        default: written = []
        }
        let lines = written.compactMap { item in
            field.unavailability(of: item.trimmingCharacters(in: .whitespaces)).map { marked in
                copy.unavailableWords(marked.value, locale: locale)
                    ?? ClashCopy.string(for: .format("%@ can’t run on this device.", [marked.value]), locale: locale)
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

 
 
 
 
 
struct ClashMacInlineValueRow: View {
    let row: ClashMacSectionRow
    let control: ClashMacFieldControl
     
    let save: (OrderedJSON?) -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    init(row: ClashMacSectionRow, control: ClashMacFieldControl, save: @escaping (OrderedJSON?) -> Void) {
        self.row = row
        self.control = control
        self.save = save
        _text = State(initialValue: row.value.map { ClashMacValueDraft.summary($0) } ?? "")
    }

    private var draft: ClashMacFieldDraft {
        var draft = ClashMacFieldDraft(control: control, value: nil, path: row.field?.path ?? "")
        draft.text = text
        return draft
    }

     
     
    private var problem: ConfigurationFieldProblem? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draft.problem
    }

    var body: some View {
        TextField(text: $text, prompt: (ClashMacValueWords.placeholder(row.field, locale: locale, copy: copy)
                                         ?? copy.entry(for: row.field, locale: locale)?.example).map { Text(verbatim: $0) }) {
            Text(verbatim: copy.title(for: row.field, key: row.key, locale: locale))
            if let problem { Text(clash: problem.words).foregroundStyle(.red) }
             
            else if case .number(_, _, let unit?, _) = control,
                    let number = text.isEmpty ? ClashMacValueWords.placeholder(row.field, locale: locale, copy: copy) : text,
                    Double(number) != nil {
                Text(clash: ConfigurationValueWords.number(number, unit: unit, locale: locale))
            }
        }
        .disableAutocorrection(true)
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { isFocused in if !isFocused { commit() } }
         
         
        .onChange(of: row.value) { value in
            if !focused { text = value.map { ClashMacValueDraft.summary($0) } ?? "" }
        }
        .accessibilityIdentifier("configuration-center.section.row.text")
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let written = row.value.map { ClashMacValueDraft.summary($0) } ?? ""
        guard trimmed != written else { return }
        if trimmed.isEmpty { if row.removable { save(nil) }; return }
        var next = draft
        next.text = trimmed
        guard next.isValid else { return }
        save(next.value)
    }
}

 
 
 
 
public struct ClashMacLANShareEntry {
    public let keys: Set<String>
    public let status: @MainActor (OrderedJSON) -> ClashDisplayText
    public let page: @MainActor () -> AnyView
    public init(keys: Set<String>, status: @escaping @MainActor (OrderedJSON) -> ClashDisplayText,
                page: @escaping @MainActor () -> AnyView) {
        self.keys = keys; self.status = status; self.page = page
    }
}

 
struct ClashMacKeyEdit: Identifiable {
    let path: [String]
     
    let value: OrderedJSON?
    let platformReason: String?
    let choices: [String]?
     
    var control: ClashMacFieldControl? = nil
     
    var removable = false
     
    var isDefault = false
     
    var field: ConfigurationField? = nil
    var id: String { path.joined(separator: ".") }
}

 
 
 
struct ClashMacValueEditSheet: View {
    let edit: ClashMacKeyEdit
    let save: (OrderedJSON) -> Void
     
    var useDefault: (() -> Void)? = nil
     
    var geoValues: ClashMacGeoValueLoader? = nil
     
     
    var turnOff: (() -> Void)? = nil
     
     
    var removeTitle: ClashDisplayText = .copy("Use Default")
    @State private var draft: ClashMacValueDraft?
     
    @State private var field: ClashMacFieldDraft?
    @State private var pickingKnown = false
     
     
    @State private var seed: OrderedJSON?
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    private var value: OrderedJSON? { field?.value ?? draft?.value }

     
     
    private var words: ConfigurationFieldCopy.Entry? { copy.entry(for: edit.field, locale: locale) }
    private var key: String { edit.path.last ?? "" }

     
     
    private var known: ClashMacGeoResource? {
        guard geoValues != nil, edit.platformReason == nil, let set = ConfigurationFieldExamples.knownSet(for: edit.field) else { return nil }
        return ClashMacGeoResource(set)
    }

     
    private static let otherTag = "\u{1F}other"

     
     
    private var writtenAs: some View {
        Text(clash: .format("Written as %@ in the configuration file", [key]))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

     
     
     
    private var saveDisabled: Bool {
        guard let value else { return true }
         
         
        if field?.writesNothing == true { return value == seed || edit.isDefault || (turnOff == nil && useDefault == nil) }
        return value == seed || !(field?.isValid ?? draft?.isValid ?? false)
    }

     
     
     
     
    static func drafts(for edit: ClashMacKeyEdit) -> (field: ClashMacFieldDraft?, value: ClashMacValueDraft?) {
        if let control = edit.control {
            return (ClashMacFieldDraft(control: control, value: edit.value, defaultText: edit.field?.defaultText,
                                      path: edit.field?.path ?? ""), nil)
        }
        return (nil, edit.value.flatMap(ClashMacValueDraft.init))
    }

     
     
     
     
     
    static func showsPresets(_ control: ClashMacFieldControl?, hasPresets: Bool, path: String) -> Bool {
        guard hasPresets, case .text(_, let suggestions)? = control, suggestions.isEmpty else { return false }
        return ConfigurationFormatPresets.addressChoices(path: path) == nil
    }

     
    @ViewBuilder
    private var listDefault: some View {
        if edit.isDefault, field?.items.isEmpty ?? draft?.items.isEmpty ?? false {
            Text(clash: ClashMacValueWords.defaultLine(edit.field, locale: locale, copy: copy))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("configuration-center.section.value.list-default")
        }
    }

     
     
    private var isList: Bool {
        if case .lines? = field?.control { return edit.platformReason == nil }
        return field == nil && draft?.kind == .list && edit.platformReason == nil
    }

    var body: some View {
        ClashMacSheetFrame(title: .verbatim(copy.title(for: edit.field, key: key, locale: locale)),
                          width: 480, height: known == nil ? 460 : 520) {
            if let known, let geoValues, let field = Binding($field), case .lines = field.wrappedValue.control {
                 
                ClashMacGeoValuesChecklist(resource: known, items: field.items, load: geoValues)
            } else if let known, let geoValues, pickingKnown, let field = Binding($field) {
                 
                ClashMacGeoValuePickerPage(resource: known, current: field.wrappedValue.text, load: geoValues,
                                          identifier: "configuration-center.section.value.known.pick", pick: { picked in
                    field.wrappedValue.text = picked
                    pickingKnown = false
                }, custom: field.text)
            } else if let known, let field = Binding($field), case .text = field.wrappedValue.control {
                ClashMacSheetForm {
                    Section {
                        ClashMacGeoValueRow(resource: known, value: field.wrappedValue.text,
                                           identifier: "configuration-center.section.value.known.choose") { pickingKnown = true }
                    }
                     
                    Section {
                        TextField(text: field.text, prompt: Text(clash: .copy("Custom"))) { Text(clash: .copy("Custom")) }
                            .disableAutocorrection(true)
                            .accessibilityIdentifier("configuration-center.section.value.known.custom")
                    } footer: {
                        Text(clash: .copy("Only when the list doesn’t have it."))
                    }
                }
            } else if isList, let field = Binding($field), case .lines(let format, let suggestions, let ordered) = field.wrappedValue.control {
                VStack(alignment: .leading, spacing: 8) {
                    ClashMacListValueEditor(items: field.items, format: format, ordered: ordered, suggestions: suggestions,
                                           field: edit.field, path: field.wrappedValue.path, pending: field.pendingItem)
                    listDefault
                    writtenAs
                }
                .padding(16)
            } else if isList, let draft = Binding($draft) {
                VStack(alignment: .leading, spacing: 8) {
                    ClashMacListValueEditor(items: draft.items, format: nil, pending: draft.pendingItem)
                    listDefault
                }
                .padding(16)
            } else {
            ClashMacSheetForm {
                if edit.platformReason != nil {
                    Section {
                        LabeledContent { EmptyView() } label: {
                            Text(clash: ConfigurationValueWords.categoryLine(for: edit.field?.platformDecision, device: ClashMacValueWords.device))
                             
                             
                            if let words = copy.platformWords(for: edit.field, locale: locale) { Text(verbatim: words) }
                        }
                    }
                }
                 
                 
                if edit.platformReason == nil, let presets = words?.presets,
                   let field = Binding($field), Self.showsPresets(field.wrappedValue.control, hasPresets: !presets.isEmpty,
                                                                  path: field.wrappedValue.path) {
                    Section {
                         
                         
                         
                        Picker(selection: Binding(
                            get: {
                                let values = presets.map(\.value), typed = field.wrappedValue.text
                                return ConfigurationChoiceMatch.choice(for: typed, in: values,
                                                                       caseInsensitive: edit.field?.caseInsensitive == true)
                                    ?? ConfigurationChoiceMatch.addressChoice(for: typed, in: values) ?? Self.otherTag
                            },
                            set: { picked in if picked != Self.otherTag { field.wrappedValue.text = picked } }
                        )) {
                            ForEach(presets, id: \.value) { Text(verbatim: $0.label).tag($0.value) }
                            Text(clash: .copy("Other")).tag(Self.otherTag)
                        } label: { Text(clash: .copy("Common Values")) }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("configuration-center.section.value.presets")
                    }
                }
                Section {
                    if let field = Binding($field) {
                        ClashMacFieldEditor(draft: field, field: edit.field)
                            .disabled(edit.platformReason != nil)
                    } else if let draft = Binding($draft) {
                        ClashMacValueEditor(draft: draft, choices: edit.choices, field: edit.field)
                            .disabled(edit.platformReason != nil)
                    } else {
                         
                         
                         
                        Text(clash: ConfigurationValueWords.summary(edit.value, field: edit.field, locale: locale, copy: copy))
                            .accessibilityIdentifier("configuration-center.section.value.summary")
                        Text(clash: .copy("Change this one in the source.")).foregroundStyle(.secondary)
                    }
                } footer: {
                     
                     
                    VStack(alignment: .leading, spacing: 4) {
                        if let summary = words?.summary, !summary.isEmpty { Text(verbatim: summary) }
                        writtenAs
                    }
                }
            }
            }
        } leading: {
            if let useDefault, edit.platformReason == nil {
                Button {
                    useDefault()
                    dismiss()
                } label: { Text(clash: removeTitle) }
                .accessibilityIdentifier("configuration-center.section.value.use-default")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.section.value.cancel",
                primaryTitle: value != nil && edit.platformReason == nil ? .copy("Save") : nil,
                primaryIdentifier: "configuration-center.section.value.save",
                primaryDisabled: saveDisabled,
                onClose: { dismiss() },
                onPrimary: {
                     
                     
                    if field?.writesNothing == true { (turnOff ?? useDefault)?() } else if let value { save(value) }
                    dismiss()
                }
            )
        }
        .clashCapturesDismiss(dismiss)
        .onAppear {
            if field == nil, draft == nil {
                (field, draft) = Self.drafts(for: edit)
                seed = field?.value ?? draft?.value
            }
             
            if known != nil, case .text? = field?.control { pickingKnown = true }
        }
    }
}

struct ClashMacValueEditor: View {
    @Binding var draft: ClashMacValueDraft
     
    let choices: [String]?
     
    var field: ConfigurationField? = nil
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

     
    var body: some View {
        Group {
            switch draft.kind {
            case .toggle:
                Toggle(isOn: $draft.flag) { Text(clash: .copy("On")) }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("configuration-center.section.value.toggle")
            case .number:
                TextField(text: $draft.text) { Text(clash: .copy("Value")) }
                    .accessibilityIdentifier("configuration-center.section.value.number")
            case .text:
                if let choices, !choices.isEmpty {
                    Picker(selection: $draft.text) {
                        ForEach(choices, id: \.self) { Text(verbatim: copy.valueLabel($0, for: field, locale: locale) ?? $0).tag($0) }
                    } label: { Text(clash: .copy("Value")) }
                    .accessibilityIdentifier("configuration-center.section.value.choice")
                } else {
                    TextField(text: $draft.text) { Text(clash: .copy("Value")) }
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-center.section.value.text")
                }
            case .list:
                ClashMacListValueEditor(items: $draft.items, format: nil, pending: $draft.pendingItem)
                    .accessibilityIdentifier("configuration-center.section.value.list")
            }
        }
    }
}

 
 
 
 
 
struct ClashMacMapEntryKind {
    let choices: [String]?
    let keyFormat: ConfigurationFieldFormat?
    let control: ClashMacFieldControl?
     
    let emptyValue: OrderedJSON
     
     
    let mapPath: String
    let valuePath: String

    init(map: ConfigurationField, entry: ConfigurationField?, control make: (ConfigurationField) -> ClashMacFieldControl?) {
        choices = map.key?.values.flatMap { $0.isEmpty ? nil : $0 }
        keyFormat = map.key?.format
        mapPath = map.path
        valuePath = entry?.path ?? map.path
        switch entry?.kind ?? map.value?.kind {
        case .object?, .map?:
            control = nil; emptyValue = .object([])
        case .objectList?:
            control = nil; emptyValue = .array([])
        default:
            control = entry.flatMap(make) ?? .text(format: nil, suggestions: [])
            emptyValue = .string("")
        }
    }
}

 
 
 
 
struct ClashMacNewEntrySheet: View {
    let entry: ClashMacMapEntryKind
    let taken: Set<String>
     
     
     
     
    var policyKeys = false
     
    var ruleSets: [String] = []
    var geoValues: ClashMacGeoValueLoader? = nil
    let save: (String, OrderedJSON) -> Void
    @State private var key = ""
    @State private var field: ClashMacFieldDraft?
    @State private var policyKind: ConfigurationPolicyKey.Kind = .domain
    @State private var policyValue = ""
    @State private var pickingGeo = false
    @StateObject private var dismiss = ClashDismissHandle()

    private var name: String {
        guard policyKeys else { return key.trimmingCharacters(in: .whitespaces) }
        let value = policyValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "" : ConfigurationPolicyKey.compose(policyKind, value)
    }

     
    @ViewBuilder
    private var policyKeySection: some View {
        Section {
            Picker(selection: $policyKind) {
                ForEach(ConfigurationPolicyKey.Kind.allCases) { Text(clash: $0.title).tag($0) }
            } label: { Text(clash: .copy("Applies To")) }
            .pickerStyle(.menu)
            .accessibilityIdentifier("configuration-center.section.new-entry.policy-kind")
            switch policyKind {
            case .domain:
                TextField(text: $policyValue, prompt: Text(clash: ConfigurationFieldExamples.prompt(for: .domain))) {
                    Text(clash: .copy("Domain Name"))
                }
                .disableAutocorrection(true)
                .accessibilityIdentifier("configuration-center.section.new-entry.policy-domain")
            case .geosite:
                if geoValues != nil {
                    ClashMacGeoValueRow(resource: .geoSite, value: policyValue,
                                       identifier: "configuration-center.section.new-entry.policy-geosite") { pickingGeo = true }
                } else {
                    TextField(text: $policyValue) { Text(clash: .copy("GEOSITE Category")) }
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("configuration-center.section.new-entry.policy-geosite")
                }
            case .ruleSet:
                Picker(selection: $policyValue) {
                    Text(clash: .copy("Choose…")).tag("")
                    ForEach(ruleSets, id: \.self) { Text(verbatim: $0).tag($0) }
                } label: { Text(clash: .copy("Rule Set")) }
                .pickerStyle(.menu)
                .accessibilityIdentifier("configuration-center.section.new-entry.policy-ruleset")
            }
        } footer: {
            if policyKind == .ruleSet && ruleSets.isEmpty {
                Text(clash: .copy("This configuration has no rule sets yet."))
            }
        }
    }
     
    private var available: [String]? { entry.choices?.filter { !taken.contains($0) } }

     
    private var keyProblem: ConfigurationFieldProblem? {
        guard !policyKeys, available == nil, !name.isEmpty else { return nil }
        return ClashMacFieldDraft.itemProblem(name, format: entry.keyFormat, path: entry.mapPath, allowed: [])
    }

    var body: some View {
        ClashMacSheetFrame(title: .copy("Add"), width: 480, height: pickingGeo ? 520 : 400) {
            if pickingGeo, let geoValues {
                ClashMacGeoValuePickerPage(resource: .geoSite, current: policyValue, load: geoValues,
                                          identifier: "configuration-center.section.new-entry.policy-geosite.pick") { picked in
                    policyValue = picked
                    pickingGeo = false
                }
            } else {
            ClashMacSheetForm {
                if policyKeys {
                    policyKeySection
                } else {
                Section {
                    if let available {
                        Picker(selection: $key) {
                            ForEach(available, id: \.self) { Text(verbatim: $0).tag($0) }
                        } label: { Text(clash: .copy("Name")) }
                        .accessibilityIdentifier("configuration-center.section.new-entry.choice")
                    } else {
                        TextField(text: $key) { Text(clash: .copy("Name")) }
                            .disableAutocorrection(true)
                            .accessibilityIdentifier("configuration-center.section.new-entry.name")
                         
                        if let keyProblem { ClashMacProblemLine(problem: keyProblem) }
                    }
                }
                }
                if let field = Binding($field) {
                    Section { ClashMacFieldEditor(draft: field) }
                }
            }
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.section.new-entry.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.section.new-entry.add",
                primaryDisabled: name.isEmpty || taken.contains(name) || keyProblem != nil || !(field?.isValid ?? true)
                    || field.map { draft -> Bool in if case .lines = draft.control { return !draft.hasEntries }; return false } == true,
                onClose: { dismiss() },
                onPrimary: {
                    save(name, field?.value ?? entry.emptyValue)
                    dismiss()
                }
            )
        }
        .clashCapturesDismiss(dismiss)
         
        .onChange(of: policyKind) { _ in policyValue = "" }
        .onAppear {
            if key.isEmpty, let first = available?.first { key = first }
            if field == nil, let control = entry.control {
                var draft = ClashMacFieldDraft(control: control, value: nil, path: entry.valuePath)
                 
                if case .choose(let options, _) = control, draft.text.isEmpty, let first = options.first { draft.text = first }
                field = draft
            }
        }
    }
}

 
 
 
struct ClashMacGroupFooter: View {
    let words: String?
     
     
     
    let off: ConfigurationOffSwitchSummary?
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    var body: some View {
        if let words, !words.isEmpty, let off {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(verbatim: words)
                Text(clash: copy.turnOnLine(off, locale: locale))
            }
        } else if let words, !words.isEmpty {
            Text(verbatim: words)
        } else if let off {
            Text(clash: copy.turnOnLine(off, locale: locale))
                .accessibilityIdentifier("configuration-center.section.turn-on")
        }
    }
}

 
 
 
struct ClashMacRowFailure: View {
    let message: String

    var body: some View {
        Text(verbatim: message)
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier("configuration-center.section.row.failure")
    }
}

extension ConfigurationPageEdit {
     
    var writtenPath: [String] {
        switch self {
        case .set(let path, _), .remove(let path), .insert(let path, _, _), .replace(let path, _, _),
             .delete(let path, _), .move(let path, _, _), .renameKey(let path, _, _), .moveKeys(let path, _, _):
            return path
        case .insertKey(let path, let key, _, _):
            return path + [key]
        }
    }
}

 
 
 
 
 
 
 
 
 
 
public struct ClashMacSettingsChapterPage: View {
    let section: ConfigurationOutlineSection
    let actions: ClashMacSettingsSectionActions

    public init(section: ConfigurationOutlineSection, actions: ClashMacSettingsSectionActions) {
        self.section = section
        self.actions = actions
    }

    public var body: some View {
        ClashSingleColumnNavigationContainer {
            ClashMacSettingsSectionPage(
                section: section, basePath: [], knownKeys: ConfigurationOutline.settingKeys(in: section), actions: actions
            )
            .navigationTitle(Text(clash: ClashMacConfigurationOutlineCard.title(section)))
             
             
             
            .clashProductModalRoot(title: ClashMacConfigurationOutlineCard.title(section))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("configuration-center.chapter-page.\(section.rawValue)")
    }
}
