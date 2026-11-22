import Foundation

 
 
 
 
 
 
 
 
 
 
public enum ClashProxyGroupKindName {
     
    public static func fileSpelling(of type: String) -> String? {
        spellings[type.lowercased().filter { $0 != "-" && $0 != "_" && $0 != " " }]
    }

     
    public static func name(for type: String, locale: Locale) -> String? {
        guard let file = fileSpelling(of: type) else { return nil }
        return names[ConfigurationFieldCopy.Language(locale: locale)]?[file]
    }

     
    public static func text(for type: String, locale: Locale, otherwise: String) -> ClashDisplayText {
        .verbatim(name(for: type, locale: locale) ?? otherwise)
    }

     
    private static let spellings: [String: String] = [
        "select": "select", "selector": "select",
        "urltest": "url-test",
        "fallback": "fallback",
        "loadbalance": "load-balance",
    ]

     
     
    private static let names: [ConfigurationFieldCopy.Language: [String: String]] = Dictionary(
        uniqueKeysWithValues: ConfigurationFieldCopy.Language.allCases.map {
            ($0, ConfigurationTypeWords.names(.proxyGroups, copy: .shared, locale: Locale(identifier: $0.rawValue)))
        })
}
