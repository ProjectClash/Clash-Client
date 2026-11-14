import SwiftUI

 
 
 
 
 
 
 
 
 
 
public struct ClashViewRoute: Hashable {
    public let id: UUID
    public init(id: UUID) { self.id = id }
}

 
public enum ClashRouteOwnership: Sendable {
     
     
     
     
     
     
    case rowOwned
     
     
     
    case oneShot
}

@MainActor
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public extension View {
    func clashNativePushBoundary() -> some View {
        modifier(ClashNativePushBoundaryModifier())
    }
}

private struct ClashNativePushBoundaryModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content
            .environment(\.clashPushRoute, nil)
             
             
             
             
             
             
             
             
             
             
             
             
             
            .environment(\.clashPopRoute, nil)
             
             
             
             
             
            .environment(\.clashIsPushedPage, true)
             
             
             
             
             
            .onAppear {
                ClashPushClock.arrived()
            }

#endif
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashNativeNavigationLink<Destination: View, Label: View>: View {
    private let destination: Destination
    private let label: Label

    public var body: some View {
        NavigationLink {
            destination
                .clashNativePushBoundary()
        } label: {
            label
        }
    }

    public init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.destination = destination()
        self.label = label()
    }
}

public enum ClashViewRouteRegistry {
    private struct Entry {
        let builder: () -> AnyView
        let onReturn: () -> Void
        let ownership: ClashRouteOwnership
         
         
         
         
         
         
         
         
        var built: AnyView?
    }

    nonisolated(unsafe) private static var entries: [UUID: Entry] = [:]

    public static func set(
        _ id: UUID,
        ownership: ClashRouteOwnership = .oneShot,
        onReturn: @escaping () -> Void,
        _ builder: @escaping () -> AnyView
    ) {
         
         
         
         
        var entry = Entry(
            builder: builder, onReturn: onReturn, ownership: ownership
        )
        entry.built = entries[id]?.built
        entries[id] = entry
    }

    public static func view(for route: ClashViewRoute) -> AnyView {
        guard var entry = entries[route.id] else {
            return AnyView(EmptyView())
        }
        if let built = entry.built {
            return built
        }
        let built = entry.builder()
        entry.built = built
        entries[route.id] = entry
        return built
    }

    public static func returnFrom(_ route: ClashViewRoute) {
         
         
         
         
         
         
         
        guard var entry = entries[route.id], entry.built != nil else { return }
        entry.built = nil

        switch entry.ownership {
        case .rowOwned:
             
             
             
             
             
             
             
             
            entries[route.id] = entry
        case .oneShot:
             
             
             
             
            entries.removeValue(forKey: route.id)
        }
        entry.onReturn()
    }

     
    public static func discard(_ route: ClashViewRoute) {
        entries.removeValue(forKey: route.id)
    }

     
     
     
     
     
     
    public static func discardAll() {
        entries.removeAll()
    }
}

private struct ClashListRetainsRowSelectionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    var clashListRetainsRowSelection: Bool {
        get { self[ClashListRetainsRowSelectionKey.self] }
        set { self[ClashListRetainsRowSelectionKey.self] = newValue }
    }
}

public extension View {
     
     
     
     
    func clashListRetainsRowSelection() -> some View {
        environment(\.clashListRetainsRowSelection, true)
    }
}

public struct ClashRoutedViewLink<Destination: View, Label: View>: View {
    private let onNavigate: () -> Void
    private let onReturn: () -> Void
    private let showsDisclosureIndicator: Bool
    private let destination: () -> Destination
    private let label: Label
     
     
     
     
     
    @State private var token = UUID()
    @Environment(\.clashPushRoute) private var pushRoute
    @Environment(\.clashInsideModalPresentation) private var insideModal
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashHostedInRootPool) private var hostedInRootPool
    @Environment(\.clashListRetainsRowSelection)
    private var listRetainsRowSelection
#if os(macOS)
    @State private var awaitsNativeReturn = false
#endif

    public init(
        onNavigate: @escaping () -> Void = {},
        onReturn: @escaping () -> Void = {},
        showsDisclosureIndicator: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.onNavigate = onNavigate
        self.onReturn = onReturn
        self.showsDisclosureIndicator = showsDisclosureIndicator
        self.destination = destination
        self.label = label()
    }

    private func trace(_ branch: String) {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1"
        else { return }
        FileHandle.standardError.write(
"[nav] link branch=\(branch) push=\(pushRoute != nil) insideModal=\(insideModal) host=\(hostContext) pool=\(hostedInRootPool)\n"
                .data(using: .utf8)!
        )
    }

    public var body: some View {
#if os(macOS)
        let _ = trace(
            pushRoute == nil
                ? "none"
                : (hostedInRootPool || insideModal || listRetainsRowSelection
                    ? "programmatic" : "value-link")
        )
         
         
         
         
         
         
         
         
         
         
         
         
         
        if let pushRoute,
           hostedInRootPool || insideModal || listRetainsRowSelection
        {
             
             
             
             
             
            Button {
                let destination = destination
                ClashViewRouteRegistry.set(
                    token,
                    ownership: .rowOwned,
                    onReturn: onReturn
                ) {
                    AnyView(destination())
                }
                ClashNavigationTransaction.resignCurrentField()
                onNavigate()
                pushRoute(ClashViewRoute(id: token))
            } label: {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    label
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 0,
                            alignment: .leading
                        )
                     
                     
                     
                     
                     
                    if showsDisclosureIndicator {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ClashPushRowButtonStyle())
        } else if let pushRoute,
           !insideModal || hostContext == .modal
        {
             
             
             
             
             
             
             
            let _ = {
                let destination = destination
                ClashViewRouteRegistry.set(
                    token,
                    ownership: .rowOwned,
                    onReturn: onReturn
                ) {
                    AnyView(destination())
                }
            }()
            NavigationLink(value: ClashViewRoute(id: token)) {
                label
                    .frame(
                        maxWidth: .infinity,
                         
                         
                         
                         
                        minHeight: insideModal
                            && !ClashPlatformLayout.pageUsesSystemSettingsIdiom
                            ? ClashTheme.Control.fullWidthRowMinHeight
                            : 0,
                        alignment: .leading
                    )
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    ClashNavigationTransaction.resignCurrentField()
                    onNavigate()
                }
            )
        } else {
            NavigationLink {
                ClashNativeRoutedDestination(
                    awaitsReturn: $awaitsNativeReturn,
                    onReturn: onReturn
                ) {
                    ClashLazyView(destination)
                }
            } label: {
                label
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ClashTheme.Control.fullWidthRowMinHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        ClashNavigationTransaction.resignCurrentField()
                        onNavigate()
                        awaitsNativeReturn = true
                    }
                )
                 
                 
                 
                 
                 
                 
                .onAppear {
                    guard awaitsNativeReturn else { return }
                    awaitsNativeReturn = false
                    onReturn()
                }
        }
#else
         
         
         
         
        if ClashPlatformLayout.regularShellKeepsContainer,
           let pushRoute,
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
           !insideModal
        {
            programmaticRow(pushRoute)
        } else {
            NavigationLink {
                ClashLazyView(destination)
                 
                 
                 
                 
                 
                 
                 
                 
                .clashNativePushBoundary()
            } label: {
                label
            }
        }
#endif
    }

     
     
    private func programmaticRow(_ pushRoute: ClashRoutePusher) -> some View {
        Button {
             
            ClashPushClock.tap()
            let destination = destination
            ClashViewRouteRegistry.set(
                token,
                ownership: .rowOwned,
                onReturn: onReturn
            ) {
                AnyView(destination())
            }
            ClashNavigationTransaction.resignCurrentField()
            onNavigate()
            pushRoute(ClashViewRoute(id: token))
        } label: {
            HStack(spacing: ClashTheme.Spacing.compact) {
                label
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 0,
                        alignment: .leading
                    )
                if showsDisclosureIndicator {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ClashPushRowButtonStyle())
    }

}

 
 
 
 
 
 
 
public struct ClashRoutedViewDestination<Destination: View>: View {
    @Binding private var isPresented: Bool
    private let destination: () -> Destination
     
     
    @State private var token = UUID()

    @Environment(\.clashPushRoute) private var pushRoute
    @Environment(\.clashInsideModalPresentation) private var insideModal
    @Environment(\.clashNavigationHostContext) private var hostContext
#if os(macOS)
    @State private var routeIsPresented = false
#endif

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        _isPresented = isPresented
        self.destination = destination
    }

    @ViewBuilder
    public var body: some View {
#if os(macOS)
        if pushRoute != nil,
           !insideModal || hostContext == .modal
        {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .onAppear(perform: presentRouteIfNeeded)
                .onChange(of: isPresented) { _ in
                    presentRouteIfNeeded()
                }
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .onChange(of: isPresented) { shown in
                    if shown {
                        assertionFailure(
                            "ClashRoutedViewDestination requires a value-route host on macOS"
                        )
                    }
                }
        }
#else
        NavigationLink(isActive: $isPresented) {
            ClashLazyView(destination)
                 
                 
                 
                .clashNativePushBoundary()
        } label: {
            EmptyView()
        }
#endif
    }

#if os(macOS)
    @MainActor
    private func presentRouteIfNeeded() {
        guard isPresented, !routeIsPresented, let pushRoute else { return }
        ClashNavigationTransaction.resignCurrentField()
        routeIsPresented = true
         
         
         
        let presented = $isPresented
        let routed = $routeIsPresented
        let destination = destination
        ClashViewRouteRegistry.set(
            token,
            onReturn: {
                routed.wrappedValue = false
                presented.wrappedValue = false
            }
        ) {
            AnyView(destination())
        }
        pushRoute(ClashViewRoute(id: token))
    }
#endif
}

#if os(macOS)
 
 
 
 
 
 
 
private struct ClashNativeRoutedDestination<Content: View>: View {
    @Binding var awaitsReturn: Bool
    let onReturn: () -> Void
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(
        awaitsReturn: Binding<Bool>,
        onReturn: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        _awaitsReturn = awaitsReturn
        self.onReturn = onReturn
        self.content = content()
    }

    var body: some View {
        content
             
            .environment(\.clashIsPushedPage, true)
            .environment(
            \.clashPopRoute,
            ClashRoutePusher { _ in
                awaitsReturn = false
                dismiss()
                DispatchQueue.main.async {
                    onReturn()
                }
            }
        )
    }
}
#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashPushRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
#if os(macOS)
        let forced: Bool = {

            false

        }()
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        configuration.isPressed || forced
                            ? AnyShapeStyle(Color.primary.opacity(0.05))
                            : AnyShapeStyle(.clear)
                    )
                    .padding(.horizontal, -ClashTheme.Spacing.cardGap)
                    .padding(.vertical, -ClashTheme.Spacing.row)
            )
#else
        configuration.label
#endif
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public enum ClashPushedPageExit {
     
     
     
     
    public static func leave(
        popRoute: ClashRoutePusher?,
        dismiss: ClashDismissHandle
    ) {
         
         
         
         
         
         
         
         
         
         
        if let popRoute {
            popRoute(ClashPopToken())
        } else {
            dismiss()
        }
    }
}
