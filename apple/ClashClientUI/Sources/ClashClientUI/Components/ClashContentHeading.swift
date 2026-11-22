import SwiftUI

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashContentHeading(_ title: ClashDisplayText, watchAs: String? = nil) -> some View {
        modifier(ClashContentHeadingModifier(title: title))
             
             
             
             
             
            .clashFrameWatch(title.frameWatchLabel(overriddenBy: watchAs))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashRootHeading(_ title: ClashDisplayText, watchAs: String? = nil) -> some View {
        modifier(ClashRootHeadingModifier(title: title, watchAs: watchAs))
    }
}

 
 
 
 
private struct ClashContentHeadingModifier: ViewModifier {
    @Environment(\.clashShellDrawsRootHeading)
    private var railOwnsHeading

    let title: ClashDisplayText

    func body(content: Content) -> some View {
        if railOwnsHeading {
            content.navigationTitle("")
        } else {
            content
                .navigationTitle("")
                .environment(\.clashRegularRootLargeTitle, ClashRootLargeTitle.published(title))
        }
    }
}

 
 
 
 
 
private struct ClashRootHeadingModifier: ViewModifier {
    @Environment(\.clashShellDrawsRootHeading)
    private var railOwnsHeading

    let title: ClashDisplayText
    let watchAs: String?

    func body(content: Content) -> some View {
         
         
         
         
         
        if railOwnsHeading {
#if os(macOS)
             
             
             
             
             
             
             
            content.navigationTitle(Text(clash: title))
                .clashFrameWatch(title.frameWatchLabel(overriddenBy: watchAs))
#else
            content.navigationTitle("")
                .clashFrameWatch(title.frameWatchLabel(overriddenBy: watchAs))
#endif
        } else {
            content.clashPageTitle(title, watchAs: watchAs)
        }
    }
}

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashPageTitle(_ title: ClashDisplayText, watchAs: String? = nil) -> some View {
        navigationTitle(Text(clash: title))
            .modifier(ClashInlinePageTitle())
             
             
             
             
             
             
            .clashFrameWatch(title.frameWatchLabel(overriddenBy: watchAs))
    }
}

private struct ClashInlinePageTitle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 17.0, *) {
            content.toolbarTitleDisplayMode(.inline)
        } else {
            content.navigationBarTitleDisplayMode(.inline)
        }
#else
        content
#endif
    }
}
