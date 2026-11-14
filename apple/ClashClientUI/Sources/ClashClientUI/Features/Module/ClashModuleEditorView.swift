#if !os(tvOS)
import ClashClientKit
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
public struct ClashModuleEditorView: View {
    private let editor: ClashModuleEditorSnapshot
    private let perform: (ClashModulesAction) -> Void
     
     
     
    @State private var typed: String?
    @State private var confirmsDiscard = false
    @Environment(\.locale) private var locale

    public init(editor: ClashModuleEditorSnapshot, perform: @escaping (ClashModulesAction) -> Void) {
        self.editor = editor
        self.perform = perform
    }

    private var opening: String { editor.text ?? ClashModuleEditorSnapshot.template(locale: locale) }
    private var text: String { typed ?? opening }
    private var isEdited: Bool { typed.map { $0 != opening } ?? false }
    private var canSave: Bool { !editor.isSaving && ClashModuleEditorSnapshot.canSave(text) }
    private var titleKey: String { editor.moduleID == nil ? "New Module" : "Edit Module" }

     
     
    static let chrome: CGFloat = 150
     
    static let minimumTextHeight: CGFloat = 240

    static func textHeight(in available: CGFloat) -> CGFloat {
        max(minimumTextHeight, available - chrome)
    }

     
    @Environment(\.clashInsideProductModalPresentation) private var insideProductModal

    public var body: some View {
        ClashSingleColumnNavigationContainer {
            GeometryReader { proxy in
                Form {
                    Section {
                        ClashModuleText(text: Binding(get: { text }, set: { typed = $0 }), isEditable: !editor.isSaving)
                            .frame(height: Self.textHeight(in: proxy.size.height))
                            .accessibilityLabel(Text("Module Content"))
                            .accessibilityIdentifier("modules.editor.text")
                    } footer: {
                         
                         
                        if let refusal = editor.refusal {
                            Text(clash: refusal)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("modules.editor.refusal")
                        } else {
                            Text("Write the module's name after #!name= on the first line.")
                        }
                    }
                }
                .modifier(ClashModulesFormStyle())
            }
            .clashPageTitle(.copy(titleKey))
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) {
                    ClashSheetCloseButton {
                        close()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editor.isSaving {
                        ProgressView()
                    } else {
                        Button {
                            save()
                        } label: {
                            Text("Save")
                        }
                        .disabled(!canSave)
                        .accessibilityIdentifier("modules.editor.save")
                    }
                }
            }
            .clashMacProductModalBar {
                if insideProductModal {
                    ClashModalActionBar(primaryTitle: "Save", primaryDisabled: !canSave, isBusy: editor.isSaving,
                                        busyTitle: "Saving…", onPrimary: save)
                }
            }
            .clashProductModalRoot(title: .copy(titleKey), actionTitle: "Save", actionDisabled: !canSave, action: save)
            .confirmationDialog(Text("Discard Changes?"), isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button(role: .destructive) {
                    perform(.closeEditor)
                } label: {
                    Text("Discard Changes")
                }
                .accessibilityIdentifier("modules.editor.discard")
                Button(role: .cancel) {} label: {
                    Text("Keep Editing")
                }
            }
        }
         
        .interactiveDismissDisabled(isEdited || editor.isSaving)
        .accessibilityIdentifier("modules.editor")
    }

    private func close() {
        if isEdited {
            confirmsDiscard = true
        } else {
            perform(.closeEditor)
        }
    }

    private func save() {
        guard canSave else { return }
        perform(.saveModule(id: editor.moduleID, text: text))
    }
}

 
 
 
 
 
 
 
public struct ClashModuleText: View {
     
    public struct Request {
        public let text: Binding<String>
        public let isEditable: Bool
    }

     
    nonisolated(unsafe) public static var platformView: (@MainActor (Request) -> AnyView)?

    @Binding private var text: String
    private let isEditable: Bool

    public init(text: Binding<String>, isEditable: Bool) {
        _text = text
        self.isEditable = isEditable
    }

    public var body: some View {
        if let make = Self.platformView {
            make(Request(text: $text, isEditable: isEditable))
        } else {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .disabled(!isEditable)
        }
    }
}
#endif
