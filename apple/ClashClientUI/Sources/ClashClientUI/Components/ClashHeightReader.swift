import SwiftUI

 
 
 
 
 
 
 
 
private struct ClashHeightReader: ViewModifier {
    let report: ((CGFloat) -> Void)?

    func body(content: Content) -> some View {
        if let report {
            reading(content, report)
        } else {
            content
        }
    }

    @ViewBuilder
    private func reading(_ content: Content, _ report: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, *) {
            content.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                report(height)
            }
        } else {
            content.background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { report(proxy.size.height) }
                        .onChange(of: proxy.size.height) { height in report(height) }
                }
            )
        }
    }
}

extension View {
     
     
    func clashReadsHeight(_ report: ((CGFloat) -> Void)?) -> some View {
        modifier(ClashHeightReader(report: report))
    }
}
