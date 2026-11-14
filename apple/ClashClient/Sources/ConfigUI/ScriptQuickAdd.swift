import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
enum ScriptQuickAdd {
     
     
     
     
     
     
     
     
    @discardableResult
    static func add(
        _ input: ProfileQuickAddInput,
        library: UserDefaults = ScriptLibrary.appGroupDefaults
    ) async throws -> ConfigScript {
        switch input {
        case .link(let address, _):
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = try await ScriptImport.body(at: trimmed)
            if var existing = ScriptLibrary.load(from: library).first(where: {
                ($0.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
            }) {
                existing.body = body
                ScriptLibrary.upsert(existing, in: library)
                return existing
            }
            let label = (try? ScriptImport.address(trimmed))
                .flatMap(ScriptImport.suggestedName(for:))
                ?? ScriptLibrary.defaultLabel
            return try ScriptAddOutcome.save(
                label: label, body: body, sourceURL: trimmed, in: library
            )

        case let .document(fileName, data, _):
            guard let text = String(data: data, encoding: .utf8) else {
                throw ScriptImportError.notText
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScriptImportError.empty
            }
             
             
             
            let name = fileName == ProfileQuickAddInput.pastedDocumentName
                ? ScriptLibrary.defaultLabel
                : (fileName as NSString).deletingPathExtension
            return try ScriptAddOutcome.save(label: name, body: text, in: library)

        case .nodeShareLink, .nodes, .nothing:
            throw ScriptImportError.notAnAddress
        }
    }
}
