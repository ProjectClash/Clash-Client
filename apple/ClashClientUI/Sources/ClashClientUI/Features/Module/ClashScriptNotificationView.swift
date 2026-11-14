import SwiftUI

 
 
 
 
 
 
 
public struct ClashScriptNotificationText: Equatable, Identifiable, Sendable {
     
     
    public var id: String
    public var scriptName: String
    public var title: String
    public var subtitle: String
    public var body: String
     
     
     
    public var copied: String?

    public init(id: String, scriptName: String, title: String, subtitle: String, body: String,
                clipboardText: String? = nil) {
        self.id = id
        self.scriptName = scriptName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        copied = clipboardText.flatMap { $0.isEmpty || $0 == body ? nil : $0 }
    }

     
     
    public var copyText: String {
        if let copied { return copied }
        if !Self.isBlank(body) { return body }
        return [title, subtitle].filter { !Self.isBlank($0) }.joined(separator: "\n")
    }

     
     
    public var pageTitle: String {
        Self.isBlank(scriptName) ? title : scriptName
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

 
 
 
public struct ClashScriptNotificationView: View {
    public let text: ClashScriptNotificationText

    public init(text: ClashScriptNotificationText) {
        self.text = text
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                if !text.title.isEmpty {
                    Text(verbatim: text.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("notification.script.title")
                }
                if !text.subtitle.isEmpty {
                    Text(verbatim: text.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("notification.script.subtitle")
                }
                if !text.body.isEmpty {
                    Text(verbatim: text.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("notification.script.body")
                }
                if let copied = text.copied {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                        Text("Copied")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(verbatim: copied)
                            .font(.system(.body, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("notification.script.copied")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ClashTheme.Spacing.standard)
        }
        .accessibilityIdentifier("notification.script")
    }
}
