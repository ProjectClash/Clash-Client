import SwiftUI

 
 
 
 
 
 
 
 
 
public struct ClashModuleScriptSourceView: View {
     
    public struct Update: Equatable {
        public var isUpdating: Bool
        public var action: ClashModulesAction

        public init(isUpdating: Bool, action: ClashModulesAction) {
            self.isUpdating = isUpdating
            self.action = action
        }
    }

    let source: ClashModuleScriptSource
    let update: Update?
    let perform: (ClashModulesAction) -> Void
    @State private var read: Read = .reading

    public enum Read: Equatable, Sendable {
        case reading
        case text(ScriptText)
         
        case notDownloaded
    }

     
    public struct ScriptText: Equatable, Sendable {
         
        public var original: String
         
         
        public var rows: [Row]
        public var lineCount: Int

        public struct Row: Equatable, Sendable {
             
            public var line: Int?
            public var text: String
        }
    }

     
     
    public nonisolated static let rowCharacters = 1_000

    public init(source: ClashModuleScriptSource, update: Update? = nil, perform: @escaping (ClashModulesAction) -> Void) {
        self.source = source
        self.update = update
        self.perform = perform
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
                Text(verbatim: source.link)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("modules.script.link")
                switch read {
                case .reading:
                    ProgressView()
                case .notDownloaded:
                    Text(clash: "This script hasn’t been downloaded yet.")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("modules.script.notDownloaded")
                    if let update {
                        Button {
                            perform(update.action)
                        } label: {
                            Text(clash: update.isUpdating ? "Updating…" : "Update")
                        }
                        .disabled(update.isUpdating)
                        .accessibilityIdentifier("modules.script.update")
                    }
                case .text(let text):
                    numbered(text)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clashPageTitle(.verbatim(source.name), watchAs: "modules.script")
         
         
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .primaryAction) {
                if case .text(let text) = read {
                    copyButton(text)
                }
            }
        }
        .accessibilityIdentifier("modules.script")
        .task(id: source) { read = await Self.read(source.file) }
    }

    private func copyButton(_ text: ScriptText) -> some View {
        Button {
            perform(.copy(text.original))
        } label: {
            Text("Copy")
        }
        .accessibilityIdentifier("modules.script.copy")
    }

    private func numbered(_ text: ScriptText) -> some View {
        let width = String(text.lineCount).count
        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                    Text(verbatim: row.line.map { Self.number($0, width: width) }
                                 ?? String(repeating: "\u{2007}", count: width))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(verbatim: row.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.system(.footnote, design: .monospaced))
            }
        }
    }

     
    public nonisolated static func number(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "\u{2007}", count: max(0, width - digits.count)) + digits
    }

     
     
    public nonisolated static func lines(_ text: String) -> [String] {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = unified.components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

     
     
     
     
     
     
     
    public nonisolated static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        var converted: NSString?
        var lossy: ObjCBool = false
        let found = NSString.stringEncoding(for: data, encodingOptions: [
            .suggestedEncodingsKey: [gb18030, String.Encoding.windowsCP1252.rawValue, String.Encoding.shiftJIS.rawValue],
            .allowLossyKey: false,
        ], convertedString: &converted, usedLossyConversion: &lossy)
        if found != 0, let converted { return converted as String }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

     
    public nonisolated static func text(_ original: String) -> ScriptText {
        let lines = lines(original)
        var rows: [ScriptText.Row] = []
        for (index, line) in lines.enumerated() {
            var start = line.startIndex
            repeat {
                let end = line.index(start, offsetBy: rowCharacters, limitedBy: line.endIndex) ?? line.endIndex
                rows.append(.init(line: start == line.startIndex ? index + 1 : nil, text: String(line[start..<end])))
                start = end
            } while start < line.endIndex
        }
        return ScriptText(original: original, rows: rows, lineCount: lines.count)
    }

    public nonisolated static func read(_ file: URL?) async -> Read {
        guard let file else { return .notDownloaded }
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: file) else { return Read.notDownloaded }
            return .text(text(decode(data)))
        }.value
    }
}
