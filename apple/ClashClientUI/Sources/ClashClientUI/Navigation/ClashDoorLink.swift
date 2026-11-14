import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
public struct ClashDoorLink<Route: Hashable, Destination: View, RowLabel: View>: View {
    private let route: Route
    @Binding private var selection: Route?
    private let destination: () -> Destination
    private let label: () -> RowLabel
#if os(macOS)
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashNavigationDepth) private var depth
#endif

    public init(
        _ route: Route,
        selection: Binding<Route?>,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> RowLabel
    ) {
        self.route = route
        self._selection = selection
        self.destination = destination
        self.label = label
    }

    public var body: some View {
#if os(macOS)
         
         
         
         
        let _ = ClashPushAuthority.trace("door", hostContext, depth)
        if ClashPushAuthority.canPush(hostContext: hostContext, depth: depth) {
            ClashRoutedViewLink {
                destination()
            } label: {
                label()
            }
        } else {
            Button {
                 
                 
                ClashPageProbe.markNavigation()
                selection = route
            } label: {
                HStack(spacing: 6) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: ClashSymbol.chevronForward.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
#else
        ClashRoutedViewLink {
            destination()
        } label: {
            label()
        }
#endif
    }
}

 
 
 
 
public struct ClashDoorPayload: Identifiable {
    public let id: String
    public let title: String
    public let destination: AnyView

    public init(id: String, title: String, destination: AnyView) {
        self.id = id
        self.title = title
        self.destination = destination
    }
}

 
public struct ClashPayloadDoorLink<Destination: View, RowLabel: View>: View {
    private let id: String
    private let title: String
    @Binding private var selection: ClashDoorPayload?
    private let destination: () -> Destination
    private let label: () -> RowLabel
#if os(macOS)
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashNavigationDepth) private var depth
#endif

    public init(
        id: String,
        title: String,
        selection: Binding<ClashDoorPayload?>,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> RowLabel
    ) {
        self.id = id
        self.title = title
        self._selection = selection
        self.destination = destination
        self.label = label
    }

    public var body: some View {
#if os(macOS)
        if ClashPushAuthority.canPush(hostContext: hostContext, depth: depth) {
            ClashRoutedViewLink {
                destination()
            } label: {
                label()
            }
        } else {
            Button {
                selection = ClashDoorPayload(
                    id: id,
                    title: title,
                    destination: AnyView(destination())
                )
            } label: {
                HStack(spacing: 6) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: ClashSymbol.chevronForward.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
#else
        ClashRoutedViewLink {
            destination()
        } label: {
            label()
        }
#endif
    }
}

 
 
 
 
 
 
 
 
 
 
public struct ClashDoorSaving {
    public let isDirty: () -> Bool
     
     
    public let save: (@escaping (Bool) -> Void) -> Void
    public let discard: () -> Void

    public init(
        isDirty: @escaping () -> Bool,
        save: @escaping (@escaping (Bool) -> Void) -> Void,
        discard: @escaping () -> Void
    ) {
        self.isDirty = isDirty
        self.save = save
        self.discard = discard
    }
}

public extension View {
     
    @ViewBuilder
    func clashDoorPresenter(
        payload: Binding<ClashDoorPayload?>,
        saving: ClashDoorSaving? = nil
    ) -> some View {
#if os(macOS)
        clashProductModal(item: payload, role: .form) { item in
            ClashSingleColumnNavigationContainer {
                 
                 
                item.destination
                    .clashProductModalRoot(title: .copy(item.title))  
                    .clashDoorSaveBar(saving) { payload.wrappedValue = nil }
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    .clashRegistersDeparture(
                        isDirty: saving?.isDirty() ?? false,
                        save: saving?.save ?? { $0(true) },
                        discard: saving?.discard ?? {}
                    )
            }
        }
#else
        self
#endif
    }

     
     
     
     
    @ViewBuilder
    func clashDoorPresenter<Route: Hashable & Identifiable, C: View>(
        selection: Binding<Route?>,
        title: @escaping (Route) -> String,
        saving: ClashDoorSaving? = nil,
        @ViewBuilder content: @escaping (Route) -> C
    ) -> some View {
#if os(macOS)
         
         
         
         
        clashProductModal(item: selection, role: .form) { route in
            ClashSingleColumnNavigationContainer {
                content(route)
                    .clashProductModalRoot(title: .copy(title(route)))  
                    .clashDoorSaveBar(saving) { selection.wrappedValue = nil }
                     
                     
                     
                    .clashRegistersDeparture(
                        isDirty: saving?.isDirty() ?? false,
                        save: saving?.save ?? { $0(true) },
                        discard: saving?.discard ?? {}
                    )
            }
        }
#else
        self
#endif
    }
}

#if os(macOS)
private extension View {
     
     
     
     
    @ViewBuilder
    func clashDoorSaveBar(_ saving: ClashDoorSaving?, close: @escaping () -> Void) -> some View {
        if let saving {
            safeAreaInset(edge: .bottom, spacing: 0) {
                ClashModalActionBar(
                    primaryTitle: "Save",
                    primaryDisabled: !saving.isDirty(),
                    onPrimary: { saving.save { saved in if saved { close() } } }
                )
            }
        } else {
            self
        }
    }
}
#endif
