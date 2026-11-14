import Foundation

 
 
 
 
 
enum ClashTVOverrideScript {
    static let notText = "The script is not text."
    static let noScript = "This profile has no override script to update."

     
     
    struct TooLarge: LocalizedError, Equatable {
        var errorDescription: String? {
            String(localized: "This configuration is too large to run an override script.")
        }
    }

    static func apply(script: String, toYAML yaml: String, profileName: String) throws -> String {
        let json = try ConfigTransforms.yamlToJSON(yaml)
        let scripted = try ScriptEngine.run(script: script, configJSON: json, profileName: profileName, caller: .surfaced,
                                            name: ScriptEngine.LogName.tvOverride)
        return try ConfigTransforms.jsonToYAML(scripted)
    }
}
