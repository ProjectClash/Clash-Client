import SwiftUI
import os

 
 
 
 
 
 
 
struct ClashDismissPlacement: Equatable {
     
     
     
    let depth: Int?
    let isPushedPage: Bool
    let hostContext: ClashNavigationHostContext
     
     
     
    let insideModal: Bool

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    var dismisses: Bool {
        if isPushedPage { return true }
        if insideModal { return true }
        guard let depth else { return true }
        if depth > 0 { return true }
        return hostContext == .modal
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashDismissHandle: ObservableObject {
    private var action: (() -> Void)?
     
     
     
     
     
    private var productModal: (@MainActor () -> Void)?

     
     
     
     
     
     
     
     
    @MainActor
    public func closeModalOrDismiss() {
        if placement.isPushedPage {
#if os(macOS)
            if let popRoute {
                popRoute(ClashPopToken())
                return
            }
#endif
            return self()
        }
        if let productModal { productModal() } else { self() }
    }

    func bindProductModal(_ closer: (@MainActor () -> Void)?) {
        productModal = closer
    }

    func bindPopRoute(_ pop: ClashRoutePusher?) {
        popRoute = pop
    }
     
    private var popRoute: ClashRoutePusher?
    private var placement = ClashDismissPlacement(
        depth: nil, isPushedPage: false, hostContext: .standalone, insideModal: false
    )

    public init() {}

     
     
    public func callAsFunction() {


        guard placement.dismisses else { return }
        action?()
    }

    func bind(_ action: @escaping () -> Void, placement: ClashDismissPlacement) {


        self.action = action
        self.placement = placement
    }


}

 
 
 
 
 
 
 
 
 
 
private struct ClashDismissCapture: View {
    let handle: ClashDismissHandle
    @Environment(\.dismiss) private var dismiss
     
     
    @Environment(\.clashNavigationDepth) private var navigationDepth
    @Environment(\.clashIsPushedPage) private var isPushedPage
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashInsideModalPresentation) private var insideModal
    @Environment(\.clashProductModalDismiss) private var productModalDismiss
    @Environment(\.clashPopRoute) private var popRoute

    var body: some View {
         
         
         
        let _ = handle.bindProductModal(productModalDismiss)
        let _ = handle.bindPopRoute(popRoute)
        let _ = handle.bind(
            { dismiss() },
            placement: ClashDismissPlacement(
                depth: navigationDepth,
                isPushedPage: isPushedPage,
                hostContext: hostContext,
                insideModal: insideModal
            )
        )
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
    }
}

public extension View {
     
     
    func clashCapturesDismiss(_ handle: ClashDismissHandle) -> some View {
        background(ClashDismissCapture(handle: handle))
    }
}
