import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashTextFieldAlertField {
    public enum Kind: Equatable {
         
        case plain
         
        case url
    }

     
    public let placeholder: String
    public let identifier: String
    public let kind: Kind

    public init(placeholder: String, identifier: String, kind: Kind = .plain) {
        self.placeholder = placeholder
        self.identifier = identifier
        self.kind = kind
    }
}

 
 
public struct ClashTextFieldAlertRequest {
    public let title: String
    public let placeholder: String
     
    public let text: String
    public let kind: ClashTextFieldAlertField.Kind
    public let identifier: String
    public let confirmTitle: String
    public let cancelTitle: String
     
    public let isConfirmEnabled: (String) -> Bool
     
    public let textChanged: (String) -> Void
     
    public let confirm: (String) -> Void
    public let cancel: () -> Void

    public init(title: String, placeholder: String, text: String, kind: ClashTextFieldAlertField.Kind,
                identifier: String, confirmTitle: String, cancelTitle: String,
                isConfirmEnabled: @escaping (String) -> Bool, textChanged: @escaping (String) -> Void,
                confirm: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.text = text
        self.kind = kind
        self.identifier = identifier
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isConfirmEnabled = isConfirmEnabled
        self.textChanged = textChanged
        self.confirm = confirm
        self.cancel = cancel
    }
}

 
@MainActor
public enum ClashTextFieldAlertHost {
    public enum Mode: Equatable {
         
        case swiftUI
         
        case host
    }

     
     
    public static var present: ((ClashTextFieldAlertRequest) -> () -> Void)?

     
    public static var forcesHost = false

     
    public nonisolated static func mode(majorSystemVersion: Int) -> Mode {
        majorSystemVersion >= 16 ? .swiftUI : .host
    }

    static var usesHost: Bool {
#if os(iOS)
        present != nil && (forcesHost || systemDrawsNoField)
#else
        false
#endif
    }

     
    private static let systemDrawsNoField =
        mode(majorSystemVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) == .host
}

public extension View {
     
     
     
     
     
     
     
     
     
    func clashTextFieldAlert<Item>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting item: Item?,
        text: Binding<String>,
        field: ClashTextFieldAlertField,
        confirm: String = "OK",
        confirmIdentifier: String? = nil,
        isConfirmEnabled: @escaping (Item, String) -> Bool = { _, _ in true },
        onConfirm: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(ClashTextFieldAlertModifier(title: title, isPresented: isPresented, item: item, text: text,
                                             field: field, confirm: confirm, confirmIdentifier: confirmIdentifier,
                                             isConfirmEnabled: isConfirmEnabled, onConfirm: onConfirm))
    }

     
    func clashTextFieldAlert(
        _ title: String,
        isPresented: Binding<Bool>,
        text: Binding<String>,
        field: ClashTextFieldAlertField,
        confirm: String = "OK",
        confirmIdentifier: String? = nil,
        isConfirmEnabled: @escaping (String) -> Bool = { _ in true },
        onConfirm: @escaping (String) -> Void
    ) -> some View {
        clashTextFieldAlert(title, isPresented: isPresented, presenting: (), text: text, field: field,
                            confirm: confirm, confirmIdentifier: confirmIdentifier,
                            isConfirmEnabled: { _, typed in isConfirmEnabled(typed) },
                            onConfirm: { _, typed in onConfirm(typed) })
    }
}

struct ClashTextFieldAlertModifier<Item>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let item: Item?
    @Binding var text: String
    let field: ClashTextFieldAlertField
    let confirm: String
    let confirmIdentifier: String?
    let isConfirmEnabled: (Item, String) -> Bool
    let onConfirm: (Item, String) -> Void
    @Environment(\.locale) private var locale
     
    @State private var takeDown: (() -> Void)?
     
     
     
    @State private var latest = Latest()

    private final class Latest {
        var drawn: Drawn?
        func remember(_ drawn: Drawn?) { self.drawn = drawn }
    }

     
     
    private struct Drawn {
        let title: String
        let isPresented: Binding<Bool>
        let item: Item?
        let text: Binding<String>
        let field: ClashTextFieldAlertField
        let confirm: String
        let isConfirmEnabled: (Item, String) -> Bool
        let onConfirm: (Item, String) -> Void
        let locale: Locale

        func request(_ present: (ClashTextFieldAlertRequest) -> () -> Void) -> (() -> Void)? {
            guard let item else { return nil }
            let (presented, typed, isConfirmEnabled, onConfirm) = (isPresented, text, isConfirmEnabled, onConfirm)
            return present(ClashTextFieldAlertRequest(
                title: ClashCopy.string(title, locale: locale),
                placeholder: ClashCopy.string(field.placeholder, locale: locale),
                text: typed.wrappedValue,
                kind: field.kind,
                identifier: field.identifier,
                confirmTitle: ClashCopy.string(confirm, locale: locale),
                cancelTitle: ClashCopy.string("Cancel", locale: locale),
                isConfirmEnabled: { isConfirmEnabled(item, $0) },
                textChanged: { typed.wrappedValue = $0 },
                confirm: { value in
                    typed.wrappedValue = value
                    presented.wrappedValue = false
                    onConfirm(item, value)
                },
                cancel: { presented.wrappedValue = false }))
        }
    }

    private var drawn: Drawn {
        Drawn(title: title, isPresented: $isPresented, item: item, text: $text, field: field, confirm: confirm,
              isConfirmEnabled: isConfirmEnabled, onConfirm: onConfirm, locale: locale)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if ClashTextFieldAlertHost.usesHost {
             
            let _ = latest.remember(isPresented ? drawn : nil)
             
             
             
             
            content
                .onAppear { if isPresented { show() } }
                .onChange(of: isPresented) { presented in
                    if presented { show() } else { hide() }
                }
        } else {
            content.alert(ClashCopy.key(title), isPresented: $isPresented, presenting: item) { item in
                TextField(ClashCopy.key(field.placeholder), text: $text)
                    .modifier(ClashTextFieldAlertKeyboard(kind: field.kind))
                    .accessibilityIdentifier(field.identifier)
                 
                 
                Button(ClashCopy.key(confirm)) { onConfirm(item, text) }
                    .disabled(!isConfirmEnabled(item, text))
                    .accessibilityIdentifier(confirmIdentifier ?? "")
                Button(ClashCopy.key("Cancel"), role: .cancel) {}
            }
        }
    }

    private func show() {
        guard takeDown == nil, let present = ClashTextFieldAlertHost.present else { return }
        takeDown = (latest.drawn ?? drawn).request(present)
    }

    private func hide() {
        takeDown?()
        takeDown = nil
    }
}

 
private struct ClashTextFieldAlertKeyboard: ViewModifier {
    let kind: ClashTextFieldAlertField.Kind

    func body(content: Content) -> some View {
        switch kind {
        case .plain:
            content
        case .url:
#if os(macOS)
            content.autocorrectionDisabled()
#else
            content
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
#endif
        }
    }
}
