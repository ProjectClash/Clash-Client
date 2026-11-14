import SwiftUI

 
 
 
public struct ClashModalActionBar: View {
    private let primaryTitle: String
    private let primaryDisabled: Bool
    private let primaryHint: String?
    private let isBusy: Bool
    private let busyTitle: String?
    private let onPrimary: () -> Void

    public init(
        primaryTitle: String,
        primaryDisabled: Bool = false,
         
         
         
         
         
         
         
        primaryHint: String? = nil,
        isBusy: Bool = false,
        busyTitle: String? = nil,
        onPrimary: @escaping () -> Void
    ) {
        self.primaryTitle = primaryTitle
        self.primaryDisabled = primaryDisabled
        self.primaryHint = primaryHint
        self.isBusy = isBusy
        self.busyTitle = busyTitle
        self.onPrimary = onPrimary
    }

    public var body: some View {
        VStack(spacing: ClashTheme.Spacing.tight) {
             
             
             
             
             
             
             
             
             
             
             
             
            if primaryDisabled, !isBusy, let primaryHint {
                Text(clash: Self.visibleHint(primaryHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
            primaryButton
        }
        .padding(
            .horizontal,
            ClashTheme.MacOS.ProductModal.contentHorizontalInset
        )
        .padding(.vertical, ClashTheme.Spacing.standard)
        .modifier(ClashModalActionBarSurface())
    }

     
     
     
     
    static func visibleHint(_ hint: String) -> ClashDisplayText {
        .copy(hint)
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
             
             
             
            if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                ClashActionProgressLabel(.copy(primaryTitle), isBusy: isBusy)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Capsule())
            } else {
                ClashActionProgressLabel(.copy(primaryTitle), isBusy: isBusy)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: ClashTheme.Control.minimumHitTarget)
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .background(
            Capsule().fill(
                 
                 
                primaryDisabled || isBusy
                    ? AnyShapeStyle(.tint.opacity(0.35))
                    : AnyShapeStyle(.tint)
            )
        )
        .clipShape(Capsule())
        .disabled(primaryDisabled || isBusy)
#if !os(tvOS)
        .keyboardShortcut(.defaultAction)
#endif
        .accessibilityIdentifier("clash.modal.primary")
         
         
         
         
        .accessibilityValue(
            isBusy ? ClashCopy.string(busyTitle ?? "Saving", locale: .current) : (primaryDisabled ? (primaryHint.map { ClashDisplayText.copy($0).resolved(locale: Locale.current) } ?? "") : "")
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashModalActionBarSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            content
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(.bar)
                        Divider()
                    }
                     
                     
                     
                    .ignoresSafeArea(edges: .bottom)
                }
        } else {
            content
        }
    }
}
