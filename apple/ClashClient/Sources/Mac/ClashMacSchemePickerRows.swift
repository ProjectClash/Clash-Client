import ClashClientKit
import ClashMacClient
import Foundation

 
 
 
extension ClashMacSchemePickerRows {
    init(_ snapshot: ConfigurationSchemePickerSnapshot) {
        func rows(_ rows: [ConfigurationSchemePickerSnapshot.Row]) -> [Row] {
            rows.map { Row(id: $0.id, detailID: $0.detailID, name: $0.name, detail: $0.detail, isCurrent: $0.isCurrent) }
        }
        self.init(builtin: rows(snapshot.builtin), mine: rows(snapshot.mine), linked: rows(snapshot.linked),
                  files: rows(snapshot.files),
                  original: snapshot.original.map { Original(isAvailable: $0.isAvailable, isCurrent: $0.isCurrent, reason: $0.reason) })
    }

     
    static func of(_ library: ConfigurationLibrarySnapshot, profileID: String, configurationName: String,
                   locale: Locale) -> Self {
        Self(ConfigurationSchemePickerSnapshot.make(library: library, profileID: profileID,
                                                    configurationName: configurationName, locale: locale))
    }

     
     
     
     
     
    static func schemeToUse(before: ConfigurationLibrarySnapshot, after: ConfigurationLibrarySnapshot,
                            input: ProfileQuickAddInput, profileID: String) -> String? {
        guard let id = ConfigurationSchemePickerSnapshot.added(before: before, after: after, input: input, profileID: profileID)
        else { return nil }
        let current = ConfigurationSchemePickerSnapshot.make(library: after, profileID: profileID, configurationName: "",
                                                             locale: Locale(identifier: "en")).current
        return current == .scheme(id) ? nil : id
    }
}
