import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashValueField: View {
    private let hint: String
    private let label: String?
    private let bordered: Bool
    private let text: Binding<String>
     
     
     
     
     
     
     
    private let identifier: String?

     
     
     
     
     
     
     
     
     
     
     
    public init(
        hint: String,
        label: String? = nil,
        bordered: Bool = false,
        text: Binding<String>,
        identifier: String? = nil
    ) {
        self.hint = hint
        self.label = label
        self.bordered = bordered
        self.text = text
        self.identifier = identifier
    }

    public var body: some View {
        field.clashFieldIdentifier(identifier)
    }

    @ViewBuilder
    private var field: some View {
#if os(macOS)
        if bordered {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            TextField(
                text: text,
                prompt: Text(ClashCopy.key(hint)),
                label: { EmptyView() }
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .clashValueFieldName(label)
        } else {
            TextField("", text: text, prompt: Text(ClashCopy.key(hint)))
                 
                 
                 
                 
                 
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .clashValueFieldName(label)
        }
#else
         
         
         
        TextField(ClashCopy.key(hint), text: text)
            .multilineTextAlignment(.trailing)
#endif
    }
}

private extension View {
    @ViewBuilder
    func clashValueFieldName(_ label: String?) -> some View {
        if let label {
            accessibilityLabel(Text(ClashCopy.key(label)))
        } else {
            self
        }
    }
}
