import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashStableNavigationLink<
    Value: Hashable,
    Destination: View,
    Label: View
>: View {
    private let value: Value
    private let destination: () -> Destination
    private let label: Label

    public init(
        value: Value,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.value = value
        self.destination = destination
        self.label = label()
    }

    @Environment(\.clashPushRoute) private var pushRoute

    public var body: some View {
#if os(macOS)
         
         
         
         
         
         
         
         
         
        if let pushRoute {
            Button {
                pushRoute(value)
            } label: {
                 
                 
                 
                 
                HStack(spacing: 6) {
                    label
                     
                     
                     
                    Spacer(minLength: ClashTheme.Spacing.row)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
             
             
             
             
             
            .buttonStyle(ClashPushRowButtonStyle())
        } else {
            NavigationLink(value: value) {
                label
            }
        }
#else
         
         
         
         
         
         
         
         
         
         
         
         
         
        if ClashPlatformLayout.regularShellKeepsContainer, let pushRoute {
             
            Button {
                pushRoute(value)
            } label: {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: ClashTheme.Spacing.row)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ClashPushRowButtonStyle())
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
}

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashStableNavigationDestination<
        Value: Hashable,
        Destination: View
    >(
        for data: Value.Type,
        @ViewBuilder destination: @escaping (Value) -> Destination
    ) -> some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            modifier(ClashStableDestinationModifier(destination: destination))
        } else {
             
             
            self
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
private struct ClashStableDestinationModifier<
    Value: Hashable,
    Destination: View
>: ViewModifier {
    let destination: (Value) -> Destination

    @Environment(\.clashPushRoute) private var pushRoute

    func body(content: Content) -> some View {
        content.navigationDestination(for: Value.self) { value in
            ClashDestinationPopScope {
                ClashLazyView {
                    destination(value)
                }
                    .clashPushedDetailPage()
                    .environment(\.clashPushRoute, pushRoute)
                    .modifier(ClashSetterRoutedBack())
                     
                     
                     
                    .environment(\.clashRegularShellOwnsCanvas, true)
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
private struct ClashDestinationPopScope<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss
     
     
     
     
    @State private var token = UUID()

    var body: some View {
        content.environment(
            \.clashPopRoute,
            ClashRoutePusher(token: token) { _ in dismiss() }
        )
         
         
         
        .environment(\.clashDeparturePage, token)
    }
}


 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public struct ClashValueRowLink<Value: Hashable, RowLabel: View>: View {
    private let value: Value
    private let label: RowLabel
    @Environment(\.clashPushRoute) private var pushRoute

    public init(value: Value, @ViewBuilder label: () -> RowLabel) {
        self.value = value
        self.label = label()
    }

    public var body: some View {
#if os(macOS)
        if let pushRoute {
             
             
             
             
             
            Button {
                pushRoute(value)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: value) { label }
        }
#else
        NavigationLink(value: value) { label }
#endif
    }
}
