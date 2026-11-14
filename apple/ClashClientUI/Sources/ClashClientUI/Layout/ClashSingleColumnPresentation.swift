import SwiftUI

 
 
 
 
 
 
 
 
public enum ClashModalPresentationRole: Sendable {
    case page
    case form
    case fitted
}

 
 
 
 
 
 
enum ClashNavigationHostContext: Sendable {
    case standalone
    case regularDetail
    case modal
}

private struct ClashNavigationHostContextKey: EnvironmentKey {
    static let defaultValue = ClashNavigationHostContext.standalone
}

extension EnvironmentValues {
    var clashNavigationHostContext: ClashNavigationHostContext {
        get { self[ClashNavigationHostContextKey.self] }
        set { self[ClashNavigationHostContextKey.self] = newValue }
    }
}

 
 
 
 
 
 
enum ClashSingleColumnNavigationPolicy {
    static func buildsHost(
        ownsNavigationContainer: Bool,
        hostContext: ClashNavigationHostContext,
        isPushedPage: Bool = false
    ) -> Bool {
        guard ownsNavigationContainer else { return false }
         
         
         
         
         
         
         
         
         
        if isPushedPage { return false }
        switch hostContext {
        case .standalone:
            return true
        case .regularDetail, .modal:
            return false
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashIsPushedPageKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var clashIsPushedPage: Bool {
        get { self[ClashIsPushedPageKey.self] }
        set { self[ClashIsPushedPageKey.self] = newValue }
    }
}

struct ClashNavigationDepthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var clashNavigationDepth: Int? {
        get { self[ClashNavigationDepthKey.self] }
        set { self[ClashNavigationDepthKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
public struct ClashSingleColumnNavigationContainer<Content: View>: View {
    private let ownsNavigationContainer: Bool
    private let content: Content
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashIsPushedPage) private var isPushedPage
    @Environment(\.clashInsideModalPresentation) private var insideModal

    public init(
        ownsNavigationContainer: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.ownsNavigationContainer = ownsNavigationContainer
        self.content = content()
    }

     
     
    private func trace(_ builds: Bool) {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1"
        else { return }
        FileHandle.standardError.write(
            "[nav] container owns=\(ownsNavigationContainer) host=\(hostContext) insideModal=\(insideModal) builds=\(builds)\n"
                .data(using: .utf8)!
        )
    }

    @ViewBuilder
    public var body: some View {
        let buildsHost = ClashSingleColumnNavigationPolicy.buildsHost(
            ownsNavigationContainer: ownsNavigationContainer,
            hostContext: hostContext,
             
             
            isPushedPage: isPushedPage
        )
        let _ = trace(buildsHost)
        if buildsHost {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
                ClashModernSingleColumnNavigationHost(
                    insideModal: insideModal
                ) {
                    content
                }
            } else {
#if os(macOS)
                 
                 
                 
                NavigationView {
                    content
                }
#else
                NavigationView {
                    content
                }
                .navigationViewStyle(.stack)
#endif
            }
        } else {
            content
        }
    }
}

 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
private struct ClashModernSingleColumnNavigationHost<Content: View>: View {
    private let insideModal: Bool
    private let content: Content
    @State private var path = NavigationPath()
    @State private var managedRoutes: [ClashViewRoute?] = []
     
     
     
     
     
     
     
    @State private var hostedRoutes: [ClashViewRoute] = []

     
    @State private var pushTokens = ClashRoutePusherTokens()
     
     
    @State private var instanceID = UUID()

#if os(macOS)
     
     
     
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
#endif

    init(
        insideModal: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.insideModal = insideModal
        self.content = content()
    }

    var body: some View {
        let _ = navTrace("body")
        return NavigationStack(path: pathBinding) {
            content.navigationDestination(
                for: ClashViewRoute.self
            ) { route in
                routedDestination(route)
            }
        }
        .environment(
            \.clashPushRoute,
            ClashRoutePusher(token: pushTokens.push) { value in
                push(value)
            }
        )
        .environment(
            \.clashPopRoute,
            ClashRoutePusher(token: pushTokens.pop) { _ in pop() }
        )
        .environment(
            \.clashNavigationHostContext,
            insideModal ? .modal : .standalone
        )
         
        .environment(\.clashNavigationDepth, 0)
        .onDisappear(perform: discardRoutes)
    }

    private var pathBinding: Binding<NavigationPath> {
        Binding(
            get: { path },
            set: { updated in
                 
                 
                 
                guard updated != path else { return }
                let removedCount = max(0, path.count - updated.count)
                let removed = managedRoutes.suffix(removedCount)
                    .compactMap { $0 }
                if removedCount > 0 {
                    managedRoutes.removeLast(
                        min(removedCount, managedRoutes.count)
                    )
                } else if updated.count > managedRoutes.count {
                    managedRoutes.append(
                        contentsOf: repeatElement(
                            nil,
                            count: updated.count - managedRoutes.count
                        )
                    )
                }
                path = updated
                for route in removed.reversed() {
                    DispatchQueue.main.async {
                        ClashViewRouteRegistry.returnFrom(route)
                    }
                }
            }
        )
    }

    private func navTrace(_ what: String) {
        guard ProcessInfo.processInfo.environment["CLASH_NAV_TRACE"] == "1"
        else { return }
        FileHandle.standardError.write(
            "[nav] host \(what) path=\(path.count) inst=\(instanceID.uuidString.prefix(6))\n"
                .data(using: .utf8)!
        )
    }

    private func push(_ value: any Hashable) {
        navTrace("push")
         
         
         
         
         
         
         
        ClashNavigationTransaction.applyPathChange {
            path.append(value)
            managedRoutes.append(value as? ClashViewRoute)
            if let route = value as? ClashViewRoute {
                hostedRoutes.append(route)
            }
        }
    }

    private func pop() {
        var updated = path
        guard !updated.isEmpty else { return }
        updated.removeLast()
        let binding = pathBinding
        ClashNavigationTransaction.applyPathChange {
            binding.wrappedValue = updated
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func adoptSystemPushedRoute(_ route: ClashViewRoute) {
        guard let last = managedRoutes.indices.last else { return }
        guard managedRoutes[last] == nil else { return }
        managedRoutes[last] = route
    }

    private func routedDestination(_ route: ClashViewRoute) -> some View {
        let _ = navTrace("destination")
        return ClashLazyView {
            ClashViewRouteRegistry.view(for: route)
        }
            .onAppear { adoptSystemPushedRoute(route) }
            .clashPushedDetailPage()
             
             
             
             
             
             
             
            .environment(\.clashIsPushedPage, true)
            .onAppear { ClashPushClock.arrived() }
            .environment(
                \.clashPushRoute,
                ClashRoutePusher(token: pushTokens.push) { nested in
                    push(nested)
                }
            )
            .environment(
                \.clashPopRoute,
                ClashRoutePusher(token: pushTokens.pop) { _ in pop() }
            )
            .environment(
                \.clashNavigationHostContext,
                insideModal ? .modal : .standalone
            )
            .environment(\.clashNavigationDepth, path.count)
             
             
             
            .clashDeparturePage()
             
             
            .environment(\.clashProductChromeApplied, false)
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
#if os(macOS)
            .environment(\.clashInsideProductModalPresentation, insideProductModal)
#endif
    }

    private func discardRoutes() {
         
         
        for route in hostedRoutes {
            ClashViewRouteRegistry.discard(route)
        }
        for route in managedRoutes.compactMap({ $0 }) {
            ClashViewRouteRegistry.discard(route)
        }
        hostedRoutes.removeAll()
    }
}

public extension View {
     
     
     
     
     
    func clashModalPresentation(
        _ role: ClashModalPresentationRole
    ) -> some View {
        modifier(ClashModalSizingPolicy(role: role))
            .modifier(ClashModalSurfacePolicy())
             
             
             
             
            .environment(\.clashNavigationHostContext, .standalone)
             
             
            .environment(\.clashIsPushedPage, false)
             
             
             
             
             
            .environment(\.clashInsideModalPresentation, true)
             
             
             
             
             
             
             
            .modifier(ClashNativePresentationOwnsDismiss())
             
             
             
             
            .environment(\.clashProductChromeApplied, false)
    }
}

private struct ClashInsideModalPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

 
 
private struct ClashNativePresentationOwnsDismiss: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content.environment(\.clashProductModalDismiss, nil)
#endif
    }
}

public extension EnvironmentValues {
     
    var clashInsideModalPresentation: Bool {
        get { self[ClashInsideModalPresentationKey.self] }
        set { self[ClashInsideModalPresentationKey.self] = newValue }
    }
}

private struct ClashModalSizingPolicy: ViewModifier {
    let role: ClashModalPresentationRole

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, *) {
            switch role {
            case .page:
                content.presentationSizing(.page)
            case .form:
                content.presentationSizing(.form)
            case .fitted:
                content.presentationSizing(.fitted)
            }
        } else {
            content
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashModalSurfacePolicy: ViewModifier {
    @Environment(\.clashDetailCanvas) private var inheritedCanvas

    private var canvas: Color {
        inheritedCanvas ?? fallbackCanvas
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
         
         
         
         
         
         
         
         
         
         
         
        content
            .formStyle(.grouped)
            .listStyle(.inset)
#else
        if #available(iOS 18.0, tvOS 18.0, *) {
            content
                .environment(\.clashDetailCanvas, canvas)
                .presentationBackground(canvas)
        } else {
            content
                .environment(\.clashDetailCanvas, canvas)
        }
#endif
    }

    private var fallbackCanvas: Color {
#if os(macOS)
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .black
                    : .windowBackgroundColor
            }
        )
#elseif os(tvOS)
        Color(uiColor: .black)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }
}

public extension View {
     
     
     
     
     
     
     
    @ViewBuilder
    func clashWindowContainerBackground(_ color: Color) -> some View {
#if os(macOS)
        if #available(macOS 15.0, *) {
            self.containerBackground(color, for: .window)
        } else {
            background(color.ignoresSafeArea())
        }
#else
        self
#endif
    }
}
