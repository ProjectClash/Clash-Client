import ClashClientUI
import SwiftUI

extension CustomOverwriteError: ClashAuthoredError {
     
     
     
     
     
    var displayText: ClashDisplayText {
        switch self {
        case .removedRelay(let group):
            .format("“%@” is a relay group, which the core no longer has. Set Connect Through on its nodes instead.", [group])
        case .unsupportedGroupType(let group, let type):
            .format("“%@” has a type the core doesn't know: %@.", [group, type])
        case .missingMembers(let group):
            .format("“%@” has no members. Add a node or a proxy provider, or turn on Include Everything.", [group])
        case .groupEmptyFallback(let group, let target):
            .format("“%@”: When Empty names the group “%@”, and it can only name a node.", [group, target])
        case .invalidExpression(let group, let field):
            field == "exclude-filter"
                ? .format("“%@”: Leave Out Nodes is written in a form the core can't read.", [group])
                : .format("“%@”: Only Matching Nodes is written in a form the core can't read.", [group])
        case .unknownMember(let group, let member):
            .format("“%@” lists “%@”, which isn't in this configuration.", [group, member])
        case .unknownProvider(let group, let provider):
            .format("“%@” uses the proxy provider “%@”, which isn't in this configuration.", [group, provider])
        case .unknownEmptyFallback(let group, let target):
            .format("“%@”: When Empty names “%@”, which doesn't exist, and it can only name a node.", [group, target])
        case .duplicateGroupName(let group):
            .format("The name “%@” is already taken. Nodes, groups and the built-in ones can't share a name.", [group])
        }
    }

     
     
     
    static func displayText(for message: String, from error: CustomOverwriteError?) -> ClashDisplayText {
        if let error, error.localizedDescription == message { return error.displayText }
        return .copy(message)
    }
}

struct CustomProxyGroupsEditor: View {
    @Binding var groups: [CustomProxyGroup]
     
     
     
     
    var profileProxyNames: [String] = []
     
     
    var validationContext = CustomGroupValidationContext(
        nodeNames: [], groupNames: [], providerNames: [], siblingGroupNames: []
    )
     
     
     
     
    var onRename: ((String, String) -> Void)?
     
     
    var draftScope: String?
    @State private var editing: Target?
     
     
    @State private var rows = ClashIdentifiedRows()
     
     
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
#if os(iOS)
     
     
    @State private var editMode: EditMode = .inactive
#endif
    private var isReordering: Bool {
#if os(iOS)
        editMode.isEditing
#else
        false
#endif
    }

    private struct Target: Identifiable {
        let id = UUID()
        let rowID: UUID?
        let group: CustomProxyGroup
    }

    private var groupTypes: [String: String] {
        ConfigurationTypeWords.names(.proxyGroups, copy: fieldCopy, locale: locale)
    }

    var body: some View {
        let groupTypes = groupTypes
        Group {
#if os(macOS)
         
         
         
         
         
         
        Form {
            if groups.isEmpty {
                Section {
                ClashEmptyState(
                    title: "No Custom Groups",
                    message: "",
                    symbol: .point3ConnectedTrianglepathDotted
                )
                .listRowSeparator(.hidden)
                }
            } else {
                Section {
            ForEach(rows.current(for: groups)) { row in
                let group = rows.index(of: row.id).map { groups[$0] }
                    ?? CustomProxyGroup(name: "")
                Button {
                    editing = Target(rowID: row.id, group: group)
                } label: {
                    ClashDestinationRow(
                         
                        title: .verbatim(group.name),
                        subtitle: group.validationError.map {
                            $0.displayText
                        } ?? .format(
                            "%@ · %@ proxies · %@ providers",
                            [
                                ConfigurationTypeWords.word(group.type, in: groupTypes),
                                String(group.proxies.count),
                                String(group.providers.count),
                            ]
                        ),
                        symbol: .point3ConnectedTrianglepathDotted,
                        tint: group.validationError == nil ? .blue : .red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom.proxy-group.row.\(group.name)")
            }
            .onDelete(perform: isReordering ? nil : { rows.removeOffsets($0, from: &groups) })
            .onMove { rows.move(fromOffsets: $0, toOffset: $1, in: &groups) }
            .onAppear { rows.resync(count: groups.count) }
            .onChange(of: groups.count) { rows.resync(count: $0) }
                }
            }
            Section {
                ClashAddRow(Text(ClashCopy.key("Add Group"))) {
                    editing = Target(rowID: nil, group: CustomProxyGroup(name: ""))
                }
                .accessibilityIdentifier("custom.proxy-group.row.add")
            }
        }
#else
        List {
            if groups.isEmpty {
                ClashEmptyState(
                    title: "No Custom Groups",
                    message: "",
                    symbol: .point3ConnectedTrianglepathDotted
                )
                .listRowSeparator(.hidden)
            }
            ForEach(rows.current(for: groups)) { row in
                let group = rows.index(of: row.id).map { groups[$0] }
                    ?? CustomProxyGroup(name: "")
                Button {
                    editing = Target(rowID: row.id, group: group)
                } label: {
                    ClashDestinationRow(
                         
                        title: .verbatim(group.name),
                        subtitle: group.validationError.map {
                            $0.displayText
                        } ?? .format(
                            "%@ · %@ proxies · %@ providers",
                            [
                                ConfigurationTypeWords.word(group.type, in: groupTypes),
                                String(group.proxies.count),
                                String(group.providers.count),
                            ]
                        ),
                        symbol: .point3ConnectedTrianglepathDotted,
                        tint: group.validationError == nil ? .blue : .red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom.proxy-group.row.\(group.name)")
            }
            .onDelete(perform: isReordering ? nil : { rows.removeOffsets($0, from: &groups) })
            .onMove { rows.move(fromOffsets: $0, toOffset: $1, in: &groups) }
            .onAppear { rows.resync(count: groups.count) }
            .onChange(of: groups.count) { rows.resync(count: $0) }
        }
        .clashInsetGroupedListStyle()
        .environment(\.editMode, $editMode)
#endif
        }
        .clashPageTitle("Proxy Groups")
        .clashDetailPageInsets()
        .clashToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .clashNavigationTrailing) {
#if os(iOS)
                if groups.count > 1 {
                    ConfigurationReorderButton(editMode: $editMode, identifier: "custom.proxy-group.reorder")
                }
#endif
            }
        }
        .clashProductModalChild(title: "Proxy Groups")
        .clashProductModal(item: $editing, role: .page) { target in
            CustomProxyGroupEditor(
                group: target.group,
                existingNames: Set(groups.enumerated().compactMap {
                    $0.offset == target.rowID.flatMap(rows.index(of:))
                        ? nil : $0.element.name
                }),
                profileProxyNames: profileProxyNames,
                validationContext: validationContext,
                draftKey: draftScope.map { CustomProxyGroupEditor.draftKey(scope: $0, groupName: target.group.name) }
            ) { group in
                if let id = target.rowID,
                   let index = rows.index(of: id) {
                    let previousName = groups[index].name
                    if previousName != group.name {
                        onRename?(previousName, group.name)
                    }
                    rows.update(id, in: &groups, to: group)
                } else {
                    rows.append(group, to: &groups)
                }
            }
            .clashModalPresentation(.page)
        }
    }
}
 
 
struct CustomProxyGroupEditorDraft: Codable, Equatable {
    var group: CustomProxyGroup
    var interval: String
    var timeout: String
    var maxFailedTimes: String
    var tolerance: String
}

extension CustomProxyGroupEditorDraft {
    init(opening group: CustomProxyGroup) {
        self.init(group: group,
                  interval: group.interval.map(String.init) ?? "",
                  timeout: group.timeout.map(String.init) ?? "",
                  maxFailedTimes: group.maxFailedTimes.map(String.init) ?? "",
                  tolerance: group.tolerance.map(String.init) ?? "")
    }
}

struct CustomProxyGroupEditor: View {
    let save: (CustomProxyGroup) -> Void
    let validateChange: ((CustomProxyGroup) -> String?)?
    let existingNames: Set<String>
    let validationContext: CustomGroupValidationContext
    let profileProxyNames: [String]

     
     
     
     
     
     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @State private var group: CustomProxyGroup
    @State private var interval = ""
    @State private var timeout = ""
    @State private var maxFailedTimes = ""
    @State private var tolerance = ""
    @State private var error = ""
     
     
    @State private var refusal: CustomOverwriteError?
    @State private var iconHistory = ProxyGroupIconHistory.load()
     
    @State private var draftSlot: ClashDraftSlot<CustomProxyGroupEditorDraft>
    @State private var showsRestoredDraft: Bool

     
     
     
    static func draftKey(scope: String, groupName: String) -> String {
        "Proxy Group|\(scope)|" + (groupName.isEmpty ? "new" : "name:\(groupName)")
    }

    init(
        group: CustomProxyGroup,
        existingNames: Set<String>,
        profileProxyNames: [String] = [],
        validationContext: CustomGroupValidationContext =
            CustomGroupValidationContext(
                nodeNames: [], groupNames: [],
                providerNames: [], siblingGroupNames: []
            ),
        validateChange: ((CustomProxyGroup) -> String?)? = nil,
        draftKey: String? = nil,
        save: @escaping (CustomProxyGroup) -> Void
    ) {
        self.existingNames = existingNames
        self.validationContext = validationContext
        self.profileProxyNames = profileProxyNames
        self.save = save
        self.validateChange = validateChange
        let slot = ClashDraftSlot(key: draftKey ?? "",
                                  original: CustomProxyGroupEditorDraft(opening: group),
                                  store: draftKey == nil ? nil : SourceEditDrafts.shared)
        _draftSlot = State(initialValue: slot)
        let opening = slot.opening()
        _group = State(initialValue: opening.value.group)
        _interval = State(initialValue: opening.value.interval)
        _timeout = State(initialValue: opening.value.timeout)
        _maxFailedTimes = State(initialValue: opening.value.maxFailedTimes)
        _tolerance = State(initialValue: opening.value.tolerance)
        _showsRestoredDraft = State(initialValue: opening.needsNotice)
    }

     
     
    private var groupTypes: [String: String] {
        ConfigurationTypeWords.names(.proxyGroups, copy: fieldCopy, locale: locale)
    }

    var body: some View {
        ClashFeatureNavigationContainer {
            Form {
                if showsRestoredDraft {
                    Section {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            ClashStatusMessage(text: .copy("Unsaved edits from last time were restored."), kind: .information)
                                .accessibilityIdentifier("custom.proxy-group.restored")
                            Spacer(minLength: 0)
                            Button("Discard", role: .destructive) { discardDraft() }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                                .accessibilityIdentifier("custom.proxy-group.restored.discard")
                        }
                    }
                }
                Section("Group") {
                    TextField("Name", text: $group.name)
                        .accessibilityIdentifier("custom.proxy-group.name")
                    Picker("Type", selection: $group.type) {
                        ForEach(CustomProxyGroup.types, id: \.self) { type in
                             
                            Text(ConfigurationTypeWords.word(type, in: groupTypes))
                            .tag(type)
                        }
                    }
                    .accessibilityIdentifier("custom.proxy-group.type")
                }

                if let validationError = group.validationError {
                    Section {
                        ClashStatusMessage(text: validationError.displayText, kind: .error)
                    }
                }

                Section("Proxies") {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    Toggle("Include all proxies and providers", isOn: optionalBoolBinding(\.includeAll))
                        .accessibilityIdentifier("custom.proxy-group.include-all")
                    Toggle("Include all proxies", isOn: $group.includeAllProxies)
                        .accessibilityIdentifier("custom.proxy-group.include-all-proxies")
                    StringListEditor(
                        items: $group.proxies,
                        itemTitle: "Proxy",
                        placeholder: "Proxy or group name",
                        identifier: "custom.proxy-group.proxies"
                    )
                    memberCandidateMenu
                }

                Section("Proxy Providers") {
                    Toggle("Include all providers", isOn: $group.includeAllProviders)
                        .accessibilityIdentifier("custom.proxy-group.include-all-providers")
                    StringListEditor(
                        items: $group.providers,
                        itemTitle: "Provider",
                        placeholder: "Provider name",
                        identifier: "custom.proxy-group.providers"
                    )
                }

                Section {
                    switch group.type {
                    case "select":
                         
                         
                         
                        TextField("Default route", text: optionalBinding(\.defaultSelected))
                            .accessibilityIdentifier("custom.proxy-group.default-selected")
                    case "url-test":
                        TextField("Allowed latency difference (ms)", text: $tolerance)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("custom.proxy-group.tolerance")
                    case "load-balance":
                        Picker("Distribution strategy", selection: optionalBinding(\.strategy)) {
                            Text("Default (consistent hashing)").tag("")
                            Text("Consistent hashing").tag("consistent-hashing")
                            Text("Round robin").tag("round-robin")
                            Text("Sticky sessions").tag("sticky-sessions")
                        }
                        .accessibilityIdentifier("custom.proxy-group.strategy")
                    default:
                        EmptyView()
                    }
                } header: {
                    Text("Selection")
                }

                Section("Health Check") {
                    TextField("Test URL", text: optionalBinding(\.url))
                                                .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("custom.proxy-group.url")
                    TextField("Interval (seconds)", text: $interval)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("custom.proxy-group.interval")
                    TextField("Timeout (ms)", text: $timeout)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("custom.proxy-group.timeout")
                    TextField("Maximum failed times", text: $maxFailedTimes)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("custom.proxy-group.max-failed-times")
                    TextField("Expected status", text: optionalBinding(\.expectedStatus))
                        .accessibilityIdentifier("custom.proxy-group.expected-status")
                    Toggle("Test when used", isOn: $group.lazy)
                        .accessibilityIdentifier("custom.proxy-group.lazy")
                }

                Section("Filters") {
                    TextField("Include regex", text: optionalBinding(\.filter))
                        .accessibilityIdentifier("custom.proxy-group.filter")
                    TextField("Exclude regex", text: optionalBinding(\.excludeFilter))
                        .accessibilityIdentifier("custom.proxy-group.exclude-filter")
                    TextField("Exclude types", text: optionalBinding(\.excludeType))
                        .accessibilityIdentifier("custom.proxy-group.exclude-type")
                    TextField("Use if no route remains", text: optionalBinding(\.emptyFallback))
                        .accessibilityIdentifier("custom.proxy-group.empty-fallback")
                }

                Section("Options") {
                    Toggle("Disable UDP", isOn: $group.disableUDP)
                        .accessibilityIdentifier("custom.proxy-group.disable-udp")
                    Toggle("Hide from list", isOn: $group.hidden)
                        .accessibilityIdentifier("custom.proxy-group.hidden")
                }

                Section {
                    TextField("emoji, a name, or https URL", text: optionalBinding(\.icon))
                                                .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("custom.proxy-group.icon")
                    iconEcho
                    ForEach(iconHistory, id: \.self) { icon in
                        Button(icon) { group.icon = icon }
                            .font(.caption)
                    }
                } header: {
                    Text("Icon")
                }

                if !error.isEmpty {
                    ClashStatusMessage(text: CustomOverwriteError.displayText(for: error, from: refusal), kind: .error)
                }
            }
            .clashPageTitle("Proxy Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") { draftSlot.clear(); dismissPresentation() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal {
                         
                         
                        ClashSaveButton(.copy("Done"), isEnabled: isNameable) { persist() }
                            .accessibilityIdentifier("custom.proxy-group.save")
                    }
                }
            }
            .clashProductModalRoot(title: "Proxy Group")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                    ClashModalActionBar(
                        primaryTitle: "Done",
                    primaryDisabled: !isNameable,
                         
                         
                         
                         
                        primaryHint: isNameable ? nil : "Give this group a name.",
                        onPrimary: persist
                    )
                }
            }
        }
        .clashStackNavigationViewStyle()
         
         
         
         
        .onChange(of: currentDraft) { draftSlot.record($0) }
        .clashCapturesDismiss(dismiss)
    }

     
     
     
     
     
     
     
    @ViewBuilder
    private var iconEcho: some View {
        switch ClashProxyGroupIconKind.of(group.icon) {
        case .emoji(let value):
            echoRow("Shows as") { Text(verbatim: value) }
        case .symbol(let symbol):
            echoRow("Shows as") { Image(systemName: symbol.name) }
        case .remote(let host):
            echoRow("Image on") { Text(verbatim: host) }
        case .unrecognized:
            EmptyView()
        case .none:
            EmptyView()
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private var memberCandidateMenu: some View {
        let candidates = GroupMemberCandidates.offer(
            proxies: profileProxyNames,
            groups: Array(existingNames),
            excluding: group.proxies,
            selfName: group.name
        )
        if !candidates.isEmpty {
            Menu {
                ForEach(candidates, id: \.self) { name in
                    Button(name) { group.proxies.append(name) }
                }
            } label: {
                Label {
                    Text(clash: "Add from this profile")
                } icon: {
                    Image(systemName: ClashSymbol.plus.name)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("custom.proxy-group.add-member")
        }
    }

    private func echoRow<Value: View>(
        _ label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack {
            Text(clash: .copy(label))
            Spacer(minLength: ClashTheme.Spacing.compact)
            value().foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("custom.proxy-group.icon.echo")
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<CustomProxyGroup, String?>) -> Binding<String> {
        Binding(
            get: { group[keyPath: keyPath] ?? "" },
            set: { group[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func optionalBoolBinding(
        _ keyPath: WritableKeyPath<CustomProxyGroup, Bool?>
    ) -> Binding<Bool> {
        Binding(
            get: { group[keyPath: keyPath] ?? false },
            set: { group[keyPath: keyPath] = $0 }
        )
    }

     
     
     
     
     
     
     
     
     
    private var isNameable: Bool {
        CustomGroupSavePolicy.normalizedName(group.name) != nil
    }

    private var currentDraft: CustomProxyGroupEditorDraft {
        CustomProxyGroupEditorDraft(group: group, interval: interval, timeout: timeout,
                                    maxFailedTimes: maxFailedTimes, tolerance: tolerance)
    }

    private func discardDraft() {
        let original = draftSlot.original
        group = original.group
        interval = original.interval
        timeout = original.timeout
        maxFailedTimes = original.maxFailedTimes
        tolerance = original.tolerance
        draftSlot.clear()
        showsRestoredDraft = false
    }

    private func persist() {
         
         
         
         
         
        guard let name = CustomGroupSavePolicy.normalizedName(group.name) else {
            error = "Group name is required."
            return
        }
        guard !existingNames.contains(name) else { error = "Group names must be unique."; return }
        group.name = name
        do {
             
             
             
             
             
            var context = validationContext
            context.siblingGroupNames.formUnion(existingNames)
            if let error = group.validationError(context: context) {
                throw error
            }
        } catch {
            refusal = error as? CustomOverwriteError
            self.error = error.localizedDescription
            return
        }
         
         
         
         
        if let icon = group.icon, !icon.isEmpty {
            ProxyGroupIconHistory.record(icon)
        }
        group.interval = Int(interval)
        group.timeout = Int(timeout)
        group.maxFailedTimes = Int(maxFailedTimes)
        group.tolerance = Int(tolerance)
        if let message = validateChange?(group) { error = message; return }
        save(group)
         
         
        draftSlot.commit()
        dismissPresentation()
    }

    private func dismissPresentation() {
        dismiss.closeModalOrDismiss()
    }
}

struct CustomRulesEditor: View {
    @Binding var rules: [String]
     
     
     
    var options: RulePolicyOptions = .empty
     
    var draftScope: String? = nil
    @State private var editing: Target?
     
    @State private var rows = ClashIdentifiedRows()
#if os(iOS)
     
     
    @State private var editMode: EditMode = .inactive
#endif
    private var isReordering: Bool {
#if os(iOS)
        editMode.isEditing
#else
        false
#endif
    }

    private struct Target: Identifiable {
        let id = UUID()
        let rowID: UUID?
        let raw: String
    }

    var body: some View {
        Group {
#if os(macOS)
         
         
         
         
         
         
        Form {
            if rules.isEmpty {
                Section {
                ClashEmptyState(
                    title: "No Custom Rules",
                    message: "",
                    symbol: .listBulletRectangle
                )
                .listRowSeparator(.hidden)
                }
            } else {
                Section {
            ForEach(rows.current(for: rules)) { row in
                let rule = rows.index(of: row.id).map { rules[$0] } ?? ""
                Button {
                    editing = Target(rowID: row.id, raw: rule)
                } label: {
                     
                    ConfigurationRuleRow(rule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom.rules.row.\(row.index)")
            }
            .onDelete(perform: isReordering ? nil : { rows.removeOffsets($0, from: &rules) })
            .onMove { rows.move(fromOffsets: $0, toOffset: $1, in: &rules) }
            .onAppear { rows.resync(count: rules.count) }
            .onChange(of: rules.count) { rows.resync(count: $0) }
                }
            }
            Section {
                ClashAddRow(Text(ClashCopy.key("Add Rule"))) {
                    editing = Target(rowID: nil, raw: "")
                }
                .accessibilityIdentifier("custom.rules.row.add")
            }
        }
#else
        List {
            if rules.isEmpty {
                ClashEmptyState(
                    title: "No Custom Rules",
                    message: "",
                    symbol: .listBulletRectangle
                )
                .listRowSeparator(.hidden)
            }
            ForEach(rows.current(for: rules)) { row in
                let rule = rows.index(of: row.id).map { rules[$0] } ?? ""
                Button {
                    editing = Target(rowID: row.id, raw: rule)
                } label: {
                     
                    ConfigurationRuleRow(rule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom.rules.row.\(row.index)")
            }
            .onDelete(perform: isReordering ? nil : { rows.removeOffsets($0, from: &rules) })
            .onMove { rows.move(fromOffsets: $0, toOffset: $1, in: &rules) }
            .onAppear { rows.resync(count: rules.count) }
            .onChange(of: rules.count) { rows.resync(count: $0) }
        }
        .clashInsetGroupedListStyle()
        .environment(\.editMode, $editMode)
#endif
        }
        .clashPageTitle("Rules")
        .clashDetailPageInsets()
        .clashToolbarUnlessInPanel {
            ToolbarItemGroup(placement: .clashNavigationTrailing) {
#if os(iOS)
                if rules.count > 1 {
                    ConfigurationReorderButton(editMode: $editMode, identifier: "custom.rules.reorder")
                }
#endif
            }
        }
        .clashProductModalChild(title: "Rules")
        .clashProductModal(item: $editing, role: .form) { target in
            RuleBuilderAdapter(raw: target.raw, options: options,
                               draftKey: draftScope.map {
                                   ClashRuleBuilderDraft.key(scope: $0, raw: target.raw,
                                                             index: target.rowID.flatMap(rows.index(of:)), in: rules)
                               }) { rule in
                if let id = target.rowID {
                    rows.update(id, in: &rules, to: rule)
                } else if !rules.contains(rule) {
                    rows.append(rule, to: &rules)
                }
            }
            .clashModalPresentation(.page)
        }
    }
}

private enum ProxyGroupIconHistory {
    private static let key = "proxy-group.icon-history"

    private static var defaults: UserDefaults {
        ScriptLibrary.appGroupDefaults
    }

    static func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ value: String) {
        var values = load().filter { $0 != value }
        values.insert(value, at: 0)
        defaults.set(Array(values.prefix(20)), forKey: key)
    }
}
