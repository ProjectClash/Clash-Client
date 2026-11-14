import SwiftUI
import os.log
import os

 
 
 
 
 
 
 
 
@MainActor
public final class ClashModalCenter: ObservableObject {
    public static let shared = ClashModalCenter()

    public struct Entry: Identifiable {
        public let id: UUID
        let role: ClashModalPresentationRole
        let content: AnyView
        let onDismiss: (() -> Void)?
        let contentRevision: Int

        init(
            id: UUID = UUID(),
            role: ClashModalPresentationRole,
            content: AnyView,
            onDismiss: (() -> Void)?,
            contentRevision: Int = 0
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.onDismiss = onDismiss
            self.contentRevision = contentRevision
        }
    }

    @Published var stack: [Entry] = []

     
     
     
     
     
     
    public var isPresenting: Bool {
        !stack.isEmpty
    }

    public func present(
        role: ClashModalPresentationRole,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> some View
    ) -> UUID {
        let entry = Entry(
            role: role,
            content: AnyView(content()),
            onDismiss: onDismiss
        )
        stack.append(entry)
        return entry.id
    }

     
     
     
     
    public func update(
        _ id: UUID,
        @ViewBuilder content: () -> some View
    ) {
        guard let index = stack.firstIndex(where: { $0.id == id }) else {
            return
        }
        let entry = stack[index]
        if ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1" {
            FileHandle.standardError.write(
                "[nav] centre update rev=\(entry.contentRevision + 1)\n"
                    .data(using: .utf8)!
            )
        }
        stack[index] = Entry(
            id: entry.id,
            role: entry.role,
            content: AnyView(content()),
            onDismiss: entry.onDismiss,
            contentRevision: entry.contentRevision + 1
        )
    }

    public func dismiss(_ id: UUID) {
        if let index = stack.firstIndex(where: { $0.id == id }) {
             
             
             
            let removed = Array(stack[index...])
            stack.removeSubrange(index...)
            for entry in removed {
                parkedOrphans.removeValue(forKey: entry.id)
            }
            for entry in removed.reversed() {
                entry.onDismiss?()
            }
        }
    }

    func dismissTop() {
        if let entry = stack.popLast() {
            parkedOrphans.removeValue(forKey: entry.id)
            entry.onDismiss?()
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var parkedOrphans: [UUID: String] = [:]

    func parkOrphan(_ id: UUID, claimKey: String) {
        guard stack.contains(where: { $0.id == id }) else { return }
        parkedOrphans[id] = claimKey
        if ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1" {
            FileHandle.standardError.write(
                "[nav] centre park key=\(claimKey)\n".data(using: .utf8)!
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.parkedOrphans.removeValue(forKey: id) != nil else {
                return
            }
            if ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1" {
                FileHandle.standardError.write(
                    "[nav] centre sweep unclaimed key=\(claimKey)\n".data(using: .utf8)!
                )
            }
            self.dismiss(id)
        }
    }

    func claimOrphan(claimKey: String) -> UUID? {
        guard let id = parkedOrphans.first(where: { $0.value == claimKey })?.key else {
            return nil
        }
        parkedOrphans.removeValue(forKey: id)
        if ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1" {
            FileHandle.standardError.write(
                "[nav] centre claim key=\(claimKey)\n".data(using: .utf8)!
            )
        }
        return id
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func requestDismissTop(_ departureGuard: ClashRootDepartureGuard?) {
        ClashDeparture.request(departureGuard) { [weak self] in self?.dismissTop() }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashWindowToolbarHiddenWhilePanelUp: ViewModifier {
    @ObservedObject private var center = ClashModalCenter.shared

    public init() {}

    public func body(content: Content) -> some View {
#if os(macOS)
        content.toolbar(
            center.isPresenting ? .hidden : .automatic,
            for: .windowToolbar
        )
#else
        content
#endif
    }
}

enum ClashProductModalLayerMetrics {
     
     
    static var legacyTopInset: CGFloat {
        if #available(macOS 15.0, *) {
            return 0
        } else {
            return 28
        }
    }
}

 
public struct ClashProductModalLayer: View {
    @ObservedObject private var center = ClashModalCenter.shared

    public init() {}

    public var body: some View {
#if os(macOS)
        ZStack {
            if !center.stack.isEmpty {
                Color.black.opacity(
                    ClashTheme.MacOS.ProductModal.dimmingOpacity
                )
                    .ignoresSafeArea()

                 
                 
                 
                 
                 
                 
                 
                 
                ForEach(
                    Array(center.stack.enumerated()),
                    id: \.element.id
                ) { index, entry in
                    let isTop = index == center.stack.index(before: center.stack.endIndex)
                    ClashProductModalPanel(role: entry.role) {
                        entry.content
                            .id(entry.contentRevision)
                             
                             
                             
                             
                            .clashPageProbe("panel")
                    }
                     
                     
                     
                     
                     
                     
                     
                    .padding(.top, ClashProductModalLayerMetrics.legacyTopInset)
                     
                     
                     
                     
                     
                     
                    .offset(x: isTop ? 0 : -100_000)
                    .animation(nil, value: isTop)
                    .allowsHitTesting(isTop)
                    .accessibilityHidden(!isTop)
                    .zIndex(Double(index))
                }
            }
        }
         
         
         
         
         
         
         
         
         
#else
        EmptyView()
#endif
    }
}

#if os(macOS)
 
 
 
 
 
 
 
 
 
private enum ClashProductModalSurface {
     
     
     
     
    static var canvas: Color {
        Color(nsColor: .windowBackgroundColor)
    }

     
     
     
     
    static var border: Color {
#if os(macOS)
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(
                        red: 0x4B / 255,
                        green: 0x4B / 255,
                        blue: 0x4B / 255,
                        alpha: 1
                    )
                    : NSColor.black.withAlphaComponent(0.08)
            }
        )
#else
        Color(red: 0x4B / 255, green: 0x4B / 255, blue: 0x4B / 255)
#endif
    }
}

private struct ClashProductModalPanel<Content: View>: View {
    let role: ClashModalPresentationRole
    @ViewBuilder let content: () -> Content

     
     
     
     
     
     
    @Environment(\.clashRootDepartureGuard) private var departureGuard

     
     
     
     
     
     
    private func requestDismiss() {
        ClashModalCenter.shared.requestDismissTop(departureGuard)
    }

    var body: some View {
        framedContent
             
             
             
             
             
             
             
             
             
             
             
            .background(ClashProductModalSurface.canvas)
             
             
            .overlay(alignment: .topTrailing) {
                ClashProductModalCloseGlyph(action: requestDismiss)
            }
            .background(
                RoundedRectangle(
                    cornerRadius: ClashTheme.MacOS.ProductModal.cornerRadius,
                    style: .continuous
                )
                .fill(ClashProductModalSurface.canvas)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: ClashTheme.MacOS.ProductModal.cornerRadius,
                    style: .continuous
                )
                    .strokeBorder(
                         
                         
                         
                         
                        ClashProductModalSurface.border,
                        lineWidth: ClashTheme.MacOS.ProductModal.borderWidth
                    )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ClashTheme.MacOS.ProductModal.cornerRadius,
                    style: .continuous
                )
            )
             
             
             
            .compositingGroup()
            .shadow(
                color: .black.opacity(
                    ClashTheme.MacOS.ProductModal.shadowOpacity
                ),
                radius: ClashTheme.MacOS.ProductModal.shadowRadius,
                y: ClashTheme.MacOS.ProductModal.shadowYOffset
            )
            .onExitCommand {
                requestDismiss()
            }
    }

    private var framedContent: some View {
        content().modifier(ClashProductModalFrame(role: role))
    }
}

 
 
 
private struct ClashProductModalFrame: ViewModifier {
    let role: ClashModalPresentationRole

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .fitted:
            content
                .fixedSize(horizontal: false, vertical: true)
                .scrollContentBackground(.hidden)
                .frame(width: ClashTheme.MacOS.ProductModal.width)
        case .page, .form:
            content
                .scrollContentBackground(.hidden)
                .frame(width: ClashTheme.MacOS.ProductModal.width)
                .frame(maxHeight: ClashTheme.MacOS.ProductModal.maximumHeight)
        }
    }
}

 
 
 
 
 
 
 
private struct ClashProductModalCloseGlyph: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: ClashSymbol.xmark.rawValue)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(
                    width: ClashTheme.MacOS.ProductModal.closeGlyphSize,
                    height: ClashTheme.MacOS.ProductModal.closeGlyphSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .padding(ClashTheme.MacOS.ProductModal.closePadding)
        .accessibilityLabel("Close")
    }
}
#endif

public extension View {
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashProductModal<Item: Identifiable, C: View>(
        item: Binding<Item?>,
        role: ClashModalPresentationRole,
        macOSPanelRole: ClashModalPresentationRole? = nil,
        immersive: @escaping (Item) -> Bool = { _ in false },
        @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
#if os(macOS)
        modifier(ClashProductModalMacItemPresenter(
            item: item,
            role: macOSPanelRole ?? role,
            builder: { AnyView(content($0)) }
        ))
#else
         
         
         
        let sheetItem = ClashModalItemSplit.binding(item, keeping: { !immersive($0) })
        let coverItem = ClashModalItemSplit.binding(item, keeping: immersive)
        clashSheet(item: sheetItem) { value in
            content(value)
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                .environment(\.clashProductModalDismiss) { sheetItem.wrappedValue = nil }
                .clashModalPresentation(role)
        }
        .fullScreenCover(item: coverItem) { value in
            content(value)
                .environment(\.clashProductModalDismiss) { coverItem.wrappedValue = nil }
                .clashModalPresentation(role)
        }
#endif
    }

     
     
     
     
    @ViewBuilder
    func clashProductModal<C: View>(
        isPresented: Binding<Bool>,
        role: ClashModalPresentationRole,
        macOSPanelRole: ClashModalPresentationRole? = nil,
        refreshID: AnyHashable = AnyHashable(false),
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
#if os(macOS)
        modifier(ClashProductModalMacBoolPresenter(
            isPresented: isPresented,
            role: macOSPanelRole ?? role,
            refreshID: refreshID,
            builder: { AnyView(content()) }
        ))
#else
        clashSheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                 
                .environment(\.clashProductModalDismiss) { isPresented.wrappedValue = false }
                .clashModalPresentation(role)
        }
#endif
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashSheet<Item: Identifiable, C: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
#if os(iOS)
        if ClashSheetSurface.coversOnThisSystem {
            fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        } else {
            sheet(item: item, onDismiss: onDismiss, content: content)
        }
#else
        sheet(item: item, onDismiss: onDismiss, content: content)
#endif
    }

     
    @ViewBuilder
    func clashSheet<C: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
#if os(iOS)
        if ClashSheetSurface.coversOnThisSystem {
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        } else {
            sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        }
#else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
#endif
    }
}

 
public enum ClashSheetSurface {
     
     
    public static let coversOnThisSystem: Bool = {
#if os(iOS)
        if let forced = ProcessInfo.processInfo.environment["CLASH_SHEETS_AS_COVERS"] {
            return forced == "1"
        }
        if #available(iOS 16.4, *) { return false }
        if #available(iOS 16.0, *) { return true }
#endif
        return false
    }()
}

#if !os(macOS)
 
 
 
enum ClashModalItemSplit {
    static func binding<Item>(
        _ item: Binding<Item?>,
        keeping: @escaping (Item) -> Bool
    ) -> Binding<Item?> {
        Binding(
            get: {
                guard let value = item.wrappedValue, keeping(value) else { return nil }
                return value
            },
            set: { newValue in
                if let newValue {
                    item.wrappedValue = newValue
                } else if let current = item.wrappedValue, keeping(current) {
                    item.wrappedValue = nil
                }
            }
        )
    }
}
#endif

#if os(macOS)
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashProductModalMacItemPresenter<Item: Identifiable>: ViewModifier {
    let item: Binding<Item?>
    let role: ClashModalPresentationRole
    let builder: (Item) -> AnyView
    @Environment(\.clashPresentsPanelsAsNativeSheets) private var asNativeSheets

    func body(content: Content) -> some View {
        if asNativeSheets {
            content.sheet(item: item) { value in
                ClashProductModalSheetBody(role: role, dismiss: { item.wrappedValue = nil }) { builder(value) }
                    .clashModalPresentation(role)
            }
        } else {
            content.modifier(ClashProductModalItemHost(item: item, role: role, builder: builder))
        }
    }
}

 
struct ClashProductModalMacBoolPresenter: ViewModifier {
    let isPresented: Binding<Bool>
    let role: ClashModalPresentationRole
    let refreshID: AnyHashable
    let builder: () -> AnyView
    @Environment(\.clashPresentsPanelsAsNativeSheets) private var asNativeSheets

    func body(content: Content) -> some View {
        if asNativeSheets {
            content.sheet(isPresented: isPresented) {
                ClashProductModalSheetBody(role: role, dismiss: { isPresented.wrappedValue = false }) { builder() }
                    .clashModalPresentation(role)
            }
        } else {
            content.modifier(ClashProductModalBoolHost(
                isPresented: isPresented, role: role, refreshID: refreshID, builder: builder
            ))
        }
    }
}

 
 
 
 
private struct ClashProductModalSheetBody<Content: View>: View {
    let role: ClashModalPresentationRole
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.clashNavigationHostContext, .standalone)
            .environment(\.clashProductChromeApplied, false)
            .environment(\.clashInsideModalPresentation, true)
            .environment(\.clashInsideProductModalPresentation, true)
            .environment(\.clashProductModalDismiss) { dismiss() }
            .modifier(ClashProductModalFrame(role: role))
            .modifier(ClashProductModalSheetHeight(role: role))
            .background(ClashProductModalSurface.canvas)
            .overlay(alignment: .topTrailing) {
                ClashProductModalCloseGlyph(action: dismiss)
            }
            .onExitCommand(perform: dismiss)
    }
}

 
 
 
 
 
 
 
private struct ClashProductModalSheetHeight: ViewModifier {
    let role: ClashModalPresentationRole

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .fitted:
            content
        case .page, .form:
            content.frame(height: ClashTheme.MacOS.ProductModal.maximumHeight)
        }
    }
}

 
 
 
 
 
 
 
 
enum ClashModalClassAudit {
     
     
     
     
     
     
     
     
    static func presenting() {


    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private final class ClashModalLatestContent<Input> {
    private(set) var make: (Input) -> AnyView = { _ in AnyView(EmptyView()) }

    func install(_ make: @escaping (Input) -> AnyView) {
        self.make = make
    }
}

private struct ClashProductModalItemHost<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let role: ClashModalPresentationRole
    let builder: (Item) -> AnyView
    @State private var token: UUID?
    @State private var latest = ClashModalLatestContent<Item>()

    func body(content: Content) -> some View {
        let _ = latest.install { value in AnyView(presentationContent(value)) }
        content
            .onChange(of: item?.id) { _ in
                sync(item)
            }
            .onAppear {
                sync(item)
            }
             
             
             
             
             
             
             
             
             
             
             
             
             
            .onDisappear {
                if let token {
                    ClashModalCenter.shared.parkOrphan(
                        token,
                        claimKey: item.map { "item:\(Item.self):\($0.id)" }
                            ?? "item:\(Item.self):?"
                    )
                    self.token = nil
                }
            }
    }

    private func sync(_ value: Item?) {
         
         
         
         
        if let value, let token {
            ClashModalCenter.shared.update(token) {
                latest.make(value)
            }
            return
        }
         
         
         
         
         
        if let value, token == nil,
            let adopted = ClashModalCenter.shared.claimOrphan(
                claimKey: "item:\(Item.self):\(value.id)"
            )
        {
            token = adopted
            ClashModalCenter.shared.update(adopted) { latest.make(value) }
            return
        }
        if let token {
            ClashModalCenter.shared.dismiss(token)
            self.token = nil
        }
        guard let value else { return }
        ClashModalClassAudit.presenting()
        token = ClashModalCenter.shared.present(
            role: role,
            onDismiss: { item = nil }
        ) {
            latest.make(value)
        }
    }

    private func presentationContent(_ value: Item) -> some View {
        builder(value)
             
             
             
             
             
             
             
            .environment(\.clashNavigationHostContext, .standalone)
            .environment(\.clashProductChromeApplied, false)
            .environment(\.clashInsideModalPresentation, true)
            .environment(\.clashInsideProductModalPresentation, true)
             
             
             
             
            .onAppear { ClashProductModalPresence.shared.up() }
            .onDisappear { ClashProductModalPresence.shared.down() }
            .environment(\.clashProductModalDismiss) {
                item = nil
            }
    }
}

private struct ClashProductModalBoolHost: ViewModifier {
    @Binding var isPresented: Bool
    let role: ClashModalPresentationRole
    let refreshID: AnyHashable
    let builder: () -> AnyView
    @State private var token: UUID?
    @State private var latest = ClashModalLatestContent<Void>()

    func body(content: Content) -> some View {
        let _ = latest.install { _ in AnyView(presentationContent) }
        content
            .onChange(of: isPresented) { shown in
                sync(shown)
            }
            .onAppear {
                sync(isPresented)
            }
            .onChange(of: refreshID) { observed in
                traceRefresh(observed)
                refresh(isPresented)
            }
             
             
             
             
             
             
             
             
             
            .onDisappear {
                if let token {
                    ClashModalCenter.shared.parkOrphan(
                        token,
                        claimKey: "presented:\(role)"
                    )
                    self.token = nil
                }
            }
    }

    private func sync(_ shown: Bool) {
         
         
         
        if shown, let token {
            ClashModalCenter.shared.update(token) { latest.make(()) }
            return
        }
        if shown, token == nil,
            let adopted = ClashModalCenter.shared.claimOrphan(
                claimKey: "presented:\(role)"
            )
        {
            token = adopted
            ClashModalCenter.shared.update(adopted) { latest.make(()) }
            return
        }
        if let token {
            ClashModalCenter.shared.dismiss(token)
            self.token = nil
        }
        guard shown else { return }
        ClashModalClassAudit.presenting()
        token = ClashModalCenter.shared.present(
            role: role,
            onDismiss: { isPresented = false }
        ) {
            latest.make(())
        }
    }

    private func refresh(_ shown: Bool) {
        guard shown, let token else { return }
        ClashModalCenter.shared.update(token) {
            latest.make(())
        }
    }

     
     
     
     
     
    private func traceRefresh(_ observed: AnyHashable) {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1" else { return }
        FileHandle.standardError.write(
            "[nav] bool-host refresh selfIsCurrent=\(observed == refreshID)\n"
                .data(using: .utf8)!
        )
    }

    private var presentationContent: some View {
        builder()
             
            .environment(\.clashNavigationHostContext, .standalone)
            .environment(\.clashProductChromeApplied, false)
            .environment(\.clashInsideModalPresentation, true)
            .environment(\.clashInsideProductModalPresentation, true)
             
             
             
             
            .onAppear { ClashProductModalPresence.shared.up() }
            .onDisappear { ClashProductModalPresence.shared.down() }
            .environment(\.clashProductModalDismiss) {
                isPresented = false
            }
    }
}
#endif

private struct ClashProductModalDismissKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

private struct ClashInsideProductModalPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ClashPresentsPanelsAsNativeSheetsKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
     
     
     
    var clashProductModalDismiss: (@MainActor () -> Void)? {
        get { self[ClashProductModalDismissKey.self] }
        set { self[ClashProductModalDismissKey.self] = newValue }
    }

     
     
     
     
     
     
    var clashInsideProductModalPresentation: Bool {
        get { self[ClashInsideProductModalPresentationKey.self] }
        set { self[ClashInsideProductModalPresentationKey.self] = newValue }
    }

     
     
     
     
    var clashPresentsPanelsAsNativeSheets: Bool {
        get { self[ClashPresentsPanelsAsNativeSheetsKey.self] }
        set { self[ClashPresentsPanelsAsNativeSheetsKey.self] = newValue }
    }
}

public extension View {
     
     
     
    func clashProductModalRoot(
        title: ClashDisplayText,
        actionTitle: String? = nil,
        actionDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        modifier(ClashProductModalRootModifier(
            title: title,
            actionTitle: actionTitle,
            actionDisabled: actionDisabled,
            action: action
        ))
    }

     
     
     
     
     
     
     
     
    func clashProductModalChild(
        title: ClashDisplayText,
        searchText: Binding<String>? = nil,
        actionTitle: String? = nil,
        actionRole: ClashModalActionRole = .primary,
        actionDisabled: Bool = false,
        action: (() -> Void)? = nil,
        backAction: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ClashProductModalChildModifier(
                title: title,
                searchText: searchText,
                actionTitle: actionTitle,
                actionRole: actionRole,
                actionDisabled: actionDisabled,
                action: action,
                backAction: backAction
            )
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashToolbarUnlessInPanel<Items: ToolbarContent>(
        @ToolbarContentBuilder _ items: @escaping () -> Items
    ) -> some View {
        modifier(ClashToolbarUnlessInPanelModifier(items: items))
    }

     
     
     
     
     
     
     
     
    func clashProductModalSearchable(
        text: Binding<String>,
        prompt: Text? = nil
    ) -> some View {
        modifier(
            ClashProductModalSearchModifier(
                text: text,
                prompt: prompt
            )
        )
    }
}



 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashProductModalPresence: ObservableObject {
    public static let shared = ClashProductModalPresence()
     
     
     
     
     
    static let signature = "clash.panel.presence.v21"
     
     
     
    static let v22Signature = "clash.panel.residue.v22"
    @Published private(set) var depth = 0
    var isUp: Bool { depth > 0 }
    func up() { depth += 1 }
    func down() { depth = max(0, depth - 1) }
}

private struct ClashToolbarUnlessInPanelModifier<Items: ToolbarContent>: ViewModifier {
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @ObservedObject private var presence = ClashProductModalPresence.shared
    let items: () -> Items

    func body(content: Content) -> some View {
         
         
         
         
         
         
         
         
#if os(macOS)
        content.toolbar {
            if !(insideProductModal || presence.isUp) {
                items()
            }
        }
#else
        content.toolbar { items() }
#endif
    }
}

private struct ClashProductModalSearchModifier: ViewModifier {
    @Binding var text: String
    let prompt: Text?

    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if insideProductModal {
            content
        } else {
            searchable(content)
        }
#else
        searchable(content)
#endif
    }

    @ViewBuilder
    private func searchable(_ content: Content) -> some View {
        if let prompt {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content.searchable(text: $text)
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
public enum ClashModalActionRole: Sendable {
    case primary
    case utility
}

 
 
 
 
 
 
 
 
 
 
 
 
struct ClashProductChromeAppliedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var clashProductChromeApplied: Bool {
        get { self[ClashProductChromeAppliedKey.self] }
        set { self[ClashProductChromeAppliedKey.self] = newValue }
    }
}

 
enum ClashChromeAudit {
    static func secondChrome(_ title: String, kind: String) {


    }
}

private struct ClashProductModalRootModifier: ViewModifier {
    let title: ClashDisplayText
    let actionTitle: String?
    let actionDisabled: Bool
    let action: (() -> Void)?

    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.clashProductChromeApplied) private var chromeApplied

    private func trace() {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1" else { return }
        FileHandle.standardError.write(
            "[chrome] root title=\(title.rawValue) insideProductModal=\(insideProductModal) chromeApplied=\(chromeApplied)\n".data(using: .utf8)!)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        let _ = trace()
        if insideProductModal && chromeApplied {
            let _ = ClashChromeAudit.secondChrome(title.rawValue, kind: "Root")
            content
        } else if insideProductModal {
            content
                .environment(\.clashProductChromeApplied, true)
                 
                 
                 
                 
                 
                .environment(\.clashRegularShellOwnsCanvas, true)
                .toolbar(.hidden, for: .windowToolbar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Text(clash: title)
                            .font(.headline)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        if let actionTitle, let action {
                             
                             
                             
                            Button(action: action) {
                                Text(ClashCopy.key(actionTitle))
                            }
                                 
                                 
                                 
                                 
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.primary)
                                .disabled(actionDisabled)
                                .accessibilityIdentifier(
                                    "clash.modal.root.action"
                                )
                        }
                        Color.clear
                            .frame(
                                width: ClashTheme.MacOS.ProductModal.closeHitRegion,
                                height: 1
                            )
                            .accessibilityHidden(true)
                    }
                    .frame(
                        minHeight: ClashTheme.MacOS.ProductModal.headerMinHeight
                    )
                    .padding(.horizontal, ClashTheme.Spacing.standard)
                    .background(ClashProductModalSurface.canvas)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct ClashProductModalChildModifier: ViewModifier {
     
    @Environment(\.clashRootDepartureGuard) private var departureGuard
    let title: ClashDisplayText
    let searchText: Binding<String>?
    let actionTitle: String?
    let actionRole: ClashModalActionRole
    let actionDisabled: Bool
    let action: (() -> Void)?
    let backAction: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.clashDeparturePage) private var departurePage
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
    @Environment(\.clashProductChromeApplied) private var chromeApplied

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if insideProductModal && chromeApplied {
             
             
             
             
             
             
             
             
             
             
             
             
             
            if actionTitle != nil {
                let _ = ClashChromeAudit.secondChrome(title.rawValue, kind: "Child")
            }
            content
        } else if insideProductModal {
            content
                .environment(\.clashProductChromeApplied, true)
                 
                 
                 
                .environment(\.clashRegularShellOwnsCanvas, true)
                 
                 
                 
                 
                 
                 
                 
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ClashProductModalSurface.canvas)
                 
                 
                 
                .formStyle(.grouped)
                .listStyle(.inset)
                 
                 
                 
                 
                 
                 
                 
                 
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .windowToolbar)
                 
                 
                 
                 
                 
                .padding(.bottom, ClashTheme.Spacing.standard)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Button {
                                ClashNavigationTransaction.resignCurrentField()
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                let leave: () -> Void = {
                                    if let backAction {
                                        backAction()
                                    } else if let popRoute {
                                        popRoute(ClashPopToken())
                                    } else {
                                        dismiss()
                                    }
                                }
                                ClashDeparture.requestBack(
                                    departureGuard,
                                    from: departurePage,
                                    leave: leave
                                )
                            } label: {
                                Image(
                                    systemName:
                                        ClashSymbol.chevronBackward.rawValue
                                )
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(Color.white.opacity(0.09))
                                )
                            }
                            .frame(
                                width: ClashTheme.Control.minimumHitTarget,
                                height: ClashTheme.Control.minimumHitTarget
                            )
                            .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("clash.modal.child.back")

                        Text(clash: title)
                            .font(.headline)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        if let searchText {
                            ClashModalSearchField(text: searchText)
                        }
                        if let actionTitle, let action {
                            switch actionRole {
                            case .primary:
                                Button(actionTitle, action: action)
                                    .clashPrimaryActionButtonStyle()
                                    .controlSize(.small)
                                    .disabled(actionDisabled)
                                    .accessibilityIdentifier(
                                        "clash.modal.child.action"
                                    )
                            case .utility:
                                Button(actionTitle, action: action)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(.primary)
                                    .disabled(actionDisabled)
                                    .accessibilityIdentifier(
                                        "clash.modal.child.action"
                                    )
                            }
                        }
                         
                         
                         
                        Color.clear
                            .frame(
                                width: ClashTheme.MacOS.ProductModal.closeHitRegion,
                                height: 1
                            )
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, ClashTheme.Spacing.standard)
                     
                     
                    .padding(.vertical, 4)
                     
                     
                     
                     
                     
                    .background(ClashProductModalSurface.canvas)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("clash.modal.child.header")
                }
        } else {
            content
        }
#else
        content
#endif
    }
}

public extension View {
     
     
     
     
     
     
     
     
    func clashNativeSheetChild(
        title: ClashDisplayText,
        searchText: Binding<String>? = nil,
        backAction: (() -> Void)? = nil,
        actionTitle: String? = nil,
        actionDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ClashNativeSheetChildModifier(
                title: title,
                searchText: searchText,
                backAction: backAction,
                actionTitle: actionTitle,
                actionDisabled: actionDisabled,
                action: action
            )
        )
    }
}

 
 
 
private struct ClashWindowToolbarHiddenInsidePanel: ViewModifier {
    let hidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if hidden {
            content.toolbar(.hidden, for: .windowToolbar)
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct ClashNativeSheetChildModifier: ViewModifier {
     
    @Environment(\.clashRootDepartureGuard) private var departureGuard
    let title: ClashDisplayText
    let searchText: Binding<String>?
    let backAction: (() -> Void)?
    var actionTitle: String? = nil
    var actionDisabled = false
    var action: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.clashDeparturePage) private var departurePage
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
             
             
             
             
             
             
             
             
             
            .modifier(ClashWindowToolbarHiddenInsidePanel(hidden: insideProductModal))
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: ClashTheme.Spacing.row) {
                    Button {
                        ClashNavigationTransaction.resignCurrentField()
                         
                         
                         
                         
                        let leave: () -> Void = {
                            if let backAction {
                                backAction()
                            } else if let popRoute {
                                popRoute(ClashPopToken())
                            } else {
                                dismiss()
                            }
                        }
                         
                        ClashDeparture.requestBack(
                            departureGuard,
                            from: departurePage,
                            leave: leave
                        )
                    } label: {
                        Image(
                            systemName:
                                ClashSymbol.chevronBackward.rawValue
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.primary.opacity(0.09))
                        )
                    }
                    .frame(
                        width: ClashTheme.Control.minimumHitTarget,
                        height: ClashTheme.Control.minimumHitTarget
                    )
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(clash: .copy("Back")))
                    .accessibilityIdentifier("clash.sheet.child.back")

                    Text(clash: title)
                        .font(.headline)
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    if let searchText {
                        ClashModalSearchField(text: searchText)
                    }
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .clashPrimaryActionButtonStyle()
                            .controlSize(.small)
                            .disabled(actionDisabled)
                            .accessibilityIdentifier(
                                "clash.sheet.child.action"
                            )
                    }
                }
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .padding(.vertical, 4)
                .background(.bar)
            }
    }
}
