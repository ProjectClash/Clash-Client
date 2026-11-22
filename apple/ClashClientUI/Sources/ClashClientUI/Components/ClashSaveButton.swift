import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashSaveButton: View {
    private let title: ClashDisplayText
    private let isEnabled: Bool
    private let identifier: String?
    private let action: () async -> Void

    @State private var isSaving = false

    public init(
        _ title: ClashDisplayText = .copy("Save"),
        isEnabled: Bool = true,
        identifier: String? = nil,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button {
             
             
             
            guard !isSaving else { return }
            isSaving = true
            Task {
                await action()
                isSaving = false
            }
        } label: {
            ClashActionProgressLabel(title, isBusy: isSaving)
        }
         
         
        .disabled(isSaving || !isEnabled)
         
         
        .modifier(ClashOptionalIdentifier(identifier: identifier))
         
         
         
         
        .accessibilityValue(isSaving ? Text(clash: .copy("Saving…")) : Text(""))
    }
}

 
 
public struct ClashActionProgressLabel: View {
    private let title: ClashDisplayText
    private let isBusy: Bool

    public init(_ title: ClashDisplayText, isBusy: Bool) {
        self.title = title
        self.isBusy = isBusy
    }

    public var body: some View {
        Text(clash: title)
            .opacity(isBusy ? 0 : 1)
            .overlay {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(Text(clash: title))
            .accessibilityValue(isBusy ? Text(clash: .copy("Saving…")) : Text(""))
    }
}

 
 
 
 
 
struct ClashOptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
