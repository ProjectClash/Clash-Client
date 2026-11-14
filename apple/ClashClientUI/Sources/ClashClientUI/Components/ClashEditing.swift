import SwiftUI

extension View {
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashAlwaysEditing() -> some View {
#if os(macOS)
        self
#else
        environment(\.editMode, .constant(.active))
#endif
    }

     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashSelectionRowFill(_ chosen: Bool) -> some View {
#if os(iOS)
        listRowBackground(chosen ? Color(uiColor: .systemFill) : nil)
#else
        self
#endif
    }

     
     
     
     
     
     
    @ViewBuilder
    public func clashBackButtonHidden(_ hidden: Bool) -> some View {
#if os(macOS)
        self
#else
        navigationBarBackButtonHidden(hidden)
#endif
    }
}

extension View {
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashEditorFormContainer<Rows: View>(
        @ViewBuilder rows: () -> Rows
    ) -> some View {
#if os(macOS)
        Form { rows() }
            .formStyle(.grouped)
#else
        List { rows() }
#endif
    }
}

 
 
extension View {
    @ViewBuilder
    public func clashConfigurationFormSpacing() -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(ClashTheme.Spacing.standard)
                .contentMargins(.top, ClashTheme.Spacing.tight, for: .scrollContent)
        } else { self }
        #else
        self
        #endif
    }
}

 
 
 
struct ClashProfilesRootTitleModifier: ViewModifier {
    let showsDismissControl: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsDismissControl {
#if os(iOS)
            content.clashPageTitle("Profile Center")
#else
            content.clashPageTitle("Profiles")
#endif
        } else {
            content
        }
    }
}


 
struct ClashConfigurationLibraryList<Content: View>: View {
    let palette: ClashProductPalette
    let accessibilityIdentifier: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        List { content() }
            .modifier(ClashConfigurationLibraryListStyle())
            .clashConfigurationFormSpacing()
            .background(palette.canvas)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
private struct ClashConfigurationLibraryListStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
#if os(iOS)
        content.listStyle(.insetGrouped)
#else
        content
#endif
    }
}

public extension View {
     
     
     
     
    func clashDeleteConfirmation(_ name: String, isPresented: Binding<Bool>,
                                actionTitle: ClashDisplayText = .copy("Delete"),
                                message: ClashDisplayText? = nil,
                                identifier: String,
                                action: @escaping () -> Void) -> some View {
        alert(Text(clash: .format("Delete %@?", [name])), isPresented: isPresented) {
            Button(role: .destructive, action: action) { Text(clash: actionTitle) }
                .accessibilityIdentifier(identifier)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let message { Text(clash: message) }
        }
    }

     
     
     
     
     
     
     
    func clashDeleteConfirmation<Item>(presenting item: Binding<Item?>, name: (Item) -> String,
                                      actionTitle: ClashDisplayText = .copy("Delete"),
                                      message: ((Item) -> ClashDisplayText?)? = nil,
                                      identifier: String,
                                      action: @escaping (Item) -> Void) -> some View {
        alert(Text(clash: .format("Delete %@?", [item.wrappedValue.map(name) ?? ""])),
              isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
              presenting: item.wrappedValue) { presented in
            Button(role: .destructive) { action(presented) } label: { Text(clash: actionTitle) }
                .accessibilityIdentifier(identifier)
            Button("Cancel", role: .cancel) {}
        } message: { presented in
            if let text = message?(presented) { Text(clash: text) }
        }
    }

     
     
     
     
     
     
     
     
     
    func clashSwipeToDelete(identifier: String? = nil, disabled: Bool = false,
                           _ delete: (() -> Void)?) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let delete {
                Button(role: .destructive, action: delete) {
                    Label { Text("Delete") } icon: { Image(systemName: ClashSymbol.trash.rawValue) }
                }
                .tint(.red)
                .disabled(disabled)
                .modifier(ClashOptionalIdentifier(identifier: identifier))
            }
        }
    }
}

 
 
 
 
 
public struct ClashSwipeLabel: View {
    private let title: ClashDisplayText
    private let symbol: ClashSymbol

    public init(_ title: ClashDisplayText, symbol: ClashSymbol) {
        self.title = title
        self.symbol = symbol
    }

    public var body: some View {
        Label { Text(clash: title) } icon: { Image(systemName: symbol.rawValue) }
    }
}
