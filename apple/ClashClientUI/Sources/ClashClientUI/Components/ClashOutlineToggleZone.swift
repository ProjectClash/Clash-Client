import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashOutlineToggleZone: ViewModifier {
    @Binding var isExpanded: Bool

    @Environment(\.layoutDirection) private var layoutDirection

     
     
     
     
     
     
    static let inner: CGFloat = 16
     
     
    static let reach: CGFloat = 64

    func body(content: Content) -> some View {
#if os(iOS)
        content.overlay(alignment: .trailing) {
            Color.clear
                .frame(width: Self.inner + Self.reach)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .offset(x: layoutDirection == .rightToLeft ? -Self.reach : Self.reach)
                .accessibilityElement()
                .accessibilityValue(ClashCopy.key(isExpanded ? "Expanded" : "Collapsed"))
                .accessibilityAction(named: Text(ClashCopy.key(isExpanded ? "Collapse" : "Expand"))) { toggle() }
        }
#else
        content
#endif
    }

     
     
    private func toggle() {
        withAnimation { isExpanded.toggle() }
    }
}

extension View {
     
    func clashOutlineToggle(isExpanded: Binding<Bool>) -> some View {
        modifier(ClashOutlineToggleZone(isExpanded: isExpanded))
    }
}
