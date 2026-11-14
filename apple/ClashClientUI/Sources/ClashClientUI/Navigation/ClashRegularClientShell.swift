import SwiftUI

 
 
 
 
 
 
 
struct ClashRegularPathDepthMarker: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {

            content

    }
}

 
 
public enum ClashRegularSidebarBehavior: Sendable {
     
    case locked

     
    case system

     
     
    case systemMenuOnly

     
     
     
     
     
     
     
     
     
    case fixed

    fileprivate var removesSidebarToolbarToggle: Bool {
        switch self {
        case .locked, .systemMenuOnly, .fixed:
            true
        case .system:
            false
        }
    }

     
     
    var pinsAllColumns: Bool {
        switch self {
        case .locked, .fixed:
            true
        case .system, .systemMenuOnly:
            false
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    var usesFixedSidebarWidth: Bool {
        switch self {
        case .locked, .systemMenuOnly, .fixed:
            true
        case .system:
            false
        }
    }
}

private enum ClashRegularColumnVisibility: Sendable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
}

 
 
 
 
 
 
 
 
 
public struct ClashRoutePusher: Equatable {
     
     
     
     
     
     
     
     
     
     
    private let token: UUID
    private let push: (any Hashable) -> Void

    public init(
        token: UUID = UUID(),
        _ push: @escaping (any Hashable) -> Void
    ) {
        self.token = token
        self.push = push
    }

    public func callAsFunction(_ route: any Hashable) {
        push(route)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.token == b.token
    }
}

public struct ClashRoutePusherKey: EnvironmentKey {
     
     
    nonisolated(unsafe) public static let defaultValue: ClashRoutePusher? = nil
}

public extension EnvironmentValues {
    var clashPushRoute: ClashRoutePusher? {
        get { self[ClashRoutePusherKey.self] }
        set { self[ClashRoutePusherKey.self] = newValue }
    }

     
     
     
     
     
     
     
     
    var clashPopRoute: ClashRoutePusher? {
        get { self[ClashPopRouteKey.self] }
        set { self[ClashPopRouteKey.self] = newValue }
    }
}

public struct ClashPopRouteKey: EnvironmentKey {
    nonisolated(unsafe) public static let defaultValue: ClashRoutePusher? = nil
}

#if !os(tvOS)
 
 
 
 
 
public struct ClashRegularClientShell<
    Icon: View,
    RootContent: View,
    DestinationContent: View,
    DetailOverlay: View
>: View {
    @Binding private var navigationState: AppleClientNavigationState
    @State private var columnVisibility: ClashRegularColumnVisibility
    @State private var rootScrollTopVisible = true
     
     
     
     
     
     
     
     
     
     
     
    @State private var presentedPathBox = ClashPresentedPathBox()
     
     
    @State private var pushTokens = ClashRoutePusherTokens()
     
     
     
     
     
     
     
     
     
    @State private var tallestRootBarInset: CGFloat = 0
    @State private var currentRootBarInset: CGFloat = 0
     
     
     
     
     
     
    @State private var stackContentOrigin: CGPoint = .zero
     
    @Environment(\.clashDetailTopAccessory) private var detailTopAccessoryView
    @StateObject private var rootDepartureGuard = ClashRootDepartureGuard()
    @ObservedObject private var modalCenter = ClashModalCenter.shared
     
     
     
     
    @Environment(\.dynamicTypeSize) private var shellDynamicTypeSize

    private let sidebarBehavior: ClashRegularSidebarBehavior
    private let background: Color
    private let sidebarBackground: Color

    private let icon: (ClashRootDestination) -> Icon
    private let rootContent: (ClashRootDestination) -> RootContent
    private let destinationContent: (AppleClientDestination) -> DestinationContent
     
     
     
     
     
     
     
     
     
    private let detailOverlay: (ClashRootDestination?) -> DetailOverlay

    public init(
        navigationState: Binding<AppleClientNavigationState>,
        sidebarBehavior: ClashRegularSidebarBehavior,
        background: Color,
        sidebarBackground: Color,
        @ViewBuilder icon: @escaping (ClashRootDestination) -> Icon,
        @ViewBuilder rootContent: @escaping (ClashRootDestination) -> RootContent,
        @ViewBuilder destinationContent: @escaping (
            AppleClientDestination
        ) -> DestinationContent,
        @ViewBuilder detailOverlay: @escaping (
            ClashRootDestination?
        ) -> DetailOverlay
    ) {
        _navigationState = navigationState
        _columnVisibility = State(
            initialValue: sidebarBehavior.pinsAllColumns ? .all : .automatic
        )
        self.sidebarBehavior = sidebarBehavior
        self.background = background
        self.sidebarBackground = sidebarBackground
        self.icon = icon
        self.rootContent = rootContent
        self.destinationContent = destinationContent
        self.detailOverlay = detailOverlay
    }

    @ViewBuilder
    public var body: some View {
        Group {
            if #available(iOS 16.0, macOS 13.0, *) {
                splitView
            } else {
                legacySplitView
            }
        }
         
         
         
         
        .allowsHitTesting(!modalCenter.isPresenting)
        .accessibilityHidden(modalCenter.isPresenting)
         
         
         
        .modifier(ClashWindowToolbarHiddenWhilePanelUp())
         
         
         
        .overlay {
            ClashProductModalLayer()
        }
        .environment(\.clashRootDepartureGuard, rootDepartureGuard)
        .alert(
            "Save your changes?",
            isPresented: Binding(
                get: { rootDepartureGuard.isPromptPresented },
                 
                 
                 
                set: { _ in }
            )
        ) {
             
             
            if rootDepartureGuard.saveBlock == nil {
                Button("Save") { rootDepartureGuard.saveAndLeave() }
            }
            Button("Discard", role: .destructive) {
                rootDepartureGuard.discardAndLeave()
            }
            Button("Keep Editing", role: .cancel) {
                rootDepartureGuard.keepEditing()
            }
        } message: {
            if let block = rootDepartureGuard.saveBlock {
                Text(clash: block)
            } else {
                Text("This page has changes that have not been saved.")
            }
        }
         
         
         
         
        .background { ClashDepartureRefusalAlert(departureGuard: rootDepartureGuard) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @available(iOS 16.0, macOS 13.0, *)
    @ViewBuilder
    private func hostedDetailStack<C: View>(
        @ViewBuilder _ content: () -> C
    ) -> some View {
        NavigationStack(path: presentedPathBinding) {
            content()
        }
         
         
         
         
         
         
         
         
         
         
        .id(
            ClashPlatformLayout.regularShellKeepsContainer
                ? AnyHashable(navigationState.selectedRoot)
                : AnyHashable("clash.detail.stack")
        )

         
         
         
         
         
         
        .environment(
            \.clashPushRoute,
            ClashRoutePusher(token: pushTokens.push) { route in
                var updated = presentedPathBinding.wrappedValue
                updated.append(route)
                presentedPathBinding.wrappedValue = updated
            }
        )
        .environment(\.clashNavigationHostContext, .regularDetail)
        .onAppear {
            ClashNavigationHooks.pop = {
                var updated = presentedPathBinding.wrappedValue
                guard !updated.isEmpty else { return }
                updated.removeLast()
                presentedPathBinding.wrappedValue = updated
            }
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        .clashRegularStackCanvas(background)
    }

    @available(iOS 16.0, macOS 13.0, *)
    private var presentedPathBinding: Binding<NavigationPath> {
        Binding(
            get: { presentedPathBox.path },
            set: { presented in
                 
                 
                 
                ClashNavigationTransaction.applyPathChange {
                let previous = presentedPathBox.path
                 
                 
                ClashPageProbe.markNavigation()
                presentedPathBox.path = presented
                 
                 
                 
                 
                 
                 
                 
                guard presented.count < previous.count,
                      presented.count < navigationState.path.count
                else { return }
                _ = navigationState.replacePath(
                    Array(navigationState.path.prefix(presented.count))
                )
                }
            }
        )
    }

    @available(iOS 16.0, macOS 13.0, *)
    private var splitView: some View {
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
            withSidebarColumnWidth(sidebarColumn)
        } detail: {
            ZStack {
                detailBackground

                 
                 
                 
                VStack(spacing: 0) {
                    detailTopAccessory
                    stackAndOverlay
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        .id(
            ClashPlatformLayout.regularShellKeepsContainer
                ? AnyHashable("clash.regular.container")
                : AnyHashable(navigationState.selectedRoot)
        )
        .clashWindowContainerBackground(background)
    }

     
     
     
     
     
     
     
     
     
    @available(iOS 16.0, macOS 13.0, *)
    @ViewBuilder
    private var stackAndOverlay: some View {
        ZStack {
                hostedDetailStack {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                ClashRegularDetailNavigationFrame(background: background) {
                    VStack(alignment: .leading, spacing: 0) {
                        if usesInContentRegularRootTitle {
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                            Text(clash: .copy(regularRootTitle))
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("regular.detail.title")
                                .padding(.horizontal, ClashTheme.Spacing.standard)
                                 
                                 
                                 
                                 
                                .padding(.top, ClashTheme.Spacing.row)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clashRegularDetailBleedAligned()
                        }
                        regularRootContent(shellDrawsHeading: true)
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                            .environment(\.clashNavigationDepth, 0)
                    }
                }
                .background(barInsetProbe)
                 
                 
                 
                 
                 
                 
                 
                 
                .navigationTitle(
                    modalCenter.isPresenting
                        ? "" : regularNavigationTitle.clashLocalized
                )
                .onPreferenceChange(
                    ClashRegularRootTopVisibilityPreferenceKey.self
                ) {
                     
                     
                    if rootScrollTopVisible != $0 {
                        rootScrollTopVisible = $0
                    }
                }
                .toolbar {
                    if showsCompensatingInlineRootTitle {
                        ToolbarItem(placement: .principal) {
                            VStack(spacing: 0) {
                                Text(clash: .copy(regularRootTitle))
                                    .font(.headline)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(regularRootTitle.clashLocalized)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(
                                "regular.collapsed.title"
                            )
                        }
                    }
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                .clashWithoutSidebarToggle(
                    when: sidebarBehavior.removesSidebarToolbarToggle
                )
                 
                 
                 
                 
                 
                .navigationDestination(for: ClashViewRoute.self) { route in
                    ClashLazyView {
                        ClashViewRouteRegistry.view(for: route)
                    }
                        .clashPushedDetailPage()
                         
                         
                         
                         
                         
                        .modifier(ClashSetterRoutedBack())
                         
                        .clashDeparturePage()
                         
                         
                         
                         
                         
                        .environment(
                            \.clashPushRoute,
                            ClashRoutePusher(token: pushTokens.push) { nestedRoute in
                                var updated = presentedPathBinding.wrappedValue
                                updated.append(nestedRoute)
                                presentedPathBinding.wrappedValue = updated
                            }
                        )
                        .environment(
                            \.clashPopRoute,
                            ClashRoutePusher(token: pushTokens.pop) { _ in
                                var updated = presentedPathBinding.wrappedValue
                                guard !updated.isEmpty else { return }
                                updated.removeLast()
                                presentedPathBinding.wrappedValue = updated
                                DispatchQueue.main.async {
                                    ClashViewRouteRegistry.returnFrom(route)
                                }
                            }
                        )
                        .environment(
                            \.clashRegularShellOwnsCanvas,
                            ClashPushedCanvasOwnership.shellOwnsPushedCanvas
                        )
                         
                         
                         
                         
                         
                        .environment(\.clashDetailCanvas, background)
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                        .environment(
                            \.clashNavigationHostContext,
                            .regularDetail
                        )
                }
                .navigationDestination(for: AppleClientDestination.self) {
                    destination in
                     
                     
                     
                     
                     
                     
                     
                     
                    ClashRegularDetailNavigationFrame(background: background) {
                        ClashLazyView {
                            destinationContent(destination)
                        }
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                             
                            .environment(
                                \.clashNavigationHostContext, .regularDetail
                            )
                            .clashPushedDetailPage()
                    }
                     
                     
                     
                    .clashPushedTopAccessory(background: background)
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    .environment(
                        \.clashPushRoute,
                        ClashRoutePusher(token: pushTokens.push) { route in
                            var updated = presentedPathBinding.wrappedValue
                            updated.append(route)
                            presentedPathBinding.wrappedValue = updated
                        }
                    )
                    .environment(
                        \.clashPopRoute,
                        ClashRoutePusher(token: pushTokens.pop) { _ in
                            var updated = presentedPathBinding.wrappedValue
                            guard !updated.isEmpty else { return }
                            updated.removeLast()
                            presentedPathBinding.wrappedValue = updated
                        }
                    )
                    .modifier(ClashSetterRoutedBack())
                     
                    .clashDeparturePage()
                     
                     
                     
                     
                     
                     
                     
                    .environment(
                        \.clashRegularShellOwnsCanvas,
                        ClashPushedCanvasOwnership.shellOwnsPushedCanvas
                    )
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    .clashWithoutSidebarToggle(
                        when: sidebarBehavior.removesSidebarToolbarToggle
                    )
                     
                     
                     
                     
                     
                     
                }
                }
                .modifier(
                    ClashRegularPathDepthMarker(
                        depth: navigationState.path.count
                    )
                )
                .onChange(of: shellDynamicTypeSize) { _ in
                    tallestRootBarInset = 0
                    currentRootBarInset = 0
                }
                .onChange(of: navigationState.selectedRoot) { _ in
                    ClashPerf.markShellRootChange(
                        to: String(describing: navigationState.selectedRoot)
                    )
                    rootScrollTopVisible = true
                     
                     
                     
                     
                     
                     
                     
                    presentedPathBox.path = NavigationPath(
                        navigationState.path
                    )
                }
                 
                 
                 
                 
                 
                 
                 
                .onChange(of: navigationState.path) { typed in
                    presentedPathBox.path = NavigationPath(typed)
                    reassertLockedSidebar()
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                .onChange(of: presentedPathBox.path.count) { _ in
                    reassertLockedSidebar()
                }
                .onAppear {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if presentedPathBox.path.isEmpty {
                        presentedPathBox.path = NavigationPath(
                            navigationState.path
                        )
                    }
                }

             
             
             
             
            detailOverlay(
                presentedPathBox.path.isEmpty
                    ? navigationState.selectedRoot
                    : nil
            )
                .padding(.top, stackContentOrigin.y)
                .padding(.leading, stackContentOrigin.x)
                 
                 
                 
                 
                 
                .environment(
                    \.clashPushRoute,
                    ClashRoutePusher(token: pushTokens.push) { route in
                        var updated = presentedPathBinding.wrappedValue
                        updated.append(route)
                        presentedPathBinding.wrappedValue = updated
                    }
                )
                .environment(
                    \.clashPopRoute,
                    ClashRoutePusher(token: pushTokens.pop) { _ in
                        var updated = presentedPathBinding.wrappedValue
                        guard !updated.isEmpty else { return }
                        updated.removeLast()
                        presentedPathBinding.wrappedValue = updated
                    }
                )
        }
        .coordinateSpace(name: Self.detailSpace)
         
         
         
        .environment(\.clashDetailTopAccessoryPlaced, presentedPathBox.path.isEmpty)
    }

    private static var detailSpace: String { "clash.regular.detail" }

    private var legacySplitView: some View {
        NavigationView {
            sidebar
                .frame(width: ClashTheme.Regular.Sidebar.width)

            ClashRegularDetailNavigationFrame(background: background) {
                regularRootContent(shellDrawsHeading: false)
            }
        }
        .navigationViewStyle(.columns)
    }

    @ViewBuilder
    @available(iOS 16.0, macOS 13.0, *)
    private var sidebarColumn: some View {
        if sidebarBehavior == .locked {
            lockedSidebarColumn
                .clashWithoutSidebarToggle()
                .clashWithoutNavigationBar()
        } else {
            sidebar
                .clashWithoutSidebarToggle(
                    when: sidebarBehavior.removesSidebarToolbarToggle
                )
                .toolbar {
                    if sidebarBehavior == .systemMenuOnly || sidebarBehavior == .fixed {
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                        if #available(iOS 26.0, macOS 26.0, *) {
                            ToolbarItem(placement: .automatic) {
                                sidebarToolbarPlaceholder
                            }
                            .sharedBackgroundVisibility(.hidden)
                        } else {
                            ToolbarItem(placement: .automatic) {
                                sidebarToolbarPlaceholder
                            }
                        }
                    }
                }
        }
    }

     
     
    private var sidebarToolbarPlaceholder: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    @available(iOS 16.0, macOS 13.0, *)
    private func withSidebarColumnWidth<C: View>(_ column: C) -> some View {
        if sidebarBehavior == .locked {
            column
        } else if sidebarBehavior.usesFixedSidebarWidth {
            column
                .navigationSplitViewColumnWidth(
                    ClashTheme.Regular.Sidebar.width
                )
        } else {
            column
                .navigationSplitViewColumnWidth(
                    min: ClashTheme.Regular.Sidebar.minimumWidth,
                    ideal: ClashTheme.Regular.Sidebar.width,
                    max: ClashTheme.Regular.Sidebar.maximumWidth
                )
        }
    }

    @available(iOS 16.0, macOS 13.0, *)
    private var lockedSidebarColumn: some View {
        sidebar
            .navigationSplitViewColumnWidth(
                min: ClashTheme.Regular.Sidebar.width,
                ideal: ClashTheme.Regular.Sidebar.width,
                max: ClashTheme.Regular.Sidebar.width
            )
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            sidebarList
                .scrollContentBackground(.hidden)
                .background(sidebarSurfaceBackground)
        } else {
            sidebarList
                .background(sidebarSurfaceBackground)
        }
    }

     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var sidebarList: some View {
        if ClashPlatformLayout.sidebarFooterConsumesOwnLayoutSpace {
             
             
             
             
            VStack(spacing: 0) {
                sidebarScrollingList
                    .safeAreaInset(edge: .top, spacing: 0) {
                        sidebarTopInset
                    }
                sidebarFoot
            }
            .background(sidebarSurfaceBackground)
        } else {
            sidebarScrollingList
                .safeAreaInset(edge: .top, spacing: 0) {
                    sidebarTopInset
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    sidebarFoot
                }
        }
    }

    private var sidebarScrollingList: some View {
        List {
             
             
             
             
            ForEach(ClashRootSidebarGroup.allCases, id: \.self) { group in
                if group != .footer, group != .hub {
                    sidebarSection(group)
                }
            }
        }
        .modifier(ClashSidebarFlushContentMargins())
        .accessibilityIdentifier("app.sidebar")
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sidebarSection(_ group: ClashRootSidebarGroup) -> some View {
        let rows = ClashRootDestination.sidebarRows(in: group)
        if !rows.isEmpty {
            if let title = group.title {
                Section {
                    ForEach(rows) { navigationRow($0) }
                } header: {
                     
                     
                     
                    Text(clash: .copy(title))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                         
                         
                         
                         
                         
                         
                         
                         
                        .padding(
                            .leading,
                            ClashTheme.Regular.Sidebar
                                .sectionHeaderLeadingCompensation
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 10,
                                leading:
                                    ClashTheme.Regular.Sidebar.rowLeadingInset
                                    + ClashTheme.Spacing.compact,
                                bottom: 4,
                                trailing: 12
                            )
                        )
                }
            } else {
                Section {
                    ForEach(rows) { navigationRow($0) }
                }
            }
        }
    }

     
     
     
     
     
    @ViewBuilder
    private var sidebarFoot: some View {
        let hubs = ClashRootDestination.sidebarRows(in: .hub)
        let footer = ClashRootDestination.sidebarRows(in: .footer)
        if !hubs.isEmpty || !footer.isEmpty {
            VStack(spacing: 0) {
                if !hubs.isEmpty {
                     
                     
                     
                     
                     
                     
                    Color.clear
                        .frame(height: 12)
                        .accessibilityHidden(true)
                    ForEach(hubs) { destination in
                        navigationRow(destination)
                             
                             
                             
                             
                             
                            .padding(
                                .leading,
                                ClashTheme.Regular.Sidebar.rowLeadingInset
                                    + ClashTheme.Regular.Sidebar
                                        .pinnedRowSectionIndent
                            )
                            .padding(.trailing, 12)
                            .padding(.vertical, 2)
                    }
                }
                if !footer.isEmpty {
                    Divider()
                        .padding(.top, 6)
                    ForEach(footer) { destination in
                        navigationRow(destination)
                            .padding(
                                .leading,
                                ClashTheme.Regular.Sidebar.rowLeadingInset
                                    + ClashTheme.Regular.Sidebar
                                        .pinnedRowSectionIndent
                            )
                            .padding(.trailing, 12)
                            .padding(.vertical, 6)
                    }
                }
            }
            .background(sidebarSurfaceBackground)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    private struct SidebarRow<RowIcon: View>: View, Equatable {
        let destination: ClashRootDestination
        let isSelected: Bool
        let isDisabled: Bool
        let icon: () -> RowIcon
        let activate: () -> Void

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.destination == rhs.destination
                && lhs.isSelected == rhs.isSelected
                && lhs.isDisabled == rhs.isDisabled
        }

        var body: some View {
            Button(action: activate) {
                ClashRootSidebarRow(
                    destination: destination,
                    isSelected: isSelected
                ) {
                    icon()
                        .foregroundStyle(
                            isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
    }

    private func navigationRow(
        _ destination: ClashRootDestination
    ) -> some View {
        let isSelected = navigationState.selectedRoot == destination
        return SidebarRow(
            destination: destination,
            isSelected: isSelected,
            isDisabled: rootDepartureGuard.isBusy && !isSelected,
            icon: { icon(destination) },
            activate: {
                 
                 
                 
                guard !isSelected else {
                    selectRoot(destination)
                    return
                }
                rootDepartureGuard.requestDeparture {
                    selectRoot(destination)
                }
            }
        )
        .equatable()
        .listRowInsets(
            EdgeInsets(
                top: 2,
                leading: ClashTheme.Regular.Sidebar.rowLeadingInset,
                bottom: 2,
                trailing: 12
            )
        )
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(
            isSelected ? [.isButton, .isSelected] : .isButton
        )
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("sidebar.\(destination.rawValue)")
         
         
         
         
        .accessibilityHidden(modalCenter.isPresenting)
    }

    private func legacyNavigationRow(
        _ destination: ClashRootDestination
    ) -> some View {
        Button {
             
             
             
            guard destination != navigationState.selectedRoot else {
                selectRoot(destination)
                return
            }
            rootDepartureGuard.requestDeparture {
                selectRoot(destination)
            }
        } label: {
            ClashRootSidebarRow(
                destination: destination,
                isSelected: navigationState.selectedRoot == destination
            ) {
                icon(destination)
                    .foregroundStyle(
                        navigationState.selectedRoot == destination
                            ? AnyShapeStyle(.tint)
                            : AnyShapeStyle(.secondary)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(
            rootDepartureGuard.isBusy
                && navigationState.selectedRoot != destination
        )
        .listRowInsets(
            EdgeInsets(
                top: 2,
                leading: ClashTheme.Regular.Sidebar.rowLeadingInset,
                bottom: 2,
                trailing: 12
            )
        )
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(
            navigationState.selectedRoot == destination
                ? [.isButton, .isSelected]
                : .isButton
        )
        .accessibilityValue(
            navigationState.selectedRoot == destination
                ? "Selected"
                : ""
        )
        .accessibilityIdentifier("sidebar.\(destination.rawValue)")
         
         
         
         
        .accessibilityHidden(modalCenter.isPresenting)
        .allowsHitTesting(!modalCenter.isPresenting)
        .disabled(modalCenter.isPresenting)
        .modifier(
            ClashOptionalCommandShortcut(
                key: keyboardShortcut(for: destination)
            )
        )
    }

    private func selectRoot(_ destination: ClashRootDestination) {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            let intercepted = ClashNavigationTransaction
                .interceptRootSelection(
                    isCurrentRoot:
                        navigationState.selectedRoot == destination,
                    hasPresentedPath: !presentedPathBox.path.isEmpty
                ) {
                presentedPathBinding.wrappedValue = NavigationPath()
                }
            if intercepted { return }
        }
        navigationState.selectRoot(destination)
    }

    private var sidebarTopInset: some View {
        Color.clear
            .frame(height: ClashTheme.Regular.Sidebar.topInset)
            .accessibilityHidden(true)
    }

    @ViewBuilder
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func regularRootContent(shellDrawsHeading: Bool) -> some View {
        Group {
             
             
            rootContent(navigationState.selectedRoot)
                .environment(\.clashRegularRootScrollsContent, false)
        }
        .id(navigationState.selectedRoot)
         
         
         
         
         
        .environment(
            \.clashRegularRootLargeTitle,
            shellDrawsHeading
                ? nil
                : (usesInContentRegularRootTitle ? regularRootTitle : nil)
        )
        .environment(\.clashRegularShellOwnsCanvas, true)
        .environment(\.clashShellDrawsRootHeading, shellDrawsHeading)
    }

     
     
     
    private var barInsetProbe: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .named(Self.detailSpace)).origin
            Color.clear
                .onAppear {
                    recordBarInset(proxy.safeAreaInsets.top)
                    recordStackContentOrigin(origin)
                }
                .onChange(of: proxy.safeAreaInsets.top) {
                    recordBarInset($0)
                }
                .onChange(of: origin) {
                    recordStackContentOrigin($0)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func recordStackContentOrigin(_ origin: CGPoint) {
         
         
         
        let clamped = CGPoint(
            x: Self.quantised(max(0, origin.x)),
            y: Self.quantised(max(0, origin.y))
        )
        if stackContentOrigin != clamped {
            stackContentOrigin = clamped
        }
    }

    private func recordBarInset(_ inset: CGFloat) {
        let quantised = Self.quantised(inset)
         
         
        if currentRootBarInset != quantised {
            currentRootBarInset = quantised
        }
        if quantised > tallestRootBarInset {
            tallestRootBarInset = quantised
        }
    }

     
     
    private static func quantised(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }

    private var regularRootTitle: String {
        navigationState.selectedRoot == .home
            ? ""
            : navigationState.selectedRoot.pageTitle
    }

    private var regularNavigationTitle: String {
        usesInContentRegularRootTitle ? "" : regularRootTitle
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var usesInContentRegularRootTitle: Bool {
         
         
         
        !ClashPlatformLayout.pageUsesSystemSettingsIdiom
            && sidebarBehavior.usesFixedSidebarWidth
            && navigationState.selectedRoot != .home
    }

    private var showsCompensatingInlineRootTitle: Bool {
        ClashPlatformLayout.installsCompensatingInlineRootTitle
            && usesInContentRegularRootTitle
            && navigationState.path.isEmpty
            && !rootScrollTopVisible
    }

    @ViewBuilder
    private var sidebarSurfaceBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
        } else {
            sidebarBackground.ignoresSafeArea()
        }
    }

     
     
     
     
     
     
    @ViewBuilder
    private var detailTopAccessory: some View {
        if let detailTopAccessoryView, presentedPathBox.isEmpty {
            detailTopAccessoryView
        }
    }

    private var detailBackground: AnyView {
        if #available(iOS 26.0, macOS 26.0, *) {
            return AnyView(
                background
                    .ignoresSafeArea()
                    .backgroundExtensionEffect()
            )
        }
        return AnyView(background.ignoresSafeArea())
    }


     
     
    private func reassertLockedSidebar() {
        guard sidebarBehavior.pinsAllColumns, columnVisibility != .all else {
            return
        }
        columnVisibility = .all
    }

    @available(iOS 16.0, macOS 13.0, *)
    private var columnVisibilityBinding:
        Binding<NavigationSplitViewVisibility>
    {
        Binding(
            get: {
                switch columnVisibility {
                case .automatic:
                    .automatic
                case .all:
                    .all
                case .doubleColumn:
                    .doubleColumn
                case .detailOnly:
                    .detailOnly
                }
            },
            set: { visibility in
                if sidebarBehavior.pinsAllColumns {
                    columnVisibility = .all
                } else if visibility == .all {
                    columnVisibility = .all
                } else if visibility == .doubleColumn {
                    columnVisibility = .doubleColumn
                } else if visibility == .detailOnly {
                    columnVisibility = .detailOnly
                } else {
                    columnVisibility = .automatic
                }
            }
        )
    }



     
    private func keyboardShortcut(
        for destination: ClashRootDestination
    ) -> KeyEquivalent? {
        guard let index = ClashRootDestination.sidebarRows
            .firstIndex(of: destination),
            index < 9,
            let scalar = Unicode.Scalar(String(index + 1)) else {
            return nil
        }
        return KeyEquivalent(Character(scalar))
    }
}

 
 
 
 
 
private struct ClashSidebarFlushContentMargins: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            content.contentMargins(.horizontal, 0, for: .scrollContent)
        } else {
            content
        }
    }
}

private struct ClashOptionalCommandShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

 
 
 
struct ClashPresentedPathBox {
    private var storage: Any?

    @available(iOS 16.0, macOS 13.0, *)
    var path: NavigationPath {
        get { storage as? NavigationPath ?? NavigationPath() }
        set { storage = newValue }
    }

     
     
    var isEmpty: Bool {
        guard #available(iOS 16.0, macOS 13.0, *) else { return true }
        return path.isEmpty
    }
}



extension View {
     
     
     
     
     
    @ViewBuilder
    func clashWithoutSidebarToggle(when shouldRemove: Bool = true) -> some View {
        if shouldRemove, #available(iOS 17.0, macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashWithoutNavigationBar() -> some View {
         
         
         
         
         
        if #available(iOS 16.0, macOS 13.0, *) {
            self.toolbar(.hidden, for: .automatic)
        } else {
            self
        }
    }
}
#endif


 
struct ClashRoutePusherTokens {
    let push = UUID()
    let pop = UUID()
}

#if !os(tvOS)
public extension ClashRegularClientShell where DetailOverlay == EmptyView {
     
    init(
        navigationState: Binding<AppleClientNavigationState>,
        sidebarBehavior: ClashRegularSidebarBehavior,
        background: Color,
        sidebarBackground: Color,
        @ViewBuilder icon: @escaping (ClashRootDestination) -> Icon,
        @ViewBuilder rootContent: @escaping (ClashRootDestination) -> RootContent,
        @ViewBuilder destinationContent: @escaping (
            AppleClientDestination
        ) -> DestinationContent
    ) {
        self.init(
            navigationState: navigationState,
            sidebarBehavior: sidebarBehavior,
            background: background,
            sidebarBackground: sidebarBackground,
            icon: icon,
            rootContent: rootContent,
            destinationContent: destinationContent,
            detailOverlay: { _ in EmptyView() }
        )
    }
}
#endif


private struct ClashDetailTopAccessoryKey: EnvironmentKey {
    static var defaultValue: AnyView? { nil }
}

public extension EnvironmentValues {
     
     
    var clashDetailTopAccessory: AnyView? {
        get { self[ClashDetailTopAccessoryKey.self] }
        set { self[ClashDetailTopAccessoryKey.self] = newValue }
    }
}

private struct ClashDetailTopAccessoryPlacedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
     
     
     
     
    var clashDetailTopAccessoryPlaced: Bool {
        get { self[ClashDetailTopAccessoryPlacedKey.self] }
        set { self[ClashDetailTopAccessoryPlacedKey.self] = newValue }
    }
}
