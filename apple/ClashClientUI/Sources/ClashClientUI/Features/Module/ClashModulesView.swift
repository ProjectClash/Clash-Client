import ClashClientKit
import SwiftUI

 
 
 
 
public struct ClashModulesNoticePlaces {
    public var offers: (ClashModulesSnapshot.NoticePlace) -> Bool
    public var page: (ClashModulesSnapshot.NoticePlace) -> AnyView

    public init(offers: @escaping (ClashModulesSnapshot.NoticePlace) -> Bool,
                page: @escaping (ClashModulesSnapshot.NoticePlace) -> AnyView) {
        self.offers = offers
        self.page = page
    }
}

 
 
public enum ClashModulesAddMode: String, Equatable, Identifiable, Sendable {
    case link, manual
    public var id: String { rawValue }
}

 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashModulesView<AddModule: View, QuickAdd: View>: View {
    private let snapshot: ClashModulesSnapshot
     
     
    private let writes: ClashModulesWrites
    private let perform: (ClashModulesAction) -> Void
    private let detail: (String) -> ClashModuleDetailSnapshot?
    private let addModule: (_ mode: ClashModulesAddMode, _ dismiss: @escaping () -> Void) -> AddModule
     
     
    private let quickAdd: (_ open: @escaping (ClashModulesAddMode) -> Void) -> QuickAdd
     
     
    private let pullToUpdate: (() async -> Void)?
     
     
    private let opensAddModule: Bool
     
     
     
     
    private let noticePlaces: ClashModulesNoticePlaces?
     
     
     
     
    private let detailResultPlace: ((String) -> AnyView)?

    @State private var addMode: ClashModulesAddMode?
    @State private var showsReorder = false
    @State private var openedModule: ClashModulesOpenedModule?
     
     
     
     
    @State private var pendingDeletion: ClashModulesSnapshot.ModuleRow?
     
    @State private var openedPlace: ClashModulesSnapshot.NoticePlace?
     
     
    @StateObject private var certificateFeed: ClashModulesCertificateFeed
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        snapshot: ClashModulesSnapshot,
        writes: ClashModulesWrites,
        perform: @escaping (ClashModulesAction) -> Void,
        detail: @escaping (String) -> ClashModuleDetailSnapshot?,
        opensAddModule: Bool = false,
        pullToUpdate: (() async -> Void)? = nil,
        noticePlaces: ClashModulesNoticePlaces? = nil,
        detailResultPlace: ((String) -> AnyView)? = nil,
        @ViewBuilder quickAdd: @escaping (_ open: @escaping (ClashModulesAddMode) -> Void) -> QuickAdd,
        @ViewBuilder addModule: @escaping (_ mode: ClashModulesAddMode, _ dismiss: @escaping () -> Void) -> AddModule
    ) {
        self.snapshot = snapshot
        self.writes = writes
        self.perform = perform
        self.detail = detail
        self.opensAddModule = opensAddModule
        self.pullToUpdate = pullToUpdate
        self.noticePlaces = noticePlaces
        self.detailResultPlace = detailResultPlace
        self.quickAdd = quickAdd
        self.addModule = addModule
        _certificateFeed = StateObject(wrappedValue: ClashModulesCertificateFeed(snapshot))
    }

    public var body: some View {
        Form {
            decryptionSection
             
             
             
            if !snapshot.notices.isEmpty {
                noticesSection
            }
            if !snapshot.modules.isEmpty {
                modulesSection
            }
            if snapshot.canRefreshAll {
                updateAllSection
            }
            quickAdd { addMode = $0 }
        }
        .modifier(ClashModulesFormStyle())
        .modifier(ClashLibraryPullToUpdate(action: snapshot.canRefreshAll ? pullToUpdate : nil))
        .clashPageTitle("Modules")
        .clashToolbarUnlessInPanel {
#if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                macToolbarControls
            }
#else
            ToolbarItem(placement: .primaryAction) {
                toolbarControls
            }
#endif
        }
        .onChange(of: snapshot) { certificateFeed.take($0) }
        .clashDeleteConfirmation(presenting: $pendingDeletion, name: \.name,
            actionTitle: .copy("Delete Module"), identifier: "modules.module.delete.confirm") { doomed in
            perform(.removeModule(id: doomed.id))
        }
        .onAppear { if opensAddModule { addMode = .link } }
        .onChange(of: opensAddModule) { opens in
            if opens { addMode = .link }
        }
        .clashSheet(item: $openedModule) { opened in
             
             
            ClashModuleDetailView(snapshot: detail(opened.id), editor: snapshot.editor, writes: writes, perform: perform) {
                openedModule = nil
            }
            .modifier(ClashModuleDetailResultInset(place: detailResultPlace?(opened.id)))
            .clashModalPresentation(Self.detailPresentation)
        }
        .clashSheet(item: $addMode) { mode in
            addModule(mode) { addMode = nil }
                .clashModalPresentation(.form)
        }
        .clashSheet(isPresented: $showsReorder) {
            ClashModulesReorderView(modules: snapshot.modules, perform: perform) { showsReorder = false }
                .clashModalPresentation(.form)
        }
         
         
         
         
         
         
         
        .clashProductModal(item: $openedPlace, role: .page) { place in
            if let noticePlaces { noticePlaces.page(place) } else { ClashOpeningCancelButton() }
        }
        .modifier(ClashModulesEditorPresentation(editor: newModuleEditor, perform: perform))
        .accessibilityIdentifier("modules.page")
    }

     
     
    static var detailPresentation: ClashModalPresentationRole {
#if os(macOS)
        .fitted
#else
        .page
#endif
    }

     
     
    private var newModuleEditor: ClashModuleEditorSnapshot? {
        snapshot.editor.flatMap { $0.moduleID == nil ? $0 : nil }
    }

     

     
     
     
     
     
     
    private var decryptionSection: some View {
        Section {
             
             
             
             
            ClashStoredToggle(writes.switches, key: ClashModulesWrites.decryption, stored: snapshot.isOn,
                              identifier: "modules.switch", set: { perform(.setEnabled($0)) }) {
                Text("HTTPS Decryption")
            }
            .modifier(ClashModulesSwitchStyle())
            if let certificate = snapshot.certificate {
                ClashRoutedViewLink {
                    ClashModulesCertificateView(feed: certificateFeed, perform: perform)
                        .clashPushedDetailPage()
                } label: {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Text("Certificate")
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        Text(clash: certificate.state.rowValue)
                            .foregroundStyle(certificate.state == .ready ? Color.secondary : Color.orange)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityIdentifier("modules.certificate")
            }
            if let install = snapshot.install {
                Button {
                    perform(.certificate(install.action.kind))
                } label: {
                    Text(clash: install.action.title)
                }
                .disabled(snapshot.isBusy)
                .accessibilityIdentifier("modules.install.\(ClashModulesCertificateView.actionName(install.action.kind))")
            }
        } footer: {
            if let install = snapshot.install {
                Text(clash: install.effect)
            } else if !snapshot.isOn {
                Text("When it's off, only the rules in your modules are used.")
            }
        }
    }

    private var noticesSection: some View {
        Section {
            ForEach(snapshot.notices) { notice in
                if let place = notice.place, let places = noticePlaces, places.offers(place) {
                     
                     
                     
                     
                     
                     
                     
                     
                    Button {
                        openedPlace = place
                    } label: {
                        noticeLabel(notice, isButton: true)
                    }
#if os(macOS)
                     
                     
                     
                    .buttonStyle(.plain)
#endif
                    .accessibilityIdentifier("modules.notice.\(notice.id)")
                } else {
                    noticeLabel(notice)
                        .accessibilityIdentifier("modules.notice.\(notice.id)")
                }
                if let action = notice.action {
                    Button {
                        perform(.notice(action))
                    } label: {
                        Text(clash: notice.actionTitle ?? "Try Again")
                    }
                    .accessibilityIdentifier("modules.notice.action.\(notice.id)")
                }
            }
        }
    }

     
     
    private func noticeLabel(_ notice: ClashModulesSnapshot.Notice, isButton: Bool = false) -> some View {
        Label {
            Text(clash: notice.text)
                .foregroundStyle(isButton ? AnyShapeStyle(.tint) : AnyShapeStyle(notice.tone == .onHold ? Color.secondary : Color.primary))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
             
            if notice.tone == .onHold {
                Image(systemName: ClashSymbol.pauseCircleFill.rawValue)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.rawValue)
                    .foregroundStyle(Color.orange)
            }
        }
    }

     
     
    private var toolbarControls: some View {
        let reorders = snapshot.modules.count > 1
        return ControlGroup {
            if reorders {
                Button {
                    showsReorder = true
                } label: {
                    Image(systemName: ClashSymbol.arrowUpArrowDown.rawValue)
                        .clashToolbarGlyph()
                        .clashToolbarCapsuleEnd(.leading)
                }
                .accessibilityLabel(Text("Reorder Modules"))
                .accessibilityIdentifier("modules.reorder")
                ClashToolbarDivider()
            }
            Button {
                addMode = .link
            } label: {
                Image(systemName: ClashSymbol.plusCircle.rawValue)
                    .clashToolbarGlyph()
                    .clashToolbarCapsuleEnd(reorders ? .trailing : [])
            }
            .accessibilityLabel(Text("Add Module"))
            .accessibilityIdentifier("modules.add.toolbar")
        }
        .disabled(snapshot.isBusy)
        .clashReaderControlGroupStyle()
    }

#if os(macOS)
     
     
     
    @ViewBuilder
    private var macToolbarControls: some View {
        Button {
            addMode = .link
        } label: {
            Label { Text("Add Module") } icon: { Image(systemName: ClashSymbol.plus.rawValue) }
        }
        .help(Text("Add Module"))
        .disabled(snapshot.isBusy)
        .accessibilityIdentifier("modules.add.toolbar")
        if snapshot.canRefreshAll {
            Button {
                perform(.refreshAll)
            } label: {
                Label { Text("Update All") } icon: { Image(systemName: ClashSymbol.arrowTriangle2Circlepath.rawValue) }
            }
            .help(Text("Update All"))
            .disabled(snapshot.isBusy || snapshot.batch?.isRunning == true)
            .accessibilityIdentifier("modules.update-all")
        }
    }
#endif

    private var modulesSection: some View {
         
         
         
        let paths = ClashModulesSnapshot.ModuleRow.distinguishingPaths(snapshot.modules)
        let shared = Set(Dictionary(grouping: snapshot.modules, by: \.name).filter { $0.value.count > 1 }.keys)
        let rows = ForEach(snapshot.modules) { row in
            moduleRow(row, path: paths[row.id] ?? (shared.contains(row.name) ? Self.sourceName(row, locale: locale) : nil))
        }
#if os(macOS)
         
         
        return Section {
            rows
        } header: {
            Text("Modules")
        } footer: {
            if let batch = snapshot.batch { batchCount(batch) }
        }
#else
        return Section {
            rows
        } header: {
            Text("Modules")
        }
#endif
    }

     
     
     
    @ViewBuilder
    private var updateAllSection: some View {
#if !os(macOS)
        Section {
            ClashConfigurationUpdateButton(title: "Update All", updatingTitle: "Updating…",
                                           isUpdating: snapshot.batch?.isRunning == true,
                                           disabled: snapshot.isBusy, action: { perform(.refreshAll) })
                .accessibilityIdentifier("modules.update-all")
        } footer: {
            if let batch = snapshot.batch { batchCount(batch) }
        }
#endif
    }

    private func batchCount(_ batch: ClashModulesSnapshot.Batch) -> some View {
        Text(verbatim: "\(batch.done) / \(batch.total)")
            .monospacedDigit()
            .accessibilityIdentifier("modules.update-status")
    }

     
     
     
    @ViewBuilder
    private func moduleRow(_ row: ClashModulesSnapshot.ModuleRow, path: String?) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
                    moduleLines(row, path: path)
                    HStack(spacing: ClashTheme.Spacing.row) {
                        moduleSwitch(row)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        moduleInfoButton(row)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: ClashTheme.Spacing.row) {
                    moduleLines(row, path: path)
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    moduleInfoButton(row)
                    moduleSwitch(row)
                }
            }
        }
         
         
         
        .contextMenu {
#if os(macOS)
            macRowMenu(row)
#else
            if let link = row.link {
                Button {
                    perform(.refreshModule(id: row.id))
                } label: {
                    Label { Text("Update") } icon: { Image(systemName: ClashSymbol.arrowClockwise.rawValue) }
                }
                .accessibilityIdentifier("modules.module.update")
                Button {
                    perform(.copy(link))
                } label: {
                    Label { Text("Copy Link") } icon: { Image(systemName: ClashSymbol.link.rawValue) }
                }
                .accessibilityIdentifier("modules.module.copy-link")
            }
            Button(role: .destructive) {
                pendingDeletion = row
            } label: {
                Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
            }
#endif
        }
        .modifier(ClashModulesDeleteSwipe { pendingDeletion = row })
    }

#if os(macOS)
     
     
     
     
    @ViewBuilder
    private func macRowMenu(_ row: ClashModulesSnapshot.ModuleRow) -> some View {
        if let link = row.link {
            Button {
                perform(.refreshModule(id: row.id))
            } label: {
                Text("Update")
            }
            .accessibilityIdentifier("modules.module.update")
            Button {
                perform(.copy(link))
            } label: {
                Text("Copy Link")
            }
            .accessibilityIdentifier("modules.module.copy-link")
        }
        if snapshot.modules.count > 1 {
            Divider()
            Button {
                if let order = snapshot.order(moving: row.id, by: -1) { perform(.moveModules(order)) }
            } label: {
                Text("Move Up")
            }
            .disabled(snapshot.order(moving: row.id, by: -1) == nil)
            .accessibilityIdentifier("modules.module.move-up")
            Button {
                if let order = snapshot.order(moving: row.id, by: 1) { perform(.moveModules(order)) }
            } label: {
                Text("Move Down")
            }
            .disabled(snapshot.order(moving: row.id, by: 1) == nil)
            .accessibilityIdentifier("modules.module.move-down")
        }
        Divider()
         
        Button(role: .destructive) {
            pendingDeletion = row
        } label: {
            Text("Delete")
        }
    }
#endif

     
     
     
     
     
     
    private func moduleLines(_ row: ClashModulesSnapshot.ModuleRow, path: String?) -> some View {
        let wraps = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: row.name)
                .font(.body)
                .lineLimit(wraps ? nil : 1)
                .truncationMode(.tail)
            Text(verbatim: [path, Self.entriesLine(row, locale: locale)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(wraps ? nil : 1)
                .truncationMode(.middle)
             
            if row.failure != nil {
                Text("Update failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func moduleInfoButton(_ row: ClashModulesSnapshot.ModuleRow) -> some View {
        Button {
            openedModule = ClashModulesOpenedModule(id: row.id)
        } label: {
            Image(systemName: ClashSymbol.infoCircle.rawValue)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Details"))
        .accessibilityIdentifier("modules.module.info.\(row.id)")
    }

    private func moduleSwitch(_ row: ClashModulesSnapshot.ModuleRow) -> some View {
         
         
         
         
        ClashStoredToggle(writes.switches, key: ClashModulesWrites.module(row.id), stored: row.enabled,
                          identifier: "modules.module.toggle.\(row.id)", set: { perform(.setModule(id: row.id, enabled: $0)) }) {
            Text(verbatim: row.name)
        }
        .modifier(ClashModulesSwitchStyle())
        .labelsHidden()
    }

     

     
     
     
    nonisolated static func sourceLine(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale, now: Date = Date()) -> String {
        [sourceName(row, locale: locale), updatedLine(row, locale: locale, now: now)].compactMap { $0 }.joined(separator: " · ")
    }

     
     
    nonisolated static func sourceName(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale) -> String? {
        switch row.source {
        case .link(let host): return host
        case .local: return ClashCopy.string("Local", locale: locale)
        case .unknown: return nil
        }
    }

     
    nonisolated static func updatedLine(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale, now: Date = Date()) -> String? {
        guard let updated = row.updatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
         
         
        let when = formatter.localizedString(for: min(updated, now.addingTimeInterval(-1)), relativeTo: now)
        return ClashCopy.string(for: .format("Last updated %@", [when]), locale: locale)
    }

     
     
     
     
    nonisolated static func entriesLine(_ row: ClashModulesSnapshot.ModuleRow, locale: Locale) -> String {
         
        let waiting = row.enabled ? row.waitingCount : 0
        return ClashModuleCountLine.string(
            ClashModuleCountLine.parts(kept: row.effectiveCount + waiting, waiting: waiting, waitsFor: row.waitsFor,
                                       enabled: row.enabled, details: false, locale: locale),
            locale: locale)
    }
}

 
 
struct ClashModulesEditorPresentation: ViewModifier {
    let editor: ClashModuleEditorSnapshot?
    let perform: (ClashModulesAction) -> Void

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.clashSheet(item: Binding(get: { editor }, set: { if $0 == nil { perform(.closeEditor) } })) { opened in
            ClashModuleEditorView(editor: editor ?? opened, perform: perform)
                .clashModalPresentation(.page)
        }
#endif
    }
}

struct ClashModulesOpenedModule: Identifiable, Equatable {
    let id: String
}

 
 
 
struct ClashModulesSwitchStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.toggleStyle(.switch)
#endif
    }
}

 
 
 
 
 
struct ClashModulesFormStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content.formStyle(.grouped).modifier(ClashMacHardTopEdge())
#else
        content
#endif
    }
}

 
 
struct ClashModulesDeleteSwipe: ViewModifier {
    let delete: () -> Void

    func body(content: Content) -> some View {
#if os(iOS)
        content.clashSwipeToDelete(identifier: "modules.module.delete", delete)
#else
        content
#endif
    }
}

 
 
 
 
struct ClashModulesReorderView: View {
    let perform: (ClashModulesAction) -> Void
    let close: () -> Void
    @State private var modules: [ClashModulesSnapshot.ModuleRow]

    init(modules: [ClashModulesSnapshot.ModuleRow], perform: @escaping (ClashModulesAction) -> Void,
         close: @escaping () -> Void) {
        self.perform = perform
        self.close = close
        _modules = State(initialValue: modules)
    }

    var body: some View {
        ClashSingleColumnNavigationContainer {
            List {
                ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                    Text(verbatim: module.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform,
                               alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityHint("Drag to reorder")
                        .accessibilityAction(named: "Move Up") { move(at: index, offset: -1) }
                        .accessibilityAction(named: "Move Down") { move(at: index, offset: 1) }
                        .contextMenu {
                            Button("Move Up") { move(at: index, offset: -1) }
                                .disabled(index == modules.startIndex)
                            Button("Move Down") { move(at: index, offset: 1) }
                                .disabled(index == modules.index(before: modules.endIndex))
                        }
                        .accessibilityIdentifier("modules.reorder.row.\(module.id)")
                }
                .onMove { source, destination in
                    modules.move(fromOffsets: source, toOffset: destination)
                    perform(.moveModules(modules.map(\.id)))
                }
            }
            .clashExplicitReorderMode()
            .clashPageTitle("Reorder Modules")
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton {
                        close()
                    }
                }
            }
            .clashProductModalRoot(title: "Reorder Modules")
        }
        .accessibilityIdentifier("modules.reorder.screen")
    }

    private func move(at index: Int, offset: Int) {
        let destination = index + offset
        guard modules.indices.contains(index), modules.indices.contains(destination) else { return }
        modules.swapAt(index, destination)
        perform(.moveModules(modules.map(\.id)))
    }
}

 
 
 
private struct ClashModuleDetailResultInset: ViewModifier {
    let place: AnyView?

    func body(content: Content) -> some View {
        if let place {
            content.safeAreaInset(edge: .top, spacing: 0) { place }
        } else {
            content
        }
    }
}
