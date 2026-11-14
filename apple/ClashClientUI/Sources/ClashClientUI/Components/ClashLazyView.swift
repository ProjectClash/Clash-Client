import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashLazyView<Content: View>: View {
    private let build: () -> Content
    private let defersOneTurn: Bool

    public init(defersOneTurn: Bool = false, @ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
        self.defersOneTurn = defersOneTurn
    }

    @ViewBuilder
    public var body: some View {
#if os(macOS)
        oneTurnLater
#else
        if defersOneTurn { oneTurnLater } else { build() }
#endif
    }

    private var oneTurnLater: some View {
        ClashDeferredPageContent {
            build()
        } placeholder: {
            ClashPageLoadingPlaceholder(title: .copy("Loading"))
        }
    }
}
