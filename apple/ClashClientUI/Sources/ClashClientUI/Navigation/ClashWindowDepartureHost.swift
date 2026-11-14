#if os(macOS)
import Combine
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashWindowDepartureHost<Content: View, WindowGuard: View>: View {
    private let content: Content
    private let windowGuard: (ClashWindowDepartureController) -> WindowGuard
    @StateObject private var controller = ClashWindowDepartureController()

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder windowGuard: @escaping (ClashWindowDepartureController) -> WindowGuard
    ) {
        self.content = content()
        self.windowGuard = windowGuard
    }

    public var body: some View {
        let departureGuard = controller.departureGuard
        content
            .environment(\.clashRootDepartureGuard, departureGuard)
            .environment(\.clashProductModalDismiss, { [controller] in controller.closeWindow() })
            .background(windowGuard(controller))
            .alert(
                "Save your changes?",
                isPresented: Binding(
                    get: { departureGuard.isPromptPresented },
                    set: { _ in }
                )
            ) {
                 
                if departureGuard.saveBlock == nil {
                    Button("Save") { departureGuard.saveAndLeave() }
                }
                Button("Discard", role: .destructive) { departureGuard.discardAndLeave() }
                Button("Keep Editing", role: .cancel) { departureGuard.keepEditing() }
            } message: {
                if let block = departureGuard.saveBlock {
                    Text(clash: block)
                } else {
                    Text("This page has changes that have not been saved.")
                }
            }
            .background { ClashDepartureRefusalAlert(departureGuard: departureGuard) }
    }
}

 
 
 
@MainActor
public final class ClashWindowDepartureController: ObservableObject {
    let departureGuard = ClashRootDepartureGuard()
     
     
    public var closeWindow: () -> Void = {}
    private var forwarding: AnyCancellable?

    public init() {
        forwarding = departureGuard.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        departureGuard.dirtyRegistrationDidChange = { [weak self] in
            self?.objectWillChange.send()
        }
    }

     
    public var hasUnsavedChanges: Bool { departureGuard.hasDirtyRegistration }

     
     
     
    public func shouldClose() -> Bool {
        guard departureGuard.hasDirtyRegistration else { return true }
        departureGuard.requestDeparture { [weak self] in self?.closeWindow() }
        return false
    }
}
#endif
