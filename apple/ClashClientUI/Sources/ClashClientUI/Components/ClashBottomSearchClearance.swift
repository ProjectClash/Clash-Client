import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashBottomSearchClearance: ViewModifier {
    static let points: CGFloat = 24
    @Environment(\.clashSearchFieldAtFoot) private var atFoot

    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26, *), atFoot {
            content.safeAreaPadding(.bottom, Self.points)
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct ClashSearchFieldAtFootKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
     
     
     
    public var clashSearchFieldAtFoot: Bool {
        get { self[ClashSearchFieldAtFootKey.self] }
        set { self[ClashSearchFieldAtFootKey.self] = newValue }
    }

     
     
     
     
    public var clashSearchFieldClearance: CGFloat {
#if os(iOS)
        if #available(iOS 26, *), clashSearchFieldAtFoot { return ClashBottomSearchClearance.points }
#endif
        return 0
    }
}

public extension View {
     
    func clashBottomSearchClearance() -> some View {
        modifier(ClashBottomSearchClearance())
    }
}
