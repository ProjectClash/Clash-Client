import Foundation
import ClashClientKit
import ClashClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
 
 
@MainActor
final class ProxyNodeEditorDraft: ObservableObject {
    let originalJSON: String
    private(set) var mapping: [String: Any] {
        didSet { cachedEditedJSON = nil }
    }

     
     
     
     
     
     
     
     
     
    private var cachedEditedJSON: String?

    init(configurationJSON: String, fallbackName: String, fallbackType: String) {
        let decoded = ProxyProtocolCatalog.mapping(from: configurationJSON) ?? [:]
        var value = decoded
        if value["name"] == nil { value["name"] = fallbackName }
        if value["type"] == nil { value["type"] = fallbackType }
        mapping = value
        originalJSON = Self.json(value)
    }

    var typeID: String { string("type") }
     
     
     
     
     
     
     
    var editedJSON: String {
        if let cachedEditedJSON { return cachedEditedJSON }
        let value = Self.json(mapping)
        cachedEditedJSON = value
        return value
    }

    var isDirty: Bool { editedJSON != originalJSON }

     
     
     
     
     
     
     
     
    func firstMissingRequiredFieldKey() -> String? {
        for field in ProxyProtocolEditorSchema.fields(for: typeID)
        where field.required && field.key != "type" {
            if field.key == "port", typeID == "hysteria2",
               !string("ports").trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).isEmpty {
                continue
            }
            if string(field.key).trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                return field.key
            }
        }
        return nil
    }

     
     
     
     
     
     
    func detachedCopy() -> ProxyNodeEditorDraft {
        ProxyNodeEditorDraft(
            configurationJSON: editedJSON,
            fallbackName: string("name"),
            fallbackType: typeID
        )
    }

     
     
     
     
    weak var openPage: ProxyNodeEditorDraft?

     
     
     
     
     
     
    var isDirtyIncludingOpenPages: Bool {
        deepestEditedJSON != originalJSON || openPagesHoldText
    }

     
     
     
     
     
    var holdsMoreThanABlankNode: Bool {
        ProxyNodeDetailsView.strippingEmptyStrings(editedJSON)
            != ProxyNodeDetailsView.strippingEmptyStrings(Self.json(ProxyNodeCatalog.newNodeMapping(type: typeID)))
    }

    private var deepestEditedJSON: String { openPage?.deepestEditedJSON ?? editedJSON }

     
    var deepestPage: ProxyNodeEditorDraft { openPage?.deepestPage ?? self }

    private var openPagesHoldText: Bool {
        guard let page = openPage else { return false }
        return page.pendingText?.isPending() == true || page.openPagesHoldText
    }

     
     
    var pendingText: ProxyNodePendingText?

     
     
     
     
     
     
    func absorbOpenPages() -> ClashDisplayText? {
        guard let page = openPage else { return nil }
        if let refusal = page.absorbOpenPages() { return refusal }
        if let refusal = page.pendingText?.apply() { return refusal }
        synchronize(from: page)
        return nil
    }

     
     
     
     
     
    func synchronize(from source: ProxyNodeEditorDraft) {
        guard editedJSON != source.editedJSON,
              let replacement = ProxyProtocolCatalog.mapping(
                from: source.editedJSON
              )
        else { return }
        objectWillChange.send()
        mapping = replacement
    }

     
     
     
     
     
     
     
     
     
     
    func prepare(from source: ProxyNodeEditorDraft) {
        guard editedJSON != source.editedJSON,
              let replacement = ProxyProtocolCatalog.mapping(
                from: source.editedJSON
              )
        else { return }
        mapping = replacement
    }

    func string(_ key: String) -> String {
        string(path: [key])
    }

    func string(path: [String]) -> String {
        Self.render(value(path: path))
    }

     
     
     
     
     
    func list(_ key: String) -> [String] {
        guard let array = value(path: [key]) as? [Any] else { return [] }
        return array.map(Self.render)
    }

     
     
     
     
    func elementLists(_ key: String, _ subKey: String) -> [[String]] {
        guard let array = value(path: [key]) as? [[String: Any]] else { return [] }
        return array.map { element in
            (element[subKey] as? [Any])?.map(Self.render) ?? []
        }
    }

    private static func render(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
             
             
             
             
             
             
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return ""
    }

    func bool(_ key: String) -> Bool { bool(path: [key]) }

    func bool(path: [String]) -> Bool {
        (value(path: path) as? NSNumber)?.boolValue ?? false
    }

    func stringList(_ key: String) -> String {
        stringList(path: [key])
    }

    func stringList(path: [String]) -> String {
        ((value(path: path) as? [String]) ?? []).joined(separator: ", ")
    }

    func setString(
        _ value: String,
        key: String,
        number: Bool = false,
        omitWhenEmpty: Bool = true
    ) {
        setString(value, path: [key], number: number, omitWhenEmpty: omitWhenEmpty)
    }

    func setString(
        _ value: String,
        path: [String],
        number: Bool = false,
        omitWhenEmpty: Bool = true
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if omitWhenEmpty && trimmed.isEmpty {
            set(nil, path: path)
        } else if number, let integer = Int(trimmed) {
            set(integer, path: path)
        } else {
            set(value, path: path)
        }
    }

    func setBool(_ value: Bool, key: String) { setBool(value, path: [key]) }
    func setBool(_ value: Bool, path: [String]) { set(value, path: path) }

    func setStringList(_ value: String, key: String) {
        setStringList(value, path: [key])
    }

    func setStringList(_ value: String, path: [String]) {
        let items = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        set(items.isEmpty ? nil : items, path: path)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func changeType(to typeID: String) {
        if let catalog = ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog,
           ProxyNodeCatalog.knows(typeID, in: catalog) {
            changeType(to: typeID, catalog: catalog)
            return
        }
        let schema = Set(ProxyProtocolEditorSchema.fields(for: typeID).map(\.key))
        guard !schema.isEmpty else {
            setString(typeID, key: "type", omitWhenEmpty: false)
            return
        }
        let kept: Set<String> = ["name", "type", "dialer-proxy"]
        objectWillChange.send()
        for key in mapping.keys where !kept.contains(key) && !schema.contains(key) {
            mapping.removeValue(forKey: key)
        }
        mapping["type"] = typeID
        applyNewTypeDefaults(typeID)
    }

     
     
     
    func applyNewTypeDefaults(_ typeID: String) {
        objectWillChange.send()
        ProxyEditorNewNodeDefaults.applying(to: &mapping, typeID: typeID)
    }

    func replaceJSONValue(_ value: Any?, key: String) { set(value, path: [key]) }

    func replaceJSONValue(_ value: Any?, path: [String]) { set(value, path: path) }

    func hasValue(path: [String]) -> Bool { value(path: path) != nil }

    func removeValue(path: [String]) { set(nil, path: path) }

    func jsonValue(_ key: String) -> String {
        jsonValue(path: [key])
    }

    func jsonValue(path: [String]) -> String {
        guard let value = value(path: path), JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
              ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func value(path: [String]) -> Any? {
        guard !path.isEmpty else { return nil }
        var current: Any = mapping
        for key in path {
            guard let object = current as? [String: Any], let next = object[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private func set(_ value: Any?, path: [String]) {
        guard let first = path.first else { return }
         
         
         
         
         
         
         
        if Self.valuesEqual(self.value(path: path), value) { return }
        objectWillChange.send()
        if path.count == 1 {
            if let value { mapping[first] = value } else { mapping.removeValue(forKey: first) }
            return
        }
        var child = mapping[first] as? [String: Any] ?? [:]
        Self.set(value, path: Array(path.dropFirst()), dictionary: &child)
        if child.isEmpty { mapping.removeValue(forKey: first) } else { mapping[first] = child }
    }

    private static func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (lhs?, rhs?):
            return (lhs as AnyObject).isEqual(rhs)
        }
    }

    private static func set(_ value: Any?, path: [String], dictionary: inout [String: Any]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            if let value { dictionary[first] = value } else { dictionary.removeValue(forKey: first) }
            return
        }
        var child = dictionary[first] as? [String: Any] ?? [:]
        set(value, path: Array(path.dropFirst()), dictionary: &child)
        if child.isEmpty { dictionary.removeValue(forKey: first) } else { dictionary[first] = child }
    }

    private static func json(_ mapping: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(mapping),
              let data = try? JSONSerialization.data(
                withJSONObject: mapping,
                options: [.sortedKeys]
              ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension ProxyNodeEditorDraft {
     
     
     
     
     
    func crossFieldViolations(catalog: ConfigurationFieldCatalog?) -> [ProxyEditorCrossFieldRules.Violation] {
        ProxyEditorCrossFieldRules.violations(
            typeID: typeID,
            value: { self.string($0) },
            nested: { self.string(path: [$0, $1]) },
            hasObject: { self.mapping[$0] is [String: Any] },
            list: { self.list($0) },
            elementLists: { self.elementLists($0, $1) },
            written: { key in
                ProxyEditorFieldChoices.catalogField(forType: self.typeID, key: key, catalog: catalog)
                    .map { $0.isWritten(self.mapping[key].flatMap(ProxyNodeCatalog.json)) }
            }
        )
    }
}

 
 
 
 
 
 
 
 
 
struct ProxyNodeEditorLeaving {
     
    let hasUnsavedEdits: () -> Bool
     
     
     
    let save: (@escaping (ClashDepartureSaveAnswer) -> Void) -> Void
     
    let leave: () -> Void
     
    let ask: () -> Void
     
     
    let sayRefusal: (ClashDisplayText) -> Void

     
    func requestLeave() {
        if hasUnsavedEdits() { ask() } else { leave() }
    }

     
     
     
     
    func saveAndLeave() {
        save { answer in
            if case .refused(let reason?) = answer { sayRefusal(reason) }
        }
    }

    func discardAndLeave() { leave() }
}

 
 
 
private struct ProxyNodeEditorTouchLeaving: ViewModifier {
     
    let asksForItself: Bool
    let saving: Bool
    let saveDisabled: Bool
    @Binding var asksBeforeLeaving: Bool
    let leaving: ProxyNodeEditorLeaving

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .clashBackButtonHidden(asksForItself)
            .clashUnsavedChangesAlert(isPresented: $asksBeforeLeaving, message: .copy("This page has changes that have not been saved."),
                isBusy: saving, saveDisabled: saveDisabled,
                save: { leaving.saveAndLeave() }, discard: { leaving.discardAndLeave() })
            .interactiveDismissDisabled(saving || asksForItself)
             
             
             
            .background(ProxyNodeEditorPullDownAttempts { leaving.pullDownAttempted(saving: saving) })
#else
        content
            .interactiveDismissDisabled(saving)
#endif
    }
}

#if os(iOS)
extension ProxyNodeEditorLeaving {
     
     
     
     
     
    func pullDownAttempted(saving: Bool) {
        if !saving && hasUnsavedEdits() { ask() }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ProxyNodeEditorPullDownAttempts: UIViewRepresentable {
    let attempted: () -> Void

    func makeCoordinator() -> Relay { Relay() }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.relay = context.coordinator
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        context.coordinator.attempted = attempted
        anchor.follow()
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: Relay) {
        coordinator.stand(on: nil)
    }

     
     
    final class Anchor: UIView {
        weak var relay: Relay?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isHidden = true
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            follow()
        }

        func follow() {
            relay?.stand(on: window == nil ? nil : presentation)
        }

         
         
        private var presentation: UIPresentationController? {
            var responder: UIResponder? = self
            while let next = responder, !(next is UIViewController) { responder = next.next }
            guard var controller = responder as? UIViewController else { return nil }
            while let parent = controller.parent { controller = parent }
            guard controller.presentingViewController != nil else { return nil }
            return controller.presentationController
        }
    }

    final class Relay: NSObject, UISheetPresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
        var attempted: () -> Void = {}
        private weak var presentation: UIPresentationController?
         
         
         
        private var original: UIAdaptivePresentationControllerDelegate?

         
         
         
        func stand(on next: UIPresentationController?) {
            if let next, next === presentation, next.delegate === self { return }
            if let presentation, presentation.delegate === self { presentation.delegate = original }
            presentation = nil
            original = nil
            guard let next else { return }
            original = next.delegate
            presentation = next
            next.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
            attempted()
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        override func conforms(to aProtocol: Protocol) -> Bool {
            super.conforms(to: aProtocol) || (original?.conforms(to: aProtocol) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if super.responds(to: aSelector) { return nil }
            return original
        }
    }
}
#endif
 
 
 
 
 
 
 
struct DialerProxyCandidates {
    let groups: [(name: String, type: String)]
    let proxies: [(name: String, type: String)]

    static let empty = DialerProxyCandidates(groups: [], proxies: [])

    static func make(sourceYAML: String?, excluding selfName: String) -> DialerProxyCandidates {
         
         
         
         
         
        let started = DispatchTime.now()
        defer {
            ClashPageProbe.stamp(
                "dialer-candidates",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                ) / 1_000_000
            )
        }
        let model = ProxiesOverviewModel.cached(sourceYAML: sourceYAML)
        return DialerProxyCandidates(
            groups: model.groups
                .filter { $0.name != selfName && !$0.isSynthesized }
                .map { ($0.name, $0.type) },
            proxies: model.proxies
                .filter { $0.name != selfName }
                .map { ($0.name, $0.type) }
        )
    }
}

 
enum ProxyDialerRouting {
     
     
    case payloadField
     
     
     
    case chainAssignment(current: String?, save: (String?) throws -> Void)
}

struct ProxyNodeDetailsView: View {
     
     
     
     
     
     
     
     
     
    var commitTitle: String = "Save"
    let record: ProxyNodeRecord
    let retest: () -> Void
    let saveNode: (String, String) async throws -> Void
     
     
     
     
     
     
    let allowsRename: Bool
     
    let showsTesting: Bool
     
     
    let isNew: Bool
    let dialerRouting: ProxyDialerRouting?
     
     
     
     
     
     
    let dialerCandidates: () -> DialerProxyCandidates
     
     
     
    let subscriptionReset: (() throws -> Void)?
    @State private var confirmsSubscriptionReset = false
     
     
     
     
     
    let onDone: (() -> Void)?
     
     
     
    let drawsClose: Bool

    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale
    @StateObject private var draft: ProxyNodeEditorDraft
     
     
     
     
     
     
    @State private var refusalLine = ""
     
     
    @State private var refusals = 0
     
     
     
    @State private var refusalGoneTo = 0
    @State private var formIsOnScreen = false
     
    @State private var refusedForMissingField: String?
    @State private var errorMessage = ""
    @State private var saving = false
     
    @State private var asksBeforeLeaving = false
     
     
    @State private var fieldCatalog: ConfigurationFieldCatalog?
     
    @State private var pendingType: String?
    @State private var revealsPassword = false
    @State private var revealsObfsPassword = false
    @State private var revealedSecretKeys: Set<String> = []
    @State private var chainDialer: String?

    init(
        record: ProxyNodeRecord,
        retest: @escaping () -> Void,
        saveNode: @escaping (String, String) async throws -> Void,
        allowsRename: Bool = true,
        showsTesting: Bool = true,
        isNew: Bool = false,
        dialerRouting: ProxyDialerRouting? = nil,
        dialerCandidates: @escaping () -> DialerProxyCandidates = { .empty },
        subscriptionReset: (() throws -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        drawsClose: Bool = false,
        commitTitle: String = "Save"
    ) {
        self.commitTitle = commitTitle
        self.drawsClose = drawsClose
        self.record = record
        self.retest = retest
        self.isNew = isNew
        self.saveNode = saveNode
        self.allowsRename = allowsRename
        self.showsTesting = showsTesting
        self.dialerRouting = dialerRouting
        self.dialerCandidates = dialerCandidates
        self.subscriptionReset = subscriptionReset
        self.onDone = onDone
        _draft = StateObject(wrappedValue: ProxyNodeEditorDraft(
            configurationJSON: record.protocolDetails?.configurationJSON ?? "{}",
            fallbackName: record.name,
            fallbackType: record.protocolDetails?.typeID ?? record.type
        ))
        _chainDialer = State(initialValue: {
            if case .chainAssignment(let current, _) = dialerRouting { return current }
            return nil
        }())
    }

    var body: some View {
        editorContainer
        .navigationTitle(isNew ? "Add Node" : "Edit Node")
         
         
        .task {
            if fieldCatalog == nil {
                fieldCatalog = try? await ProfilesViewModel.loadSyntaxCatalog().fieldCatalog
            }
        }
         
         
        .alert(
            ClashCopy.key("Change Proxy Type?"),
            isPresented: Binding(get: { pendingType != nil }, set: { if !$0 { pendingType = nil } }),
            presenting: pendingType
        ) { type in
            Button(role: .destructive) {
                if let fieldCatalog { draft.changeType(to: type, catalog: fieldCatalog) }
                pendingType = nil
            } label: {
                Text(clash: .copy("Change Proxy Type"))
            }
            Button(role: .cancel) { pendingType = nil } label: { Text(clash: .copy("Cancel")) }
        } message: { type in
            if let fieldCatalog {
                 
                Text(clash: .copy("These fields are removed:"))
                    + Text(verbatim: "\n" + ConfigurationValueWords.listJoined(ProxyNodeCatalog.droppedFieldTitles(
                        from: draft.mapping, currentType: draft.typeID, changingTo: type, in: fieldCatalog,
                        copy: fieldCopy, locale: locale), locale: locale))
            }
        }
        .clashDetailPageInsets()
         
         
         
         
         
        .onAppear {
            let appeared = DispatchTime.now()
            DispatchQueue.main.async {
                ClashPageProbe.stamp(
                    "editor-frame-committed",
                    milliseconds: Double(
                        DispatchTime.now().uptimeNanoseconds - appeared.uptimeNanoseconds
                    ) / 1_000_000
                )
            }
        }
        .clashStableNavigationDestination(for: ProxyEditorRoute.self) { route in
            switch route {
            case .dialerProxy:
                if let dialerRouting {
                    DialerProxyPickerView(
                        prepare: dialerCandidates,
                        current: currentDialer
                    ) { selection in
                        applyDialer(selection, routing: dialerRouting)
                    }
                    .clashPushedDetailPage()
                }
            }
        }
         
         
         
         
         
         
        .clashPageProbe("node-editor")
        .accessibilityIdentifier("proxies.nodeEditor.\(draft.typeID)")
        .toolbar {
#if os(iOS)
             
             
             
             
             
            ToolbarItem(placement: .cancellationAction) {
                 
                 
                 
                 
                 
                 
                if asksForItself {
                    Button { leaving.requestLeave() } label: { Text(clash: .copy("Cancel")) }
                        .disabled(saving)
                        .accessibilityIdentifier("proxies.nodeEditor.cancel")
                } else if let onDone, drawsClose || ClashSheetSurface.coversOnThisSystem {
                    ClashSheetCloseButton { onDone() }
                }
            }
#endif
            ToolbarItem(placement: .clashNavigationTrailing) {
                 
                 
                if !insideProductModal {
                    ClashSaveButton(.copy(commitTitle)) { save() }
                        .font(.body.weight(.semibold))
                        .disabled(saveDisabled)
                         
                         
                         
                         
                         
                         
                        .accessibilityValue(missingFieldSentence ?? "")
                        .accessibilityIdentifier("proxies.nodeEditor.save")
                }
            }
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
        .clashRegistersDeparture(
            isDirty: hasUnsavedEdits,
             
             
            currentlyDirty: { [draft, chainDialerChanged, isNew] in
                Self.hasUnsavedEdits(draft: draft, chainDialerChanged: chainDialerChanged, isNew: isNew,
                                     includingOpenPages: true)
            },
            isBusy: saving,
             
             
             
            whySaveIsBlocked: { [draft, fieldCopy, locale] in
                let page = draft.deepestPage
                return page.firstMissingRequiredFieldKey().map {
                    .format("%@ is required.", [
                        ProxyNodeFieldLabel.title(path: [$0], typeID: page.typeID, copy: fieldCopy, locale: locale),
                    ])
                }
            },
            saveAnswering: saveForDeparture,
             
             
            discard: {}
        )
         
         
        .onReceive(draft.objectWillChange) { _ in if !refusalLine.isEmpty { refusalLine = "" } }
        .onChange(of: chainDialer) { _ in if !refusalLine.isEmpty { refusalLine = "" } }
        .disabled(saving)
         
         
         
         
        .modifier(ProxyNodeEditorTouchLeaving(asksForItself: asksForItself, saving: saving, saveDisabled: saveDisabled,
                                              asksBeforeLeaving: $asksBeforeLeaving, leaving: leaving))
        .clashProductModalRoot(title: isNew ? "Add Node" : "Edit Node")
         
         
        .alert(
            ClashCopy.key("Could Not Save"),
            isPresented: Binding(
                get: { !errorMessage.isEmpty },
                set: { if !$0 { errorMessage = "" } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(clash: .copy(errorMessage))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if insideProductModal {
                ClashModalActionBar(
                    primaryTitle: commitTitle,
                    primaryDisabled: saveDisabled,
                     
                     
                     
                     
                     
                    primaryHint: missingFieldSentence,
                    onPrimary: save
                )
            }
        }
    }

    @ViewBuilder
    private var hysteria2Form: some View {
        Section {
            editableRow("Address", key: "server", textContentType: .URL)
             
             
             
             
             
            editableRow("Port", key: "port", number: true)
            editableRow("Port Range", key: "ports", placeholder: "443-8443")
            secretRow("Password", key: "password", reveals: $revealsPassword)
             
             
             
             
             
             
            ProxyStringMenuRow(
                "Obfuscation",
                selection: stringBinding("obfs"),
                values: [""] + ProxyEditorFieldChoices.choices(
                    forType: "hysteria2", key: "obfs", catalog: fieldCatalog
                ),
                identifier: "proxies.nodeEditor.option.obfs"
            ) {
                $0.isEmpty ? .copy("None") : .verbatim(Self.menuLabel($0, key: "obfs", typeID: "hysteria2",
                                                                      catalog: fieldCatalog, copy: fieldCopy, locale: locale))
            }
            if !draft.string("obfs").isEmpty {
                secretRow(
                    "Obfuscation Password",
                    key: "obfs-password",
                    reveals: $revealsObfsPassword
                )
            }
            ProxyNodeDraftNavigationLink(source: draft) { local in
                ProxyTLSEditorView(draft: local)
            } label: {
                valueRow("TLS", "On")
            }
            .accessibilityIdentifier("proxies.nodeEditor.tls")
            valueRow("UDP Relay", "Built in")
        }

        ClashSection("Bandwidth and port hopping") {
            editableRow("Upload Speed", key: "up", placeholder: "auto")
            editableRow("Download Speed", key: "down", placeholder: "auto")
             
             
             
             
             
            editableRow("Hop Interval", key: "hop-interval", placeholder: "15 or 15-30")
        } footer: {
            Text("Leave upload and download empty or set them to 0 to use BBR flow control.")
        }

        ClashSection("Obfuscation packet size") {
            editableRow("Minimum", key: "obfs-min-packet-size", number: true)
            editableRow("Maximum", key: "obfs-max-packet-size", number: true)
        }

        ClashSection("QUIC tuning") {
             
             
            ProxyStringMenuRow(
                "BBR Profile",
                selection: stringBinding("bbr-profile"),
                values: [""] + ProxyEditorFieldChoices.choices(
                    forType: draft.typeID, key: "bbr-profile", catalog: fieldCatalog
                ),
                identifier: "proxies.nodeEditor.option.bbr-profile"
            ) {
                 
                $0.isEmpty ? .copy("Not set") : .verbatim(Self.menuLabel($0, key: "bbr-profile", typeID: draft.typeID,
                                                                         catalog: fieldCatalog, copy: fieldCopy, locale: locale))
            }
            editableRow("CWND", key: "cwnd", number: true)
            editableRow("UDP MTU", key: "udp-mtu", number: true)
            editableRow("Initial Stream Window", key: "initial-stream-receive-window", number: true)
            editableRow("Maximum Stream Window", key: "max-stream-receive-window", number: true)
            editableRow("Initial Connection Window", key: "initial-connection-receive-window", number: true)
            editableRow("Maximum Connection Window", key: "max-connection-receive-window", number: true)
        }

         
         
         
         
        ClashSection("Dialing") {
            editableRow("IP Version", key: "ip-version", placeholder: "dual")
        }

    }

    @ViewBuilder
    private var anyTLSForm: some View {
        Section {
            editableRow("Address", key: "server", textContentType: .URL)
            editableRow("Port", key: "port", number: true)
            secretRow("Password", key: "password", reveals: $revealsPassword)
            ProxyNodeDraftNavigationLink(source: draft) { local in
                ProxyTLSEditorView(draft: local)
            } label: {
                valueRow("TLS", "On")
            }
            .accessibilityIdentifier("proxies.nodeEditor.tls")
            ClashSettingsToggleRow(
                Text("UDP Relay"),
                isOn: boolBinding("udp")
            )
            .accessibilityIdentifier("proxies.nodeEditor.option.udp")
        }

        ClashSection("Session Pool") {
            editableRow("Idle Check Interval", key: "idle-session-check-interval", placeholder: "30", number: true)
            editableRow("Idle Session Timeout", key: "idle-session-timeout", placeholder: "30", number: true)
            editableRow("Minimum Idle Sessions", key: "min-idle-session", placeholder: "0", number: true)
        } footer: {
            Text("Seconds.")
        }

        ClashSection("Dialing") {
            ClashSettingsToggleRow(
                Text("TCP Fast Open"),
                isOn: boolBinding("tfo")
            )
            .accessibilityIdentifier("proxies.nodeEditor.option.tfo")
            ClashSettingsToggleRow(
                Text("Multipath TCP"),
                isOn: boolBinding("mptcp")
            )
            .accessibilityIdentifier("proxies.nodeEditor.option.mptcp")
            editableRow("IP Version", key: "ip-version", placeholder: "dual")
        }

    }

    @ViewBuilder
    private var genericForm: some View {
        if !editableKeys.isEmpty {
            ClashSection("Configured Options") {
                ForEach(editableKeys, id: \.self) { key in
                    genericRow(key)
                }
            }
        }
        if supportsTLS {
            ClashSection("Security") {
                ProxyNodeDraftNavigationLink(source: draft) { local in
                    ClashLazyView {
                        ProxyTLSEditorView(draft: local)
                    }
                } label: {
                    valueRow("TLS", tlsStateTitle)
                }
                .accessibilityIdentifier("proxies.nodeEditor.tls")
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
    private var editableKeys: [String] {
        Self.editableKeys(typeID: draft.typeID, mapping: draft.mapping, catalog: fieldCatalog)
    }

     
     
     
     
     
     
    static func editableKeys(typeID: String, mapping: [String: Any], catalog: ConfigurationFieldCatalog?) -> [String] {
#if os(macOS)
         
         
         
        let plan = Self.keyPlan(for: typeID)
        let hidden = plan.hidden
        let schemaKeys = plan.schemaFields
        let defaultKeys = plan.defaultKeys
#else
        let hidden = dedicatedKeys(typeID: typeID)
            .union(ProxyEditorFieldOwnership.dedicatedSections)
            .union(ProxyEditorHiddenFields.platformUnsupported)
        let schemaKeys = ProxyProtocolEditorSchema.fields(for: typeID)
        let defaultKeys = ProxyEditorDefaultFields.keys(for: typeID)
#endif
         
         
         
        let decided = ProxyNodeCatalog.platformDecidedKeys(of: mapping, typeID: typeID, in: catalog)
        var keys: [String] = []
        var seen = Set<String>()
        for key in defaultKeys
        where !hidden.contains(key) && !decided.contains(key) && key != "name" {
            if seen.insert(key).inserted { keys.append(key) }
        }
        for field in schemaKeys where !hidden.contains(field.key) && !decided.contains(field.key) {
            let present = mapping[field.key] != nil
            if (field.required || present), field.key != "name",
               seen.insert(field.key).inserted {
                keys.append(field.key)
            }
        }
        let extras = mapping.keys
            .filter { !hidden.contains($0) && !decided.contains($0) && !seen.contains($0) && $0 != "name" }
#if os(macOS)
             
             
             
            .filter { !plan.schemaKeySet.contains($0) }
#else
            .filter { key in !schemaKeys.contains { $0.key == key } }
#endif
            .sorted()
        return keys + extras
    }

     
     
     
     
    @ViewBuilder
    private var editorSections: some View {
        ClashSection("Identity") {
             
             
             
             
             
             
             
             
             
             
            if let macProxyTypeRow = ProxyNodeEditorMacOverrides.proxyTypeRow {
                 
                 
                 
                 
                 
                macProxyTypeRow(draft, isNew, fieldCatalog, $pendingType)
            } else {
                 
                 
                 
                 
                ProxyNodeTypePicker(draft: draft, catalog: fieldCatalog, isNew: isNew, pendingType: $pendingType)
            }

             
             
             
             
             
             
             
             
             
             
             
             
             
            if isNew || allowsRename {
                ClashFieldRow(
                    "Name",
                    hint: "Required",
                    text: stringBinding("name"),
                    identifier: "proxies.nodeEditor.name"
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } else {
                valueRow("Name", .verbatim(draft.string("name")))
            }
        }

        if draft.typeID == "hysteria2" {
            hysteria2Form
        } else if draft.typeID == "anytls" {
            anyTLSForm
        } else {
            genericForm
        }

        dialerProxySection

         
         
         
         
         
         
         
         
         
        if !refusalLine.isEmpty {
            ClashStatusMessage(text: .verbatim(refusalLine), kind: .error)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("proxies.nodeEditor.refusal")
                .id(Self.refusalRowID)
        }
         
         
         
         
        if !insideProductModal, !refusalIsTheMissingField, let sentence = missingFieldSentence {
            Text(clash: .verbatim(sentence))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                 
                 
                .accessibilityHidden(true)
        }

        if showsTesting || record.failureMessage != nil {
            ClashSection("Latency Test") {
                valueRow("Latency", delayTitle)
                 
                 
                 
                if let message = record.failureMessage {
                    Text(verbatim: message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("proxies.nodeEditor.failure")
                }
                if showsTesting {
                    Button(action: retest) {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            Label(
                                "Retest Latency",
                                systemImage: ClashSymbol.speedometer.name
                            )
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("proxies.nodeEditor.retest")
                }
            }
        }

        moreFieldsSection

         
         
         
         
         
         
         
         
    }

     
     
    @ViewBuilder
    private var editorContainer: some View {
         
         
         
         
         
         
         
        ScrollViewReader { proxy in
            let reveal = {
                guard formIsOnScreen, refusals != refusalGoneTo, !refusalLine.isEmpty else { return }
                refusalGoneTo = refusals
                withAnimation { proxy.scrollTo(Self.refusalRowID, anchor: .center) }
            }
            editorForm
                .onChange(of: refusals) { _ in reveal() }
                .clashOnScreen { onScreen in
                    formIsOnScreen = onScreen
                    reveal()
                }
        }
    }

    static let refusalRowID = "proxies.nodeEditor.refusal.row"

    @ViewBuilder
    private var editorForm: some View {
        if let macEditorContainer = ProxyNodeEditorMacOverrides.editorContainer {
             
             
             
            macEditorContainer(AnyView(Group {
                if subscriptionReset != nil {
                    subscriptionSection
                }
                editorSections
            }))
        } else {
            Form {
                if subscriptionReset != nil {
                    subscriptionSection
                }
                editorSections
            }
            .clashInsetGroupedListStyle()
        }
    }

     
     
     
    private var subscriptionSection: some View {
        Section {
            Text(clash: .copy("Edited from the profile URL"))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("proxies.nodeEditor.overridden")
            Button(role: .destructive) {
                confirmsSubscriptionReset = true
            } label: {
                Text(clash: .copy("Reset to Profile URL"))
            }
            .accessibilityIdentifier("proxies.nodeEditor.reset")
            .alert("Reset to Profile URL", isPresented: $confirmsSubscriptionReset) {
                Button("Reset to Profile URL", role: .destructive) {
                    do {
                        try subscriptionReset?()
                         
                         
                         
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onDone?()
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(clash: .copy("The profile URL's own values come back; the edit is discarded."))
            }
        }
    }

#if os(macOS)
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private struct ProtocolKeyPlan {
        let hidden: Set<String>
        let schemaFields: [ProxyEditorSchemaField]
        let schemaKeySet: Set<String>
        let defaultKeys: [String]
    }

    nonisolated(unsafe) private static var keyPlans: [String: ProtocolKeyPlan] = [:]
    private static let keyPlanLock = NSLock()

    private static func keyPlan(for typeID: String) -> ProtocolKeyPlan {
        keyPlanLock.lock()
        defer { keyPlanLock.unlock() }
        if let hit = keyPlans[typeID] { return hit }
        let schemaFields = ProxyProtocolEditorSchema.fields(for: typeID)
         
         
        let plan = ProtocolKeyPlan(
            hidden: Set(["name", "type"])
                .union(ProxyEditorFieldOwnership.tlsKeys(typeID: typeID))
                .union(ProxyEditorFieldOwnership.dedicatedSections)
                .union(ProxyEditorHiddenFields.platformUnsupported),
            schemaFields: schemaFields,
            schemaKeySet: Set(schemaFields.map(\.key)),
            defaultKeys: ProxyEditorDefaultFields.keys(for: typeID)
        )
        keyPlans[typeID] = plan
        return plan
    }
#endif

     
     
     
     
     
    static func menuLabel(_ value: String, key: String, typeID: String, catalog: ConfigurationFieldCatalog?,
                          copy: ConfigurationFieldCopy, locale: Locale) -> String {
        copy.valueLabel(value, for: ProxyEditorFieldChoices.catalogField(forType: typeID, key: key, catalog: catalog),
                        locale: locale) ?? value
    }

    private func isRequiredKey(_ key: String) -> Bool {
        ProxyProtocolEditorSchema.fields(for: draft.typeID)
            .first { $0.key == key }?.required ?? false
    }

     
     
     
     
    @ViewBuilder
    private var moreFieldsSection: some View {
        Section {
            ProxyNodeDraftNavigationLink(source: draft) { local in
                ProxyNodeMoreFieldsPage(draft: local)
            } label: {
                Text(clash: .copy("More Fields"))
            }
            .accessibilityIdentifier("proxies.nodeEditor.more-fields")
        }
    }

    private var supportsTLS: Bool {
        ProxyEditorFieldOwnership.supportsTLS(typeID: draft.typeID)
    }

    private var tlsStateTitle: ClashDisplayText {
        if ProxyProtocolEditorSchema.supports("tls", typeID: draft.typeID) {
            return draft.bool("tls") ? "On" : "Off"
        }
        return "On"
    }

    private static func dedicatedKeys(typeID: String) -> Set<String> {
         
         
         
         
         
         
         
        return Set(["name", "type"])
            .union(ProxyEditorFieldOwnership.tlsKeys(typeID: typeID))
    }

    @ViewBuilder
    private func genericRow(_ key: String) -> some View {
         
         
         
         
         
        if let managed = ProxyEditorPlatformNotes.clientManagedNote(forKey: key) {
             
             
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                valueRow(humanLabel(key), .copy("Automatic"))
                 
                Text(clash: .copy(managed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if key == "username",
                  ProxyNodeEditorSecretFields.plainUsernameTypes
                      .contains(draft.typeID.lowercased()) {
            editableRow(
                humanLabel(key),
                key: key,
                placeholder: isRequiredKey(key) ? "Required" : "Optional",
                identifier: "proxies.nodeEditor.option.\(key)"
            )
        } else if !ProxyEditorFieldChoices.choices(
            forType: draft.typeID, key: key, catalog: fieldCatalog
        ).isEmpty {
             
             
            ProxyStringMenuRow(
                humanLabel(key),
                selection: stringBinding(key),
                values: ProxyEditorMenuOptions.values(
                    choices: ProxyEditorFieldChoices.choices(
                        forType: draft.typeID,
                        key: key,
                        catalog: fieldCatalog
                    ),
                    isRequired: isRequiredKey(key)
                ),
                identifier: "proxies.nodeEditor.option.\(key)"
            ) {
                $0.isEmpty
                    ? .copy(isRequiredKey(key) ? "Required" : "Not set")
                    : .verbatim(Self.menuLabel($0, key: key, typeID: draft.typeID, catalog: fieldCatalog,
                                               copy: fieldCopy, locale: locale))
            }
        } else if let field = ProxyProtocolEditorSchema.fields(for: draft.typeID)
            .first(where: { $0.key == key }),
            field.editorControlKind != .text,
            !isSecret(key) {
            ProxySchemaFieldRow(
                draft: draft,
                field: field,
                pathPrefix: [],
                identifierOverride: "proxies.nodeEditor.option.\(key)",
                 
                 
                 
                 
                 
                 
                valueName: { [typeID = draft.typeID, fieldCopy, locale] in
                    .verbatim(Self.menuLabel($0, key: key, typeID: typeID,
                                             catalog: ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog,
                                             copy: fieldCopy, locale: locale))
                }
            )
        } else if draft.mapping[key] is Bool || draft.mapping[key] is NSNumber
            && CFGetTypeID(draft.mapping[key] as CFTypeRef) == CFBooleanGetTypeID() {
            ClashSettingsToggleRow(
                Text(humanLabel(key)),
                isOn: boolBinding(key)
            )
            .accessibilityIdentifier("proxies.nodeEditor.option.\(key)")
        } else if isSecret(key) {
            secretRow(
                humanLabel(key),
                key: key,
                reveals: Binding(
                    get: { revealedSecretKeys.contains(key) },
                    set: { shown in
                        if shown { revealedSecretKeys.insert(key) }
                        else { revealedSecretKeys.remove(key) }
                    }
                ),
                placeholder: isRequiredKey(key) ? "Required" : "Optional",
                identifier: "proxies.nodeEditor.option.\(key)"
            )
        } else if draft.mapping[key] is [Any] || draft.mapping[key] is [String: Any] {
            ProxyNodeDraftNavigationLink(source: draft) { local in
                ProxyJSONValueEditorView(draft: local, key: key)
            } label: {
                valueRow(humanLabel(key), "Edit")
            }
        } else {
            editableRow(
                humanLabel(key),
                key: key,
                placeholder: isRequiredKey(key) ? "Required" : "Optional",
                number: draft.mapping[key] is NSNumber,
                identifier: "proxies.nodeEditor.option.\(key)"
            )
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func isDocumentField(_ key: String, typeID: String) -> Bool {
        let key = key.lowercased()
        guard documentKeys.contains(key) else { return false }
        return !fixedWidthKeyFields.contains("\(typeID.lowercased()).\(key)")
    }

     
     
    private static let fixedWidthKeyFields: Set<String> = [
        "wireguard.private-key",
    ]

    static let documentKeys: Set<String> = [
        "ca", "certificate", "private-key", "client-certificate", "client-key",
        "tls-cert", "tls-key",
         
         
        "cert", "key", "tls-auth", "tls-crypt", "tls-crypt-v2",
    ]

     
     
     
     
     
     
     
     
    private func editableRow(
        _ label: String,
        key: String,
        placeholder: String? = nil,
        number: Bool = false,
        textContentType: UITextContentType? = nil,
        identifier: String? = nil
    ) -> some View {
        let identifier = identifier ?? "proxies.nodeEditor.option.\(key)"
         
         
         
        let placeholder = placeholder ?? ProxyEditorFieldHint.text(
            forKey: key, typeID: draft.typeID
        )
#if os(macOS)
        return VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            if Self.isDocumentField(key, typeID: draft.typeID) {
                ProxyDocumentFieldRow(
                    title: label,
                    hint: placeholder,
                    text: stringBinding(key, number: number),
                    identifier: identifier
                )
            } else {
                let binding = stringBinding(key, number: number)
                ClashFieldRow(
                    label,
                    hint: placeholder,
                    text: binding,
                    suffix: ProxyEditorFieldUnits.displayUnit(
                        forKey: key,
                        value: binding.wrappedValue
                    ),
                    compactValue: ProxyEditorFieldUnits.unit(forKey: key)
                        != nil,
                    identifier: identifier
                )
                .textContentType(textContentType)
                .keyboardType(number ? .numbersAndPunctuation : .default)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .id(identifier)
            }
        }
#else
         
         
        return VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            if Self.isDocumentField(key, typeID: draft.typeID) {
                 
                 
                 
                 
                 
                 
                ProxyDocumentFieldRow(
                    title: label,
                    hint: placeholder,
                    text: stringBinding(key, number: number),
                    identifier: identifier
                )
            } else {
            HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.standard) {
                Text(clash: .copy(label))
                Spacer(minLength: ClashTheme.Spacing.compact)
                 
                 
                 
                ClashValueField(
                    hint: placeholder,
                    label: label,
                    text: stringBinding(key, number: number)
                )
                    .textContentType(textContentType)
                    .keyboardType(number ? .numbersAndPunctuation : .default)
                    .multilineTextAlignment(.trailing)
                     
                     
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier(identifier)
            }
            }
        }
        .accessibilityElement(children: .contain)
#endif
    }

     
     
    private func secretRow(
        _ label: String,
        key: String,
        reveals: Binding<Bool>,
        placeholder: String? = nil,
        identifier: String? = nil
    ) -> some View {
        let identifier = identifier ?? "proxies.nodeEditor.option.\(key)"
         
         
         
        let placeholder = placeholder ?? ProxyEditorFieldHint.text(
            forKey: key, typeID: draft.typeID
        )
#if os(macOS)
        return Group {
            if Self.isDocumentField(key, typeID: draft.typeID) {
                ProxyRevealingFieldRow(
                    title: label,
                    hint: placeholder,
                    text: stringBinding(key),
                    reveals: reveals,
                    multiline: true,
                    identifier: identifier
                )
            } else {
                ClashFieldRow(
                    label,
                    hint: placeholder,
                    text: stringBinding(key),
                    secure: true,
                    reveals: reveals,
                    monospaced: true,
                    identifier: identifier
                )
                 
                 
                 
                 
                .id(identifier)
                .textContentType(.oneTimeCode)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
            }
        }
#else
         
         
         
         
         
        return ProxyRevealingFieldRow(
            title: label,
            hint: placeholder,
            text: stringBinding(key),
            reveals: reveals,
            multiline: Self.isDocumentField(key, typeID: draft.typeID),
            identifier: identifier
        )
#endif
    }

     
     
    private func valueRow(_ label: String, _ value: ClashDisplayText) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(clash: .copy(label))
            Spacer(minLength: ClashTheme.Spacing.standard)
            Text(clash: value.isBlank ? .copy("Not set") : value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
    }

    private func stringBinding(_ key: String, number: Bool = false) -> Binding<String> {
        Binding(
            get: { draft.string(key) },
             
             
            set: { draft.setString($0, key: key, number: number, omitWhenEmpty: false) }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { draft.bool(key) }, set: { draft.setBool($0, key: key) })
    }

    private var protocolDisplayName: String {
        ProxyProtocolCatalog.specification(for: draft.typeID)?.displayName ?? draft.typeID
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private var delayTitle: ClashDisplayText {
        if let category = record.failureCategory, record.delay.map({ $0 <= 0 }) ?? true {
            return .copy(ClashProbeFailureCopy.badge(for: category))
        }
        guard let delay = record.delay else { return .copy("Not tested") }
        return delay > 0 ? .verbatim("\(delay) ms") : .copy(ClashProbeFailureCopy.neutralBadge)
    }

     
     
     
    @ViewBuilder
    private var dialerProxySection: some View {
        if let dialerRouting {
            ClashSection("Routing") {
                ClashStableNavigationLink(value: ProxyEditorRoute.dialerProxy) {
                    DialerProxyPickerView(
                        prepare: dialerCandidates,
                        current: currentDialer
                    ) { selection in
                        applyDialer(selection, routing: dialerRouting)
                    }
                    .clashPushedDetailPage()
                } label: {
                    valueRow("Dialer Proxy", currentDialer.map(ClashDisplayText.verbatim) ?? .copy("Not set"))
                }
                .accessibilityIdentifier("proxies.nodeEditor.dialer-proxy")
            }
        }
    }

    private var currentDialer: String? {
        guard let dialerRouting else { return nil }
        switch dialerRouting {
        case .payloadField:
            let value = draft.string("dialer-proxy")
            return value.isEmpty ? nil : value
        case .chainAssignment:
            return chainDialer
        }
    }

    private func applyDialer(_ selection: String?, routing: ProxyDialerRouting) {
        switch routing {
        case .payloadField:
            draft.setString(selection ?? "", key: "dialer-proxy")
        case .chainAssignment:
             
             
            chainDialer = selection
        }
    }

    private var chainDialerChanged: Bool {
        guard case .chainAssignment(let current, _) = dialerRouting else { return false }
        return chainDialer != current
    }

     
     
    private var refusalIsTheMissingField: Bool {
        guard !refusalLine.isEmpty, let refused = refusedForMissingField else { return false }
        return refused == draft.firstMissingRequiredFieldKey()
    }

     
     
     
     
     
     
    private var missingFieldSentence: String? {
        draft.firstMissingRequiredFieldKey().map {
            ClashCopy.string(for: .format("Needs %@", [humanLabel($0)]), locale: locale)
        }
    }

     
     
     
     
    static func hasUnsavedEdits(draft: ProxyNodeEditorDraft, chainDialerChanged: Bool, isNew: Bool,
                                includingOpenPages: Bool = false) -> Bool {
        (includingOpenPages ? draft.isDirtyIncludingOpenPages : draft.isDirty)
            || chainDialerChanged
            || (isNew && draft.holdsMoreThanABlankNode)
    }

    private var hasUnsavedEdits: Bool {
        Self.hasUnsavedEdits(draft: draft, chainDialerChanged: chainDialerChanged, isNew: isNew)
    }

     
     
     
     
     
     
    private var asksForItself: Bool { hasUnsavedEdits }

     
     
     
    static let afterTheQuestionHasGone: TimeInterval = 0.4

     
     
    private var leaving: ProxyNodeEditorLeaving {
        ProxyNodeEditorLeaving(
            hasUnsavedEdits: { [draft, chainDialerChanged, isNew] in
                Self.hasUnsavedEdits(draft: draft, chainDialerChanged: chainDialerChanged, isNew: isNew)
            },
            save: saveForDeparture,
            leave: leaveEditor,
            ask: { asksBeforeLeaving = true },
            sayRefusal: { [locale] reason in
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterTheQuestionHasGone) {
                    errorMessage = ClashCopy.string(for: reason, locale: locale)
                }
            }
        )
    }

     
     
     
    private func leaveEditor() {
        if let onDone {
             
             
            onDone()
        } else {
#if os(macOS)
            if let popRoute { popRoute(ClashPopToken()) }
            else { presentationMode.wrappedValue.dismiss() }
#else
            presentationMode.wrappedValue.dismiss()
#endif
        }
    }

    private var saveDisabled: Bool {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        Self.saveIsDisabled(
            isNew: isNew,
            isDirty: draft.isDirty,
            chainDialerChanged: chainDialerChanged,
            missingRequiredFieldKey: draft.firstMissingRequiredFieldKey()
        )
    }

     
    static func saveIsDisabled(
        isNew: Bool,
        isDirty: Bool,
        chainDialerChanged: Bool,
        missingRequiredFieldKey: String?
    ) -> Bool {
        if missingRequiredFieldKey != nil { return true }
        if isNew { return false }
        return !isDirty && !chainDialerChanged
    }

    private func save() { saveAnswering(fromTheQuestion: false) { _ in } }

     
     
     
     
     
     
     
     
    private func saveForDeparture(_ answer: @escaping (ClashDepartureSaveAnswer) -> Void) {
        refusalLine = ""
        refusedForMissingField = nil
        if let refusal = draft.absorbOpenPages() {
#if os(iOS)
             
#else
            refusalLine = ClashCopy.string(for: refusal, locale: locale)
            refusals += 1
#endif
            answer(.refused(refusal))
            return
        }
        saveAnswering(fromTheQuestion: true, answer)
    }

     
     
     
     
    private func saveAnswering(
        fromTheQuestion: Bool,
        _ answer: @escaping (ClashDepartureSaveAnswer) -> Void
    ) {
        guard !saving else { answer(.refused(nil)); return }
         
         
        errorMessage = ""
        refusalLine = ""
        refusedForMissingField = nil
        let refuse: (ClashDisplayText) -> Void = { reason in
            let said = ClashCopy.string(for: reason, locale: locale)
            if fromTheQuestion {
#if os(iOS)
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
#else
                refusalLine = said
                refusals += 1
#endif
                answer(.refused(reason))
            } else {
                errorMessage = said
                answer(.refused(nil))
            }
        }
        do {
            try validate()
        } catch {
            if case ProxyNodeEditorError.missingField(_, let key) = error { refusedForMissingField = key }
            refuse(Self.reason(for: error))
            return
        }
        saving = true
         
         
         
         
         
#if os(macOS)
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
#else
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
#endif
        Task { @MainActor in
            let failure = await finishSave()
            saving = false
             
            if let failure { refuse(.copy(failure)) } else { answer(.saved) }
        }
    }

     
     
     
    private static func reason(for error: Error) -> ClashDisplayText {
        guard let refusal = error as? ProxyNodeEditorError else {
            return .copy(error.localizedDescription)
        }
        return refusal.displayText
    }

     
    private func finishSave() async -> String? {
        do {
            if draft.isDirty || isNew {
                 
                 
                 
                 
                 
                try await saveNode(draft.originalJSON, Self.strippingEmptyStrings(draft.editedJSON))
            }
            if case .chainAssignment(_, let saveAssignment) = dialerRouting,
               chainDialerChanged {
                try saveAssignment(chainDialer)
            }
            leaveEditor()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

     
     
    static func strippingEmptyStrings(_ json: String) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              var root = value as? [String: Any] else { return json }
        root = root.filter { !(($0.value as? String)?.isEmpty ?? false) }
        for (key, nested) in root {
            if var child = nested as? [String: Any] {
                child = child.filter { !(($0.value as? String)?.isEmpty ?? false) }
                if child.isEmpty { root.removeValue(forKey: key) } else { root[key] = child }
            }
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.sortedKeys]
        ) else { return json }
        return String(decoding: data, as: UTF8.self)
    }

    private func validate() throws {
         
         
        if let key = draft.firstMissingRequiredFieldKey() {
            throw ProxyNodeEditorError.missingField(humanLabel(key), key: key)
        }
         
         
         
        if let violation = draft.crossFieldViolations(catalog: fieldCatalog).first {
            throw ProxyNodeEditorError.refusedCombination(violation.message)
        }
         
         
         
         
         
         
         
         
         
         
         
        if let key = ProxyEditorNumericFields.firstNonNumeric(
            typeID: draft.typeID,
            mapping: draft.mapping
        ) {
            throw ProxyNodeEditorError.notANumber(humanLabel(key))
        }
    }

     
     
     
    private func humanLabel(_ key: String) -> String {
        ProxyNodeFieldLabel.title(path: [key], typeID: draft.typeID, copy: fieldCopy, locale: locale)
    }

    private static let secretKeys = ProxyNodeEditorSecretFields.keys

     
     
     
     
     
     
     
     
     
    private func isSecret(_ key: String) -> Bool {
        let lowered = key.lowercased()
        guard Self.secretKeys.contains(lowered) else { return false }
        let type = draft.typeID.lowercased()
        if lowered == "auth",
           ProxyNodeEditorSecretFields.plaintextAuthTypes.contains(type) {
            return false
        }
        if lowered == "username",
           ProxyNodeEditorSecretFields.plainUsernameTypes.contains(type) {
            return false
        }
        return true
    }


}

private enum ProxyNodeEditorError: LocalizedError {
    case missingServer
    case missingPort
    case missingPassword
     
    case missingField(String, key: String)
     
     
    case refusedCombination(String)
     
    case notANumber(String)

    var errorDescription: String? { displayText.rawValue }

     
     
    var displayText: ClashDisplayText {
        switch self {
        case .refusedCombination(let message): return .copy(message)
        case .missingField(let label, _): return .format("%@ is required.", [label])
        case .notANumber(let label): return .format("%@ must be a number.", [label])
        case .missingServer: return .copy("Enter the proxy server address.")
        case .missingPort: return .copy("Enter a port or port range.")
        case .missingPassword: return .copy("Enter the Hysteria 2 password.")
        }
    }
}

 
enum DialerProxyRowTitle {
     
    static let none: ClashDisplayText = .copy("None")

     
     
    static func candidate(_ name: String) -> ClashDisplayText { .verbatim(name) }
}

private struct DialerProxyPickerView: View {
     
     
     
     
     
     
     
     
     
     
     
     
    let prepare: () -> DialerProxyCandidates
    let current: String?
    let pick: (String?) -> Void

    @State private var candidates: DialerProxyCandidates?

     
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.locale) private var locale

     
     
     
     
     
     
     
     
    @ViewBuilder
    private func dialerSeat<C: View>(
        @ViewBuilder _ content: @escaping () -> C
    ) -> some View {
#if os(macOS)
        List {
            content()
        }
        .listStyle(.inset)
         
         
        .environment(\.defaultMinListRowHeight, 0)
#else
        ProxyEditorSeat {
            content()
        }
#endif
    }

     
     
     
    var body: some View {
        pageBody.clashCapturesDismiss(dismiss)
    }
    @ViewBuilder
    private var pageBody: some View {
         
         
         
         
         
         
         
         
         
#if os(macOS)
         
         
         
         
         
        if let candidates {
            ClashRulePolicyPickerView(
                title: "Dialer Proxy",
                builtIns: [(
                    name: "None",
                    caption: ""
                )],
                builtInsTitle: nil,
                axPrefix: "dialer-proxy",
                offersGlobal: false,
                options: ClashRulePolicyOptions(
                    groups: candidates.groups.map {
                        ClashRulePolicySnapshot(name: $0.name, type: $0.type)
                    },
                    proxies: candidates.proxies.map {
                        ClashRulePolicySnapshot(name: $0.name, type: $0.type)
                    }
                ),
                current: current ?? "None",
                icon: { symbol in Image(systemName: symbol.name) },
                pick: { name in
                    pick(name == "None" ? nil : name)
                }
            )
            .task(prepareTask)
            .onAppear(perform: stampFirstFrame)
        } else {
            dialerSeat {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("proxies.nodeEditor.dialer-proxy.loading")
                }
            }
            .clashProductModalChild(title: "Dialer Proxy")
            .task(prepareTask)
        }
#else
        dialerSeat {
             
             
             
            Section {
                Text(ClashCopy.key(
                    "This node connects out through the group or proxy you pick here. None connects directly."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)

                 
                 
                row(title: DialerProxyRowTitle.none, value: nil)
            }
            if let candidates {
                if !candidates.groups.isEmpty {
                    Section {
                        ForEach(candidates.groups, id: \.name) { group in
                            row(title: DialerProxyRowTitle.candidate(group.name), value: group.name, caption: group.type)
                        }
                    } header: {
                        Text(clash: .copy("Groups"))
                    }
                }
                if !candidates.proxies.isEmpty {
                    Section {
                        ForEach(candidates.proxies, id: \.name) { proxy in
                            row(title: DialerProxyRowTitle.candidate(proxy.name), value: proxy.name, caption: proxy.type)
                        }
                    } header: {
                        Text(clash: .copy("Proxies"))
                    }
                }
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("proxies.nodeEditor.dialer-proxy.loading")
                }
            }
        }
        .task(prepareTask)
         
         
         
        .onAppear(perform: stampFirstFrame)
        .clashPageTitle("Dialer Proxy")
        .clashPageProbe("dialer-proxy")
        .clashDetailPageInsets()
        .accessibilityIdentifier("proxies.nodeEditor.dialer-proxy.picker")
        .clashProductModalChild(title: "Dialer Proxy")
#endif
    }

     
    @Sendable
    private func prepareTask() async {
         
         
         
        guard candidates == nil else { return }
        let build = prepare
        candidates = await Task.detached(priority: .userInitiated) {
            build()
        }.value
    }

     
     
     
    private func stampFirstFrame() {
        let appeared = DispatchTime.now()
        DispatchQueue.main.async {
            ClashPageProbe.stamp(
                "dialer-proxy-frame-committed",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - appeared.uptimeNanoseconds
                ) / 1_000_000
            )
        }
    }

    private func row(title: ClashDisplayText, value: String?, caption: String? = nil) -> some View {
        Button {
            pick(value)
             
             
#if os(macOS)
            if let popRoute {
                popRoute(ClashPopToken())
            } else {
                dismiss()
            }
#else
             
             
             
            dismiss()
#endif
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(clash: title).foregroundStyle(.primary)
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: ClashTheme.Spacing.compact)
                ClashSelectionMark(isSelected: current == value)
            }
            .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dialer-proxy.\(value ?? "none")")
    }
}

 
 
 
 
 
struct ProxyNodePendingText {
    let isPending: () -> Bool
    let apply: () -> ClashDisplayText?
}

 
 
 
 
 
enum ProxyEditorRoute: Hashable {
    case dialerProxy
}

 
 
 
 
 
 
 
 
 
struct ProxyNodeDraftNavigationLink<
    Destination: View,
    Label: View
>: View {
    @ObservedObject private var source: ProxyNodeEditorDraft
    private let destination: (ProxyNodeEditorDraft) -> Destination
    private let label: () -> Label

#if os(macOS)
    @StateObject private var local: ProxyNodeEditorDraft
#endif

    init(
        source: ProxyNodeEditorDraft,
        @ViewBuilder destination: @escaping (
            ProxyNodeEditorDraft
        ) -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.source = source
        self.destination = destination
        self.label = label
#if os(macOS)
        _local = StateObject(wrappedValue: source.detachedCopy())
#endif
    }

    @ViewBuilder
    var body: some View {
#if os(macOS)
        ClashRoutedViewLink(
            onNavigate: prepare,
            onReturn: commit
        ) {
            destination(local)
        } label: {
            label()
        }
#else
        ClashRoutedViewLink {
            destination(source)
        } label: {
            label()
        }
#endif
    }

#if os(macOS)
    private func prepare() {
        local.prepare(from: source)
        source.openPage = local
    }

    private func commit() {
        source.synchronize(from: local)
        if source.openPage === local { source.openPage = nil }
    }
#endif
}

 
 
 
 
 
enum ProxyTypeGrouping {
     
    static let commonTypeIDs = [
        "ss", "vmess", "vless", "trojan", "hysteria2", "tuic", "wireguard", "socks5",
    ]

     
     
    static let nonServerTypeIDs: Set<String> = [
        "direct", "dns", "reject", "rematch",
    ]
}

 
 
 
 
 
 
 
enum ProxyNodeEditorMacOverrides {
    nonisolated(unsafe) static var proxyTypeRow:
        ((ProxyNodeEditorDraft, _ hidesNonServerTypes: Bool, _ catalog: ConfigurationFieldCatalog?,
          _ pendingType: Binding<String?>) -> AnyView)?

     
     
     
     
     
    nonisolated(unsafe) static var editorContainer: ((AnyView) -> AnyView)?

     
     
     
    nonisolated(unsafe) static var entryPage:
        ((ProxyNodeEditorDraft, _ path: [String], _ field: ConfigurationField, _ title: String) -> AnyView)?
}

 
 
 
 
 
 
 
 
 
 
struct ProxyEditorSeat<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let macEditorContainer = ProxyNodeEditorMacOverrides.editorContainer {
            macEditorContainer(AnyView(content()))
        } else {
            Form {
                content()
            }
            .clashInsetGroupedListStyle()
        }
    }
}

private extension View {
    @ViewBuilder
    func optionalProxyAccessibilityIdentifier(
        _ identifier: String?
    ) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

 
 
 
private enum ProxyNodeFieldLabel {
     
     
     
     
    @MainActor
    static func title(path: [String], typeID: String, copy: ConfigurationFieldCopy, locale: Locale) -> String {
        let language = ConfigurationFieldCopy.Language(locale: locale)
        let tail = path.joined(separator: ".")
        return copy.entry(forPath: ProxyNodeCatalog.typePath(typeID) + "." + tail, language: language)?.title
            ?? copy.entry(forPath: "proxies[*]." + tail, language: language)?.title
            ?? text(for: path.last ?? tail)
    }

    private static let replacements = [
        "addr": "Address",
        "alpn": "ALPN",
        "auth": "Authentication",
        "bbr": "BBR",
        "ca": "CA",
        "cdn": "CDN",
        "cert": "Certificate",
        "cwnd": "CWND",
        "dns": "DNS",
        "ech": "ECH",
        "grpc": "gRPC",
        "h2": "H2",
        "http": "HTTP",
        "id": "ID",
        "ip": "IP",
        "ipv4": "IPv4",
        "ipv6": "IPv6",
        "jls": "JLS",
        "max": "Maximum",
        "mkcp": "mKCP",
        "min": "Minimum",
        "mptcp": "MPTCP",
        "mtu": "MTU",
        "nat": "NAT",
        "opts": "Options",
        "param": "Parameter",
        "quic": "QUIC",
        "rtt": "RTT",
        "smux": "SMUX",
        "sni": "SNI",
        "ssh": "SSH",
        "str": "String",
        "down": "Download",
        "tcp": "TCP",
        "tfo": "TFO",
        "tls": "TLS",
        "tlsmirror": "TLS Mirror",
        "udp": "UDP",
        "up": "Upload",
        "uri": "URI",
        "url": "URL",
        "uuid": "UUID",
        "ws": "WebSocket",
        "xudp": "XUDP",
    ]

    static func text(for key: String) -> String {
        words(in: key).map { word in
            replacements[word.lowercased()] ?? word.capitalized
        }.joined(separator: " ")
    }

    private static func words(in key: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in key {
            if character == "-" || character == "_" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

struct ProxyJSONPathEditorView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @ObservedObject var draft: ProxyNodeEditorDraft
    let path: [String]
    let title: String
    let goType: String
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.clashPopRoute) private var popRoute
    @State private var text: String
    @State private var errorMessage = ""
     
    @State private var asksBeforeLeaving = false
     
     
     
    @State private var openedWith: String

    init(
        draft: ProxyNodeEditorDraft,
        path: [String],
        title: String,
        goType: String
    ) {
        self.draft = draft
        self.path = path
        self.title = title
        self.goType = goType
        _text = State(initialValue: draft.jsonValue(path: path))
        _openedWith = State(initialValue: _text.wrappedValue)
    }

    var body: some View {
        ProxyEditorSeat {
            Section {
                TextEditor(text: $text)
                    .accessibilityIdentifier(
                        "proxies.nodeEditor.field.\(path.joined(separator: ".")).json"
                    )
                    .font(.body.monospaced())
                    .frame(minHeight: 280)
            } header: {
                Text(clash: .copy("JSON"))
            } footer: {
                if !errorMessage.isEmpty {
                    ClashStatusMessage(
                        text: .copy(errorMessage),
                        kind: .error
                    )
                    .accessibilityLabel("Invalid JSON")
                    .accessibilityValue(Text(ClashCopy.key(errorMessage)))
                    .accessibilityIdentifier(
                        "proxies.nodeEditor.field.\(path.joined(separator: ".")).json.error"
                    )
                }
            }
        }
            .clashPageTitle(.verbatim(title), watchAs: title)  
            .clashDetailPageInsets()
            .toolbar {
                ToolbarItem(placement: .clashNavigationTrailing) {
                     
                    if !insideProductModal {
                        ClashSaveButton(.copy("Done")) { save() }.font(.body.weight(.semibold))
                            .accessibilityIdentifier(
                                "proxies.nodeEditor.field.\(path.joined(separator: ".")).json.save"
                            )
                    }
                }
            }
             
             
             
             
            .clashProductModalChild(title: .verbatim(title), backAction: leaveAsking)  
            .modifier(ProxyFieldPageLeaving(
                draft: draft,
                asks: $asksBeforeLeaving,
                isPending: { text != openedWith },
                 
                 
                 
                apply: {
                    if let refusal = apply() { return .copy(refusal) }
                    openedWith = text
                    return nil
                },
                save: save,
                finish: finish
            ))
             
             
             
             
             
             
             
             
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                     
                     
                     
                     
                     
                     
                     
                    ClashModalActionBar(primaryTitle: "Done",
                        primaryDisabled: text == openedWith,
                        onPrimary: save)
                }
            }
    }

    private func leaveAsking() {
        if text == openedWith { finish() } else { asksBeforeLeaving = true }
    }

    private func save() {
        if let refusal = apply() { errorMessage = refusal } else { finish() }
    }

     
    private func apply() -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft.removeValue(path: path)
            return nil
        }
        do {
            let value = try JSONSerialization.jsonObject(
                with: Data(trimmed.utf8),
                options: [.fragmentsAllowed]
            )
            guard ProxyJSONShapeValidator.accepts(value, goType: goType) else {
                return ProxyJSONShapeValidator.errorMessage(goType: goType)
            }
            draft.replaceJSONValue(value, path: path)
            return nil
        } catch {
            return "Enter a valid JSON value, array, or object."
        }
    }

    private func finish() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            presentationMode.wrappedValue.dismiss()
        }
#else
         
         
         
        presentationMode.wrappedValue.dismiss()
#endif
    }
}

 
 
 
 
 
 
struct ProxyFieldPageLeaving: ViewModifier {
    let draft: ProxyNodeEditorDraft
    @Binding var asks: Bool
    let isPending: () -> Bool
    let apply: () -> ClashDisplayText?
    let save: () -> Void
    let finish: () -> Void

    func body(content: Content) -> some View {
        content
             
             
             
             
            .clashOnScreen { onScreen in
#if os(macOS)
                draft.pendingText = onScreen ? ProxyNodePendingText(isPending: isPending, apply: apply) : nil
#endif
            }
            .asksBeforeDroppingUntaken($asks, save: save, discard: finish)
    }
}

extension View {
     
     
     
     
    func asksBeforeDroppingUntaken(
        _ asks: Binding<Bool>,
        save: @escaping () -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        clashUnsavedChangesAlert(isPresented: asks,
            message: .copy("This page has changes that have not been saved."),
            isBusy: false,
            save: save,
            discard: discard
        )
    }
}

 
 
 
 
enum ProxyJSONShapeValidator {
    static func accepts(_ value: Any, goType: String) -> Bool {
        let type = String(goType.drop(while: { $0 == "*" }))
        if type.hasPrefix("map[") { return value is [String: Any] }
        if type.hasPrefix("[]") { return value is [Any] }
        return acceptsContainer(value)
    }

    static func acceptsContainer(_ value: Any) -> Bool {
        value is [String: Any] || value is [Any]
    }

    static func errorMessage(goType: String) -> String {
        let type = String(goType.drop(while: { $0 == "*" }))
        if type.hasPrefix("map[") {
            return "Enter a valid JSON object for this field."
        }
        if type.hasPrefix("[]") {
            return "Enter a valid JSON array for this field."
        }
        return "Enter a valid JSON array or object."
    }
}

 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
enum ProxyNodeEditorDocumentFields {
    static let keys: Set<String> = [
        "ca", "certificate", "private-key", "client-certificate", "client-key",
        "tls-cert", "tls-key",
         
         
        "cert", "key", "tls-auth", "tls-crypt", "tls-crypt-v2",
    ]
}

enum ProxyNodeEditorSecretFields {
    static let keys: Set<String> = [
        "auth", "auth-key", "auth-str", "key", "obfs-password", "password", "pre-shared-key",
        "primary-key",
        "private-key", "private-key-passphrase", "psk", "secret", "tls-auth", "tls-crypt",
        "tls-crypt-v2", "token", "username", "uuid",
    ]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let plaintextAuthTypes: Set<String> = ["openvpn"]

    static let plainUsernameTypes: Set<String> = [
        "http", "socks5", "ssh", "mieru", "trusttunnel", "openvpn", "gost-relay",
    ]
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProxyEditorFieldHint {
    static func text(forKey key: String, typeID: String) -> String {
        isRequired(key: key, typeID: typeID) ? "Required" : "Optional"
    }

     
     
     
    static func isRequired(key: String, typeID: String) -> Bool {
        ProxyProtocolEditorSchema.fields(for: typeID)
            .first { $0.key == key }?.required ?? false
    }
}

enum ProxyEditorPlatformNotes {
    private static let clientManagedKeys: Set<String> = ["state-dir"]

     
     
    static func clientManagedNote(forKey key: String) -> String? {
        guard clientManagedKeys.contains(key.lowercased()) else { return nil }
        return "Managed by Clash — the on-device state path is assigned automatically; edits here have no effect."
    }
}



 

 
 
 
 
 
 
enum ProxyEditorMenuOptions {
    static func values(
        choices: [String],
        isRequired: Bool
    ) -> [String] {
        (isRequired ? [] : [""]) + choices
    }

    static func offeredValues(
        selection: String,
        values: [String]
    ) -> [String] {
         
         
         
         
        if selection.isEmpty, !values.contains("") {
            return values
        }
        return values.contains(selection) ? values : [selection] + values
    }
}

private struct ProxyStringMenuRow: View {
    let title: String
    @Binding var selection: String
    let values: [String]
    let identifier: String?
     
     
     
     
    let displayName: (String) -> ClashDisplayText

    init(
        _ title: String,
        selection: Binding<String>,
        values: [String],
        identifier: String? = nil,
        displayName: @escaping (String) -> ClashDisplayText = { .verbatim($0) }
    ) {
        self.title = title
        _selection = selection
        self.values = values
        self.identifier = identifier
        self.displayName = displayName
    }

    private var offeredValues: [String] {
        ProxyEditorMenuOptions.offeredValues(
            selection: selection,
            values: values
        )
    }

    var body: some View {
#if os(macOS)
        Menu {
            Picker(selection: $selection) {
                ForEach(offeredValues, id: \.self) { value in
                    Text(clash: displayName(value))
                        .tag(value)
                        .accessibilityIdentifier(
                            "\(identifier ?? "proxy-menu.\(title)").choice.\(value.isEmpty ? "default" : value)"
                        )
                }
            } label: {
                Text(clash: .copy(title))
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
             
             
             
             
             
             
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: displayName(selection))
                    .foregroundStyle(.secondary)
                Image(
                    systemName:
                        ClashSymbol.chevronUpChevronDown.name
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(clash: .copy(title)))
            .accessibilityValue(Text(clash: displayName(selection)))
            .optionalProxyAccessibilityIdentifier(identifier)
        }
        .buttonStyle(.plain)
        .fixedSize()
         
         
         
         
         
        .id(identifier ?? title)
        .clashSettingsMenuRow(title)
#else
         
         
        Picker(selection: $selection) {
            ForEach(offeredValues, id: \.self) { value in
                Text(clash: displayName(value))
                    .tag(value)
                    .accessibilityIdentifier(
                        "\(identifier ?? "proxy-menu.\(title)").choice.\(value.isEmpty ? "default" : value)"
                    )
            }
        } label: {
            Text(clash: .copy(title))
        }
        .optionalProxyAccessibilityIdentifier(identifier)
#endif
    }
}

 
 
private struct ProxyDocumentFieldRow: View {
    let title: String
    let hint: String
    @Binding var text: String
    let identifier: String?
    @FocusState private var focused: Bool

    var body: some View {
         
         
         
         
        if #available(iOS 16.0, macOS 13.0, *) {
            stacked
        } else {
            ClashFieldRow(
                title,
                hint: hint,
                text: $text,
                monospaced: true,
                identifier: identifier
            )
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @available(iOS 16.0, macOS 13.0, *)
    private var stacked: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: .copy(title))
                    .lineLimit(1)
                Spacer(minLength: ClashTheme.Spacing.compact)
                if text.isEmpty {
                    Text(ClashCopy.key(hint))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            TextField(
                text: $text,
                prompt: nil,
                axis: .vertical,
                label: { EmptyView() }
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .lineLimit(4...16)
            .multilineTextAlignment(.leading)
            .textContentType(.oneTimeCode)
            .disableAutocorrection(true)
            .focused($focused)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(ClashCopy.key(title)))
            .optionalProxyAccessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .optionalProxyAccessibilityIdentifier(
            identifier.map { "\($0).row" }
        )
    }
}

private struct ProxyRevealingFieldRow: View {
    let title: String
    let hint: String
    @Binding var text: String
    @Binding var reveals: Bool
    let multiline: Bool
    let identifier: String?
    @FocusState private var focused: Bool

    var body: some View {
         
         
         
        if multiline,
           reveals,
           #available(iOS 16.0, macOS 13.0, *) {
             
             
             
             
            stacked
        } else {
            inline
        }
    }

    private var inline: some View {
        HStack(alignment: multiline && reveals ? .top : .center) {
            Text(clash: .copy(title))
                .lineLimit(1)
                .layoutPriority(1)
                .padding(.top, multiline && reveals ? 4 : 0)
                 
                 
                .onTapGesture { focused = true }
            Spacer(minLength: ClashTheme.Spacing.compact)
            if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                !(multiline && reveals)
            {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                field
                    .focused($focused)
                    .optionalProxyAccessibilityIdentifier(identifier)
            } else {
                field
                    .focused($focused)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .optionalProxyAccessibilityIdentifier(identifier)
            }
            revealButton
        }
        .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { focused = true }
        )
         
         
         
        .onDisappear { focused = false }
        .accessibilityElement(children: .contain)
        .optionalProxyAccessibilityIdentifier(
            identifier.map { "\($0).row" }
        )
    }

    private var revealButton: some View {
        Button {
            reveals.toggle()
        } label: {
            Image(
                systemName:
                    (reveals ? ClashSymbol.eyeSlash : ClashSymbol.eye).name
            )
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(reveals ? "Hide value" : "Show value")
    }

     
     
     
     
    @available(iOS 16.0, macOS 13.0, *)
    private var stacked: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: .copy(title))
                    .lineLimit(1)
                    .onTapGesture { focused = true }
                Spacer(minLength: ClashTheme.Spacing.compact)
                if text.isEmpty {
                    Text(ClashCopy.key(hint))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                revealButton
            }
            TextField(
                text: $text,
                prompt: nil,
                axis: .vertical,
                label: { EmptyView() }
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .lineLimit(4...16)
            .multilineTextAlignment(.leading)
            .textContentType(.oneTimeCode)
            .disableAutocorrection(true)
            .focused($focused)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(ClashCopy.key(title)))
            .optionalProxyAccessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
         
         
        .onDisappear { focused = false }
        .accessibilityElement(children: .contain)
        .optionalProxyAccessibilityIdentifier(
            identifier.map { "\($0).row" }
        )
    }

    @ViewBuilder
    private var field: some View {
        if reveals {
            if multiline, #available(iOS 16.0, macOS 13.0, *) {
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(3...12)
                    .textFieldStyle(.plain)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.leading)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .overlay(alignment: .trailing) {
                        if text.isEmpty {
                            Text(ClashCopy.key(hint))
                                .foregroundStyle(.tertiary)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(Text(ClashCopy.key(title)))
            } else {
                 
                 
                 
                 
                 
                 
                ClashValueField(
                    hint: hint,
                    label: title,
                    bordered: ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                    text: $text
                )
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.trailing)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .clashMacFieldValueWidth()
            }
        } else {
            ClashSecureValueField(
                hint: hint,
                label: title,
                bordered: ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                text: $text
            )
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.trailing)
            .clashMacFieldValueWidth()
        }
    }

}


 
 
 
 
 
 
 
 
 
enum ProxyNodeNestedFields {
    static func split(
        _ fields: [ProxyEditorSchemaField], pathPrefix: [String], typeID: String,
        catalog: ConfigurationFieldCatalog?, node: OrderedJSON? = nil
    ) -> (kept: [ProxyEditorSchemaField], decided: [ConfigurationNotApplyingItem]) {
        var kept: [ProxyEditorSchemaField] = []
        var decided: [ConfigurationNotApplyingItem] = []
        for field in fields {
            let path = pathPrefix + [field.key]
            let key = path.joined(separator: ".")
            if let entry = ProxyEditorFieldChoices.catalogField(forType: typeID, key: key, catalog: catalog),
               let decision = entry.platformDecision, decision.overridesTheFile,
               node.map({ decision.applies(to: $0.node(at: Array(path.dropLast())) ?? .object([])) }) ?? true {
                decided.append(.init(id: key, title: key, decision: decision, field: entry))
            } else {
                kept.append(field)
            }
        }
        return (kept, decided)
    }

     
     
     
     
     
     
     
    static func valueName(_ value: String, path: [String], typeID: String, catalog: ConfigurationFieldCatalog?,
                          copy: ConfigurationFieldCopy, locale: Locale) -> ClashDisplayText {
        .verbatim(ProxyNodeDetailsView.menuLabel(value, key: path.joined(separator: "."), typeID: typeID,
                                                 catalog: catalog, copy: copy, locale: locale))
    }
}

private struct ProxySchemaNestedOptionsView: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let title: String
    let fields: [ProxyEditorSchemaField]
    let pathPrefix: [String]
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        let split = ProxyNodeNestedFields.split(
            fields, pathPrefix: pathPrefix, typeID: draft.typeID,
            catalog: ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog,
            node: ProxyNodeCatalog.json(draft.mapping))
        ProxyEditorSeat {
            ForEach(ProxyNestedFieldGrouping.groups(for: split.kept), id: \.title) {
                group in
                ClashSection(group.title) {
                    ForEach(group.fields) { field in
                        ProxySchemaFieldRow(
                            draft: draft,
                            field: field,
                            pathPrefix: pathPrefix,
                             
                            valueName: { [typeID = draft.typeID, path = pathPrefix + [field.key], fieldCopy, locale] in
                                ProxyNodeNestedFields.valueName(
                                    $0, path: path, typeID: typeID,
                                    catalog: ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog,
                                    copy: fieldCopy, locale: locale)
                            }
                        )
                    }
                }
            }
            if !split.decided.isEmpty {
                Section {
                    ClashRoutedViewLink {
                        ConfigurationSettingsNotApplyingView(items: split.decided)
                    } label: {
                        ConfigurationNotApplyingLabel(count: split.decided.count)
                    }
                    .accessibilityIdentifier("configuration-editor.not-applying")
                }
            }
        }
        .clashPageTitle(.verbatim(title), watchAs: title)  
        .clashPageProbe("nested-options")
        .clashDetailPageInsets()
        .clashProductModalChild(title: .verbatim(title))  
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum ProxyNestedFieldGrouping {
    struct Group {
        let title: String
        let fields: [ProxyEditorSchemaField]
    }

    private static let buckets: [(title: String, keys: Set<String>)] = [
        (
            "Transport",
            [
                "mode", "host", "path", "headers", "version", "service-name",
                "grpc-service-name", "obfs", "obfs-param", "obfs-host",
            ]
        ),
        (
            "Authentication",
            ["username", "password", "uuid", "auth", "auth-str", "token", "psk"]
        ),
        (
            "Security",
            [
                "tls", "sni", "servername", "alpn", "fingerprint",
                "client-fingerprint", "skip-cert-verify", "certificate",
                "private-key", "ca", "ca-str", "name-cert-verify",
                "version-hint", "reality-opts",
            ]
        ),
        ("Multiplexing", ["mux", "smux", "brutal", "max-streams"]),
    ]

    static func groups(for fields: [ProxyEditorSchemaField]) -> [Group] {
        var remaining = fields
        var grouped: [Group] = []

        for bucket in buckets {
            let matched = remaining.filter { bucket.keys.contains($0.key.lowercased()) }
            guard !matched.isEmpty else { continue }
            grouped.append(Group(title: bucket.title, fields: matched))
            remaining.removeAll { bucket.keys.contains($0.key.lowercased()) }
        }

        if !remaining.isEmpty {
            grouped.insert(Group(title: "", fields: remaining), at: 0)
        }
        return grouped
    }
}

private struct ProxySchemaFieldRow: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let field: ProxyEditorSchemaField
    let pathPrefix: [String]
     
     
    var identifierOverride: String? = nil
     
     
     
    var valueName: ((String) -> ClashDisplayText)? = nil
    @State private var revealsSecret = false

    var body: some View {
        Group {
            if field.editorControlKind == .bool {
                ClashSettingsToggleRow(
                    Text(label),
                    isOn: boolBinding
                )
                    .accessibilityIdentifier(fieldIdentifier)
            } else if field.editorControlKind == .optionalBool {
                optionalBoolPicker
                    .accessibilityIdentifier(fieldIdentifier)
            } else if field.editorControlKind == .nestedObject {
                ProxyNodeDraftNavigationLink(source: draft) { local in
                    ProxySchemaNestedOptionsView(
                        draft: local,
                        title: label,
                        fields: field.children,
                        pathPrefix: path
                    )
                } label: {
                    valueRow(label, draft.hasValue(path: path) ? "Configured" : "Not set")
                }
                .accessibilityIdentifier(fieldIdentifier)
            } else if field.editorControlKind == .json {
                ProxyNodeDraftNavigationLink(source: draft) { local in
                    ProxyJSONPathEditorView(
                        draft: local,
                        path: path,
                        title: label,
                        goType: field.goType
                    )
                } label: {
                    valueRow(label, draft.hasValue(path: path) ? "Configured" : "Not set")
                }
                .accessibilityIdentifier(fieldIdentifier)
            } else if !pickerChoices.isEmpty {
                 
                 
                 
                 
                 
                 
                 
                ProxyStringMenuRow(
                    label,
                    selection: textBinding,
                    values: ProxyEditorMenuOptions.values(
                        choices: pickerChoices,
                        isRequired: field.required
                    ),
                    identifier: fieldIdentifier
                ) {
                    $0.isEmpty
                        ? .copy(field.required ? "Required" : "Not set")
                        : valueName?($0) ?? .verbatim($0)
                }
            } else if field.editorControlKind == .stringList {
                textRow(binding: listBinding)
            } else if field.editorControlKind == .secret {
                secretRow
            } else {
                textRow(binding: textBinding)
            }
        }
    }

    private var path: [String] { pathPrefix + [field.key] }

     
     
     
    private var pickerChoices: [String] {
        let typeID = draft.typeID
        let catalog = ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog
        let byPath = ProxyEditorFieldChoices.choices(
            forType: typeID, key: path.joined(separator: "."), catalog: catalog
        )
        if !byPath.isEmpty { return byPath }
        guard pathPrefix.isEmpty else { return [] }
        return ProxyEditorFieldChoices.choices(forType: typeID, key: field.key, catalog: catalog)
    }

    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    private var label: String {
        ProxyNodeFieldLabel.title(path: pathPrefix + [field.key], typeID: draft.typeID, copy: fieldCopy, locale: locale)
    }

    private var isNumeric: Bool { field.editorControlKind == .number }

    private var fieldIdentifier: String {
        identifierOverride
            ?? "proxies.nodeEditor.field.\(path.joined(separator: "."))"
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { draft.string(path: path) },
            set: { draft.setString($0, path: path, number: isNumeric) }
        )
    }

    private var listBinding: Binding<String> {
        Binding(
            get: { draft.stringList(path: path) },
            set: { draft.setStringList($0, path: path) }
        )
    }

     
    private var boolBinding: Binding<Bool> {
        Binding(
            get: { draft.shownFlag(path: path, catalog: ProfilesViewModel.rememberedSyntaxCatalog?.fieldCatalog) },
            set: { draft.setBool($0, path: path) }
        )
    }

    private var optionalBoolSelection: Binding<String> {
        Binding(
            get: {
                guard draft.hasValue(path: path) else { return "default" }
                return draft.bool(path: path) ? "on" : "off"
            },
            set: { value in
                switch value {
                case "on": draft.setBool(true, path: path)
                case "off": draft.setBool(false, path: path)
                default: draft.removeValue(path: path)
                }
            }
        )
    }

    private var optionalBoolPicker: some View {
        ProxyStringMenuRow(
            label,
            selection: optionalBoolSelection,
            values: ["default", "on", "off"],
            identifier: fieldIdentifier
        ) {
            switch $0 {
            case "on": "On"
            case "off": "Off"
            default: "Default"
            }
        }
    }

     
     
     
     
     
     
    private func textRow(binding: Binding<String>) -> some View {
        ClashFieldRow(
            label,
            hint: field.required ? "Required" : "Optional",
            text: binding,
            suffix: unitSuffix(for: binding.wrappedValue),
            compactValue: hasUnit,
            identifier: fieldIdentifier
        )
        .keyboardType(isNumeric ? .numbersAndPunctuation : .default)
        .disableAutocorrection(true)
        .textInputAutocapitalization(.never)
    }

     
     
    private func unitSuffix(for value: String) -> String? {
#if os(macOS)
        ProxyEditorFieldUnits.displayUnit(forKey: field.key, value: value)
#else
        nil
#endif
    }

    private var hasUnit: Bool {
#if os(macOS)
        ProxyEditorFieldUnits.unit(forKey: field.key) != nil
#else
        false
#endif
    }

    private var secretRow: some View {
        ProxyRevealingFieldRow(
            title: label,
            hint: field.required ? "Required" : "Optional",
            text: textBinding,
            reveals: $revealsSecret,
            multiline: ProxyNodeDetailsView.isDocumentField(
                field.key,
                typeID: draft.typeID
            ),
            identifier: fieldIdentifier
        )
    }

    private func valueRow(_ label: String, _ value: ClashDisplayText) -> some View {
        HStack {
             
             
            Text(clash: .verbatim(label))
            Spacer(minLength: ClashTheme.Spacing.standard)
            Text(clash: value).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
    }

}

 
 
 

private struct ProxyTLSEditorView: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    @State private var revealsPrivateKey = false

     
    @ViewBuilder
    private func documentRow(
        _ label: String,
        path: [String],
        identifier: String
    ) -> some View {
        ProxyDocumentFieldRow(
            title: label,
            hint: "Optional",
            text: textBinding(path),
            identifier: identifier
        )
    }

    var body: some View {
        ProxyEditorSeat {
            Section {
                ClashSettingsToggleRow(
                    Text("TLS"),
                    isOn: tlsBinding
                )
                    .disabled(tlsRequired)
                    .accessibilityIdentifier("proxies.nodeEditor.tls.tls")
            } footer: {
                if tlsRequired {
                    Text("\(protocolDisplayName) always uses TLS.")
                }
            }

            Section {
                if supports("skip-cert-verify") {
                    ClashSettingsToggleRow(
                        Text("Allow Insecure"),
                        isOn: boolBinding(["skip-cert-verify"])
                    )
                        .accessibilityIdentifier("proxies.nodeEditor.tls.skip-cert-verify")
                }
                if let sniKey {
                    textRow(
                        "SNI",
                        path: [sniKey],
                        identifier: "proxies.nodeEditor.tls.sni"
                    )
                }
                if supports("ech-opts") {
                    ProxyNodeDraftNavigationLink(source: draft) { local in
                        ProxyECHEditorView(draft: local)
                    } label: {
                        valueRow("ECH", draft.bool(path: ["ech-opts", "enable"]) ? "On" : "Off")
                    }
                    .accessibilityIdentifier("proxies.nodeEditor.tls.ech")
                }
                if supports("alpn") {
                    textRow(
                        "ALPN",
                        path: ["alpn"],
                        list: true,
                        identifier: "proxies.nodeEditor.tls.alpn"
                    )
                }
                if supports("client-fingerprint") {
                    textRow(
                        "Client Fingerprint",
                        path: ["client-fingerprint"],
                        identifier: "proxies.nodeEditor.tls.client-fingerprint"
                    )
                }
                if supports("reality-opts") {
                    ProxyNodeDraftNavigationLink(source: draft) { local in
                        ProxyRealityEditorView(draft: local)
                    } label: {
                        valueRow(
                            "Reality",
                            draft.string(path: ["reality-opts", "public-key"]).isEmpty ? "Off" : "Configured"
                        )
                    }
                    .accessibilityIdentifier("proxies.nodeEditor.tls.reality")
                }
            }

            if supports("fingerprint") {
                Section {
                    textRow(
                        "SHA256",
                        path: ["fingerprint"],
                        identifier: "proxies.nodeEditor.tls.fingerprint"
                    )
                } footer: {
                    Text("Use a SHA-256 certificate fingerprint to pin the server certificate.")
                }
            }

            if supports("certificate") || supports("private-key") {
                ClashSection("Mutual TLS") {
                    if supports("certificate") {
                         
                         
                         
                         
                         
                         
                        documentRow(
                            "Certificate",
                            path: ["certificate"],
                            identifier: "proxies.nodeEditor.tls.certificate"
                        )
                    }
                    if supports("private-key") {
                        ProxyRevealingFieldRow(
                            title: "Private Key",
                            hint: "Optional",
                            text: textBinding(["private-key"]),
                            reveals: $revealsPrivateKey,
                            multiline: true,
                            identifier: "proxies.nodeEditor.tls.private-key"
                        )
                    }
                } footer: {
                    Text("Certificate and private key must be configured together.")
                }
            }
        }
        .clashPageTitle("TLS")
        .clashDetailPageInsets()
        .clashProductModalChild(title: "TLS")
    }

    private func textRow(
        _ label: String,
        path: [String],
        list: Bool = false,
        identifier: String
    ) -> some View {
        ClashFieldRow(
            label,
            hint: "Optional",
            text: list ? listBinding(path[0]) : textBinding(path),
            identifier: identifier
        )
        .disableAutocorrection(true)
        .textInputAutocapitalization(.never)
    }

    private func textBinding(_ path: [String]) -> Binding<String> {
        Binding(
            get: { draft.string(path: path) },
            set: { draft.setString($0, path: path) }
        )
    }

    private func listBinding(_ key: String) -> Binding<String> {
        Binding(get: { draft.stringList(key) }, set: { draft.setStringList($0, key: key) })
    }

    private func boolBinding(_ path: [String]) -> Binding<Bool> {
        Binding(get: { draft.bool(path: path) }, set: { draft.setBool($0, path: path) })
    }

    private var tlsBinding: Binding<Bool> {
        guard !tlsRequired else { return .constant(true) }
        return boolBinding(["tls"])
    }

    private var tlsRequired: Bool {
        !supports("tls")
    }

     
     
     
     
     
    private func supports(_ key: String) -> Bool {
        ProxyEditorFieldOwnership.tlsKeys(typeID: draft.typeID).contains(key)
    }

    private var sniKey: String? {
        if supports("sni") { return "sni" }
        if supports("servername") { return "servername" }
        return nil
    }

    private var protocolDisplayName: String {
        ProxyProtocolCatalog.specification(for: draft.typeID)?.displayName ?? draft.typeID
    }

    private func valueRow(_ label: String, _ value: ClashDisplayText) -> some View {
        HStack {
            Text(clash: .copy(label))
            Spacer()
            Text(clash: value).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: ClashClientUI.ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
        .contentShape(Rectangle())
    }
}

private struct ProxyECHEditorView: View {
    @ObservedObject var draft: ProxyNodeEditorDraft

    var body: some View {
        ProxyEditorSeat {
            Section {
                ClashSettingsToggleRow(
                    Text("ECH"),
                    isOn: boolBinding(["ech-opts", "enable"])
                )
                .accessibilityIdentifier("proxies.nodeEditor.tls.ech.enabled")
                textRow(
                    "Configuration",
                    path: ["ech-opts", "config"],
                    identifier: "proxies.nodeEditor.tls.ech.config"
                )
                textRow(
                    "Query Server Name",
                    path: ["ech-opts", "query-server-name"],
                    identifier: "proxies.nodeEditor.tls.ech.query-server-name"
                )
            }
        }
        .clashPageTitle("ECH")
        .clashDetailPageInsets()
        .clashProductModalChild(title: "ECH")
    }

    private func textRow(
        _ label: String,
        path: [String],
        identifier: String
    ) -> some View {
        ClashFieldRow(
            label,
            hint: "Optional",
            text: Binding(
                get: { draft.string(path: path) },
                set: { draft.setString($0, path: path) }
            ),
            identifier: identifier
        )
        .disableAutocorrection(true)
        .textInputAutocapitalization(.never)
    }

    private func boolBinding(_ path: [String]) -> Binding<Bool> {
        Binding(get: { draft.bool(path: path) }, set: { draft.setBool($0, path: path) })
    }
}

private struct ProxyRealityEditorView: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    @State private var revealsPublicKey = false

    var body: some View {
        ProxyEditorSeat {
            Section {
                ProxyRevealingFieldRow(
                    title: "Public Key",
                    hint: "Required",
                    text: textBinding("public-key"),
                    reveals: $revealsPublicKey,
                    multiline: false,
                    identifier: "proxies.nodeEditor.tls.reality.public-key"
                )
                textRow(
                    "Short ID",
                    key: "short-id",
                    identifier: "proxies.nodeEditor.tls.reality.short-id"
                )
                ClashSettingsToggleRow(
                    Text("X25519 + ML-KEM-768"),
                    isOn: Binding(
                        get: { draft.bool(path: ["reality-opts", "support-x25519mlkem768"]) },
                        set: { draft.setBool($0, path: ["reality-opts", "support-x25519mlkem768"]) }
                    )
                )
                .accessibilityIdentifier(
                    "proxies.nodeEditor.tls.reality.support-x25519mlkem768"
                )
            }
        }
        .clashPageTitle("Reality")
        .clashDetailPageInsets()
        .clashProductModalChild(title: "Reality")
    }

    private func textRow(
        _ label: String,
        key: String,
        identifier: String
    ) -> some View {
        ClashFieldRow(
            label,
            hint: "Optional",
            text: textBinding(key),
            identifier: identifier
        )
        .disableAutocorrection(true)
        .textInputAutocapitalization(.never)
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { draft.string(path: ["reality-opts", key]) },
            set: { draft.setString($0, path: ["reality-opts", key]) }
        )
    }
}

private struct ProxyJSONValueEditorView: View {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @ObservedObject var draft: ProxyNodeEditorDraft
    let key: String
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.clashPopRoute) private var popRoute
    @State private var text: String
    @State private var errorMessage = ""
     
    @State private var asksBeforeLeaving = false
     
     
    @State private var openedWith: String

    init(draft: ProxyNodeEditorDraft, key: String) {
        self.draft = draft
        self.key = key
        _text = State(initialValue: draft.jsonValue(key))
        _openedWith = State(initialValue: _text.wrappedValue)
    }

    var body: some View {
        ProxyEditorSeat {
            ClashSection("JSON") {
                TextEditor(text: $text)
                    .accessibilityIdentifier("proxies.nodeEditor.field.\(key).json")
                    .font(.body.monospaced())
                    .frame(minHeight: 280)
            } footer: {
                if !errorMessage.isEmpty {
                    ClashStatusMessage(
                        text: .copy(errorMessage),
                        kind: .error
                    )
                    .accessibilityLabel("Invalid JSON")
                    .accessibilityValue(Text(ClashCopy.key(errorMessage)))
                    .accessibilityIdentifier(
                        "proxies.nodeEditor.field.\(key).json.error"
                    )
                }
            }
        }
            .clashPageTitle(.verbatim(key), watchAs: "node-editor-field")
            .clashDetailPageInsets()
            .toolbar {
                ToolbarItem(placement: .clashNavigationTrailing) {
                     
                    if !insideProductModal {
                        ClashSaveButton(.copy("Done")) { save() }.font(.body.weight(.semibold))
                            .accessibilityIdentifier("proxies.nodeEditor.field.\(key).json.save")
                    }
                }
            }
             
             
            .clashProductModalChild(title: .verbatim(key), backAction: leaveAsking)  
            .modifier(ProxyFieldPageLeaving(
                draft: draft,
                asks: $asksBeforeLeaving,
                isPending: { text != openedWith },
                 
                 
                 
                apply: {
                    if let refusal = apply() { return .copy(refusal) }
                    openedWith = text
                    return nil
                },
                save: save,
                finish: finish
            ))
             
             
             
             
             
             
             
             
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal {
                     
                     
                     
                     
                     
                     
                     
                    ClashModalActionBar(primaryTitle: "Done",
                                                 
                         
                         
                         
                         
                         
                        primaryDisabled: text == openedWith,
                        onPrimary: save)
                }
            }
    }

    private func leaveAsking() {
        if text == openedWith { finish() } else { asksBeforeLeaving = true }
    }

    private func save() {
        if let refusal = apply() { errorMessage = refusal } else { finish() }
    }

     
    private func apply() -> String? {
        do {
            let data = Data(text.utf8)
            let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard ProxyJSONShapeValidator.acceptsContainer(value) else {
                return "Enter a valid JSON array or object."
            }
            draft.replaceJSONValue(value, key: key)
            return nil
        } catch {
            return "Enter a valid JSON array or object."
        }
    }

    private func finish() {
#if os(macOS)
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            presentationMode.wrappedValue.dismiss()
        }
#else
         
         
         
        presentationMode.wrappedValue.dismiss()
#endif
    }
}



 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProxyEditorFieldChoices {
     
     
     
     
     
     
     
    private static let clientFingerprints = [
        "chrome", "firefox", "safari", "ios", "android", "edge", "360", "qq",
        "random", "chrome120", "firefox120", "safari16",
        "chrome_psk", "chrome_psk_shuffle", "chrome_padding_psk_shuffle",
        "chrome_pq", "chrome_pq_psk", "randomized",
    ]

     
     
     
    private static let shadowsocksCiphers = ["aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "2022-blake3-aes-128-ccm", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-ccm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305", "2022-blake3-chacha8-poly1305", "aegis-128l", "aegis-256", "aes-128-ccm", "aes-128-cfb", "aes-128-ctr", "aes-128-gcm-siv", "aes-192-ccm", "aes-192-cfb", "aes-192-ctr", "aes-192-gcm", "aes-256-ccm", "aes-256-cfb", "aes-256-ctr", "aes-256-gcm-siv", "aez-384", "ascon128", "ascon128a", "chacha20", "chacha20-ietf", "chacha8-ietf-poly1305", "deoxys-ii-256-128", "lea-128-gcm", "lea-192-gcm", "lea-256-gcm", "none", "rabbit128-poly1305", "rc4-md5", "xchacha20", "xchacha20-ietf-poly1305", "xchacha8-ietf-poly1305"]

    private static let congestionControllers = [
        "bbr", "cubic", "new_reno", "bbr_meta_v1", "bbr_meta_v2",
    ]
    private static let bbrProfiles = ["standard", "conservative", "aggressive"]

     
     
     
     
     
     
     
     
     
     
    private static let ipStackCongestionControllers = ["cubic", "reno", "bbr", "bbr3"]

    static let choicesByField: [String: [String]] = [
         
         
         
         
         
        "*.ip-version": ["dual", "ipv4", "ipv6", "ipv4-prefer", "ipv6-prefer"],
         
         
         
         
         
         
        "anytls.client-fingerprint": Self.clientFingerprints,
        "gost-relay.client-fingerprint": Self.clientFingerprints,
        "snell.client-fingerprint": Self.clientFingerprints,
        "ss.client-fingerprint": Self.clientFingerprints,
        "trojan.client-fingerprint": Self.clientFingerprints,
        "trusttunnel.client-fingerprint": Self.clientFingerprints,
        "vless.client-fingerprint": Self.clientFingerprints,
        "vmess.client-fingerprint": Self.clientFingerprints,
         
        "*.smux.protocol": ["h2mux", "smux", "yamux"],
         
         
         
        "tuic.udp-relay-mode": ["native", "quic"],
         
         
         
         
         
         
        "masque.congestion-controller": Self.congestionControllers,
        "shadowquic.congestion-controller": Self.congestionControllers,
        "trusttunnel.congestion-controller": Self.congestionControllers,
         
         
         
        "hysteria2.bbr-profile": Self.bbrProfiles,
        "masque.bbr-profile": Self.bbrProfiles,
        "shadowquic.bbr-profile": Self.bbrProfiles,
        "trusttunnel.bbr-profile": Self.bbrProfiles,
        "tuic.bbr-profile": Self.bbrProfiles,
         
         
         
         
         
        "masque.network": ["h3", "h2", "h3-l4proxy"],
         
         
         
         
         
         
         
        "hysteria.protocol": ["udp", "wechat-video"],
         
         
         
         
        "hysteria2.obfs": ["salamander", "gecko"],
         
         
         
         
         
         
        "mieru.transport": ["TCP", "UDP"],
         
         
         
        "openvpn.auth": ["SHA256", "SHA1", "SHA384", "SHA512", "MD5"],
        "openvpn.cipher": ["AES-128-GCM", "AES-192-GCM", "AES-256-GCM", "AES-128-CBC", "AES-192-CBC", "AES-256-CBC", "CHACHA20-POLY1305"],
        "openvpn.proto": ["udp", "tcp"],
         
         
         
         
         
         
         
         
         
         
         
        "ss.cipher": Self.shadowsocksCiphers,
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        "ssr.cipher": ["aes-256-cfb", "aes-128-cfb", "aes-192-cfb", "aes-128-ctr", "aes-192-ctr", "aes-256-ctr", "chacha20-ietf", "chacha20", "xchacha20", "rc4-md5", "none"],
        "ssr.obfs": ["plain", "http_simple", "http_post", "random_head", "tls1.2_ticket_auth", "tls1.2_ticket_fastauth"],
        "ssr.protocol": ["origin", "auth_sha1_v4", "auth_aes128_md5", "auth_aes128_sha1", "auth_chain_a", "auth_chain_b"],
         
         
         
         
         
         
        "snell.version": ["1", "2", "3", "4", "5", "6"],
        "sudoku.aead-method": ["aes-128-gcm", "chacha20-poly1305", "none"],
         
         
         
         
         
        "sudoku.table-type": ["prefer_ascii", "prefer_entropy", "up_ascii_down_entropy", "up_entropy_down_ascii"],
        "sudoku.multiplex": ["off", "auto", "on"],
        "trojan.network": ["tcp", "ws", "grpc"],
         
         
         
         
        "vless.network": ["tcp", "ws", "http", "h2", "grpc", "xhttp"],
         
         
        "vless.flow": ["xtls-rprx-vision"],
         
         
        "ss.plugin": ["obfs", "v2ray-plugin", "gost-plugin", "shadow-tls", "restls", "jls", "kcptun"],
         
         
         
        "ss.udp-over-tcp-version": ["1", "2"],
         
        "snell.obfs-opts.mode": ["tls", "http", "shadow-tls", "restls", "jls"],
         
         
        "mieru.multiplexing": [
            "MULTIPLEXING_DEFAULT", "MULTIPLEXING_OFF", "MULTIPLEXING_LOW",
            "MULTIPLEXING_MIDDLE", "MULTIPLEXING_HIGH",
        ],
        "mieru.handshake-mode": [
            "HANDSHAKE_DEFAULT", "HANDSHAKE_STANDARD", "HANDSHAKE_NO_WAIT",
        ],
         
        "shadowquic.quic-versions": ["v1", "v2"],
         
         
        "sudoku.http-mask-mode": ["legacy", "stream", "poll", "auto", "ws"],
        "sudoku.httpmask.mode": ["legacy", "stream", "poll", "auto", "ws"],
         
         
         
        "sudoku.http-mask-multiplex": ["off", "auto", "on"],
        "sudoku.httpmask.multiplex": ["off", "auto", "on"],
         
         
        "openvpn.key-direction": ["0", "1"],
         
        "openvpn.dev": ["tun"],
         
         
        "hysteria.obfs-protocol": ["udp", "wechat-video", "faketcp"],
         
         
        "vmess.packet-encoding": ["packetaddr", "packet", "xudp"],
         
         
        "vless.xhttp-opts.mode": ["stream-one", "stream-up", "packet-up"],
         
        "snell.obfs-opts.version": ["1", "2", "3"],
        "trojan.shadow-tls-opts.version": ["1", "2", "3"],
        "vmess.shadow-tls-opts.version": ["1", "2", "3"],
        "vless.shadow-tls-opts.version": ["1", "2", "3"],
        "anytls.shadow-tls-opts.version": ["1", "2", "3"],
        "ss.plugin-opts.version": ["1", "2", "3"],
         
         
        "ss.plugin-opts.mode": ["tls", "http", "websocket"],
         
         
        "vmess.cipher": ["auto", "none", "zero", "aes-128-cfb", "aes-128-gcm", "chacha20-poly1305"],
         
         
        "tuic.congestion-controller": Self.congestionControllers,
         
         
         
        "trojan.ss-opts.method": Self.shadowsocksCiphers,
         
         
        "vmess.network": ["tcp", "ws", "http", "h2", "grpc", "mkcp", "kcp", "mekya"],
         
         
         
         
         
         
         
         
         
         
        "masque.ip-stack.mode": ["auto", "gvisor", "mips"],
        "openvpn.ip-stack.mode": ["auto", "gvisor", "mips"],
        "wireguard.ip-stack.mode": ["auto", "gvisor", "mips"],
        "zerotier.ip-stack.mode": ["auto", "gvisor", "mips"],
        "masque.ip-stack.congestion-controller": Self.ipStackCongestionControllers,
        "openvpn.ip-stack.congestion-controller": Self.ipStackCongestionControllers,
        "wireguard.ip-stack.congestion-controller": Self.ipStackCongestionControllers,
        "zerotier.ip-stack.congestion-controller": Self.ipStackCongestionControllers,

         
         
         
        "zerotier.tcp-fallback-mode": ["auto", "force", "disable"],
    ]

     
     
     
    static func choices(forType typeID: String, key: String) -> [String] {
        choicesByField["\(typeID.lowercased()).\(key)"]
            ?? choicesByField["*.\(key)"]
            ?? []
    }

     
     
     
    static func catalogField(forType typeID: String, key: String,
                             catalog: ConfigurationFieldCatalog?) -> ConfigurationField? {
        catalog?.field(atCatalogPath: ProxyNodeCatalog.typePath(typeID) + "." + key)
    }

     
     
     
     
     
     
     
    static func choices(forType typeID: String, key: String, catalog: ConfigurationFieldCatalog?) -> [String] {
        if let field = catalogField(forType: typeID, key: key, catalog: catalog) {
             
             
             
             
             
            guard field.kind == .select else { return [] }
            let values = ProxyNodeCatalog.offeredValues(for: field)
            if !values.isEmpty { return values }
        }
        return choices(forType: typeID, key: key)
    }
}


 
 
 
struct ProxyNodeMoreFieldsPage: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    @State private var catalog: ConfigurationFieldCatalog?

    var body: some View {
         
         
        ProxyEditorSeat {
            if let catalog, ProxyNodeCatalog.knows(draft.typeID, in: catalog) {
                ProxyNodeCatalogSections(draft: draft, catalog: catalog)
            } else if catalog == nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                Section {
                    Text(clash: .copy("The core does not describe this type. Change it in the source."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(clash: .copy("More Fields")))
        .accessibilityIdentifier("proxies.nodeEditor.more-fields.page")
        .task {
            if catalog == nil {
                catalog = try? await ProfilesViewModel.loadSyntaxCatalog().fieldCatalog
            }
        }
    }
}
