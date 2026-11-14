import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashSheetCloseButton: View {
    private let dismiss: () -> Void
    @Environment(\.clashProductModalDismiss) private var productModalDismiss

    public init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }

    public var body: some View {
        Button(action: close) {
            Label("Close", systemImage: "xmark")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("sheet.close")
    }

    private func close() {
        (productModalDismiss ?? dismiss)()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashOpeningCancelButton: View {
    @StateObject private var dismiss = ClashDismissHandle()
    @Environment(\.clashNavigationDepth) private var navigationDepth
    @Environment(\.clashIsPushedPage) private var isPushedPage
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashInsideModalPresentation) private var insideModal

    public init() {}

    public var body: some View {
        let placement = ClashDismissPlacement(
            depth: navigationDepth, isPushedPage: isPushedPage, hostContext: hostContext, insideModal: insideModal
        )
        if ClashSheetSurface.coversOnThisSystem, placement.dismisses {
            Button {
                dismiss.closeModalOrDismiss()
            } label: {
                Text(ClashCopy.key("Cancel"))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("opening.cancel")
            .clashCapturesDismiss(dismiss)
        }
    }
}

 
 
public struct ClashOpeningProgress: View {
    public init() {}

    public var body: some View {
        VStack(spacing: ClashTheme.Spacing.row) {
            ProgressView()
            ClashOpeningCancelButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
