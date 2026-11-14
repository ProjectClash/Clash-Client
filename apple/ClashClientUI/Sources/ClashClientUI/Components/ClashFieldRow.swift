import SwiftUI

 
 
 
public struct ClashFieldRow: View {
    private let title: String
    private let hint: String
    private let text: Binding<String>
    private let secure: Bool
    private let reveals: Binding<Bool>?
    private let monospaced: Bool
    private let suffix: String?
    private let compactValue: Bool
    private let identifier: String?
    private let subtitle: ClashDisplayText?
     
     
     
     
    private let onEditingEnded: (() -> Void)?
    @FocusState private var focused: Bool
     
     
     
     
     
     
     
     
     
     
     
    @State private var endedOnDisappearWith: String?
     
     
     
     
     
     
     
     
     
    @State private var holdsFocus = false

    public init(
        _ title: String,
        hint: String,
        text: Binding<String>,
        secure: Bool = false,
        reveals: Binding<Bool>? = nil,
        monospaced: Bool = false,
        suffix: String? = nil,
        compactValue: Bool = false,
        identifier: String? = nil,
        subtitle: ClashDisplayText? = nil,
        onEditingEnded: (() -> Void)? = nil
    ) {
        self.title = title
        self.hint = hint
        self.text = text
        self.secure = secure
        self.reveals = reveals
        self.monospaced = monospaced
        self.suffix = suffix
        self.compactValue = compactValue
        self.identifier = identifier
        self.subtitle = subtitle
        self.onEditingEnded = onEditingEnded
    }

    public var body: some View {
         
         
         
         
         
         
         
         
         
         
        let _ = ClashPageProbe.isEnabled
            ? ClashPageProbe.countRowEvaluation(identifier ?? title)
            : ()
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ClashCopy.key(title))
                    .lineLimit(1)
                if let subtitle {
                     
                     
                    Text(clash: subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
             
             
             
             
            .onTapGesture { focused = true }
            Spacer(minLength: ClashTheme.Spacing.compact)
            if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                valueField
                    .clashMacFieldValueWidth(compact: compactValue)
            } else {
                valueField
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let reveals {
                Button {
                    reveals.wrappedValue.toggle()
                } label: {
                    Image(
                        systemName:
                            (reveals.wrappedValue
                                ? ClashSymbol.eyeSlash
                                : ClashSymbol.eye).rawValue
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    reveals.wrappedValue ? "Hide value" : "Show value"
                )
            }
             
             
             
             
            if let suffix,
                ClashPlatformLayout.pageUsesSystemSettingsIdiom
                    || !text.wrappedValue.isEmpty
            {
                Text(ClashCopy.key(suffix))
                    .foregroundStyle(.secondary)
            }
        }
#if os(macOS)
        .frame(
            maxWidth: .infinity,
             
             
            minHeight: ClashPlatformLayout.pageUsesSystemSettingsIdiom
                ? 0
                : ClashTheme.Control.fullWidthRowMinHeight
        )
#else
        .frame(maxWidth: .infinity)
#endif
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { focused = true }
        )
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        .onAppear {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            holdsFocus = focused
        }
        .onDisappear {
             
             
             
            guard holdsFocus else { return }
            holdsFocus = false
            endedOnDisappearWith = text.wrappedValue
            onEditingEnded?()
        }
        .onChange(of: focused) { isFocused in
            holdsFocus = isFocused
            guard !isFocused else { return }
            let ends = Self.focusLossEndsTheEdit(endedOnDisappearWith: endedOnDisappearWith,
                                                 text: text.wrappedValue)
            endedOnDisappearWith = nil
            if ends { onEditingEnded?() }
        }
        .onSubmit { onEditingEnded?() }
        .accessibilityElement(children: .contain)
        .clashFieldRowIdentifier(identifier)
    }

     
     
    static func focusLossEndsTheEdit(endedOnDisappearWith ended: String?, text: String) -> Bool {
        guard let ended else { return true }
        return ended != text
    }

    @ViewBuilder
    private var valueField: some View {
        if secure && reveals?.wrappedValue != true {
            ClashSecureValueField(
                hint: hint,
                label: title,
                bordered: ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                text: text
            )
            .font(monospaced ? .body.monospaced() : .body)
            .focused($focused)
            .clashFieldIdentifier(identifier)
        } else {
            ClashValueField(
                hint: hint,
                label: title,
                bordered: ClashPlatformLayout.pageUsesSystemSettingsIdiom,
                text: text
            )
            .font(monospaced ? .body.monospaced() : .body)
            .focused($focused)
            .clashFieldIdentifier(identifier)
        }
    }

}

 
 
extension View {
    @ViewBuilder
    func clashFieldIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    @ViewBuilder
    func clashFieldRowIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier("\(identifier).row")
        } else {
            self
        }
    }
}

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashMacFieldValueWidth(compact: Bool = false) -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
             
             
             
             
             
             
            frame(maxWidth: compact ? 96 : 260)
        } else {
            self
        }
    }
}
