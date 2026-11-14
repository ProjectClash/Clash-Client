import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 

enum ModuleCopy {
     
     
     
     
    static func size(_ bytes: Int) -> String {
        Foundation.ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

extension ModuleIgnoredReason {
     
     
     
     
     
     
     
    var authoredText: AuthoredText {
        switch self {
        case .sectionNotSupported, .settingNotSupported, .mapLocalNotSupported, .unsupportedRewriteType,
             .unsupportedRuleType, .ruleListNotSupported, .newerSyntaxNotSupported:
            return Self.notSupported
        case .unreadableLine, .invalidPattern, .invalidHost, .jqExpressionInvalid:
            return Self.writtenWrong
        case .argumentsNotSupported:
            return .app("Changing module settings is not supported yet, so the defaults are used.")
        case .customPolicy(let policy):
            return .app("This rule's destination %@ isn't in Clash, so it was skipped.", arguments: [policy])
        case .readersOwnPolicy:
            return .app("A module can't choose the proxy, so this rule was skipped.")
        case .catchAllRule:
            return .app("This rule would apply to all traffic, so it was skipped.")
        case .urlRuleNeedsReject:
            return .app("Rules that match a web address can only block, so this one was skipped.")
        case .ruleRefused(let message):
            return .app("This rule could not be used: %@", arguments: [message])
        case .unsupportedScriptType(let type) where type.isEmpty || type == "?":
             
             
            return Self.scriptUnusable
        case .unsupportedScriptType:
            return Self.notSupported
        case .scriptWithoutAddress, .scriptAddressNotSecure:
            return Self.scriptUnusable
        case .missingArgument(let name):
            return .app("The %@ setting is missing, so this line was skipped.", arguments: [name])
        case .scriptTurnedOff:
            return .app("This script is turned off in the module.")
        case .argumentsOverLimit:
            return .app("This module has too much in it, so the extra was skipped.")
        case .scriptDownloadFailed(let why):
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            switch why {
            case .app(let key, let arguments)
                where key == ModuleStoredSentence.scriptStatus || ModuleStoredSentence.isServerAnswer(key):
                return ModuleStoredSentence.scriptDownloadFailure(key: key, arguments: arguments)
            case .app: return ModuleStoredSentence.current(why)
            case .verbatim: return ModuleStoredSentence.scriptNotReached
            }
        case .fileDownloadFailed(let why):
            switch why {
             
            case .app(let key, _) where ModuleStoredSentence.isServerAnswer(key): return ModuleStoredSentence.fileNotDownloaded
            case .app: return ModuleStoredSentence.current(why)
             
             
            case .verbatim: return ModuleStoredSentence.fileNotDownloaded
            }
        case .platformCannot(let limit):
            switch limit {
            case .processRules:
                return .app("This device can't tell which app a connection comes from, so this rule was skipped.")
            case .lanDeviceRules:
                return .app("This device can't see the other devices on your network, so this rule was skipped.")
            case .carrierCode:
                return .app("This device doesn't report its carrier, so this rule was skipped.")
            case .remoteRelativeFile:
                return .app("The file this line needs isn't on this device, so it was skipped.")
             
             
            case .systemProxy:
                return .app("Clash doesn't use a system proxy, so this compatibility mode was skipped.")
            case .pingForwarding:
                return .app("Clash always answers pings itself, so this line was skipped.")
            case .snellVersion:
                return .app("Snell version 6 isn't supported, so this line was skipped.")
            case .networkSwitching:
                return .app("The system decides when Wi-Fi and cellular are used together, so this line was skipped.")
            case .noSuchSetting:
                return .app("Clash has no such setting, so this line was skipped.")
            case .cellularServices:
                return .app("A Mac has no cellular services, so this line was skipped.")
            case .dnsScripts:
                return .app("Clash doesn't run DNS scripts, so this line was skipped.")
            case .ruleScripts:
                return .app("Clash doesn't run rule scripts, so this line was skipped.")
            }
        case .waitingForKernel:
             
             
            return .app("This line can't take effect yet, so it was skipped.")
        case .setInClashSettings:
             
             
             
            return .app("Clash's own setting is used for this, so it was skipped.")
        case .noEffectInItsOwnApp(let why):
            switch why {
            case .app: return ModuleStoredSentence.current(why)
            case .verbatim(let text):
                return .app("This line doesn't work in the app it was written for either (%@), so it was skipped.", arguments: [text])
            }
        case .policyNotFound(let policy):
            return .app("This rule's destination %@ isn't in the current configuration, so it was skipped.",
                        arguments: [policy])
        case .notApplicable(let why):
            switch why {
            case .app: return ModuleStoredSentence.current(why)
             
             
            case .verbatim: return .app("This line doesn't fit the current configuration, so it was skipped.")
            }
        case .settingsRefused(let message):
             
            return .app("This module's settings couldn't be used: %@", arguments: [message])
        case .ruleSetTooLarge:
            return .app("This rule set is too large, so it was skipped.")
        case .tooManyRuleSets:
            return .app("Too many rule sets are on, so some didn't take effect.")
        case .ruleSetNotDownloadedYet:
            return .app("This rule set hasn't been downloaded yet; it will be added at the next update.")
        }
    }

     
     
     
    static let notSupported: AuthoredText = .app("This isn't supported, so it was skipped.")
     
     
    static let writtenWrong: AuthoredText = .app("This line isn't written correctly, so it was skipped.")
     
     
    static let scriptUnusable: AuthoredText = .app("This script can't be used, so it was skipped.")
}

 
 
 
 
 
 
 
 
 
enum ModuleStoredSentence {
     
    static let scriptStatus = #"This script could not be downloaded: the server returned HTTP %@."#
    static let scriptTooLarge = #"This script is larger than %@, so it cannot be downloaded."#
    static let sectionLayout = #"The %@ section of this configuration is written in an unusual way, so modules cannot take effect."#
     
     
     
    static let noRulesSection = #"This configuration has no rules section, so modules cannot take effect."#

     
    static let scriptNotDownloaded: AuthoredText = .app("This script couldn't be downloaded.")
     
    static let fileNotDownloaded: AuthoredText = .app("The file this line uses couldn't be downloaded, so it was skipped.")
     
     
     
     
    static let linkDidNotOpenLastCopyInUse: AuthoredText = .app("The link didn't open; the last copy is still in use.")

    static func current(_ text: AuthoredText) -> AuthoredText {
        guard case .app(let key, _) = text else { return text }
        switch key {
        case scriptStatus: return scriptNotDownloaded
         
        case scriptTooLarge: return .app("This script is too large, so it wasn't downloaded.")
         
        case sectionLayout, noRulesSection: return ModuleDegradeReason.refusedWithModules.authoredText
         
         
         
        case let key where serverAnswers.contains(key): return ModuleStoreError.serverNotVerified.authoredText
        default: return text
        }
    }

     
     
     
     
     
     
    static func failure(_ text: AuthoredText, linked: Bool) -> AuthoredText {
        guard case .app(let key, _) = text else { return text }
        if linked, isServerAnswer(key) { return linkDidNotOpenLastCopyInUse }
        if let refusal = addTimeRefusals[key] {
            return current(ModuleStore.updateFailureText(for: refusal, linked: linked))
        }
        return current(text)
    }

     
     
    private static let addTimeRefusals: [String: ModuleRefusal] = {
        let all: [ModuleRefusal] = [.quantumultX, .notAModule, .otherPlatform([]), .notText, .tooLarge(0),
                                           .unreadableYAML(""), .notAnAddress, .requirementNotMet]
        var keys: [String: ModuleRefusal] = [:]
        for refusal in all {
            switch refusal {
            case .quantumultX, .notAModule, .otherPlatform, .notText, .tooLarge, .unreadableYAML, .notAnAddress,
                 .requirementNotMet:
                guard case .app(let key, _) = refusal.authoredText,
                      ModuleStore.updateFailureText(for: refusal, linked: true) != refusal.authoredText else { continue }
                keys[key] = refusal
            }
        }
        return keys
    }()

     
     
    private static let serverAnswers: Set<String> = Set([DownloadError.badStatus(404), .badStatus(-1)].compactMap { error in
        if case .app(let key, _) = error.authoredText { return key }
        return nil
    })

     
     
    static func serverStatus(key: String, arguments: [String]) -> Int? {
        guard case .app(let badStatus, _) = DownloadError.badStatus(404).authoredText,
              key == badStatus || key == scriptStatus else { return nil }
        guard let first = arguments.first, let status = Int(first), status > 0 else { return nil }
        return status
    }

     
     
     
     
     
     
     
     
     
     
     
    static func scriptDownloadFailure(key: String, arguments: [String]) -> AuthoredText {
        guard let status = serverStatus(key: key, arguments: arguments) else {
             
             
            return scriptNotReached
        }
         
         
         
         
         
         
        return .app("This script couldn't be downloaded: the server returned HTTP %@.", arguments: [String(status)])
    }

     
     
     
     
     
    static var everyScriptDownloadFailure: [AuthoredText] {
        [scriptDownloadFailure(key: badStatusKey, arguments: ["404"]),
         scriptNotReached]
    }

     
    static var badStatusKey: String {
        guard case .app(let key, _) = DownloadError.badStatus(404).authoredText else { return "" }
        return key
    }

     
     
    static let scriptNotReached: AuthoredText = .app("This script couldn't be downloaded: the server couldn't be reached.")

     
     
    static func isServerAnswer(_ key: String) -> Bool {
        if serverAnswers.contains(key) { return true }
        guard case .app(let verified, _) = ModuleStoreError.serverNotVerified.authoredText else { return false }
        return key == verified
    }

    static func current(_ sentence: ModuleSentence) -> AuthoredText {
        switch sentence {
        case .app(let key, let arguments): return current(AuthoredText.app(key, arguments: arguments))
        case .verbatim(let words): return .verbatim(words)
        }
    }
}

 
 
extension ModuleSentence {
     
     
    static let noEffect = ModuleSentence.app("This line has no effect, so it was skipped.", arguments: [])
     
    static let modulesCannotAddProxies = ModuleSentence.app("A module can't add proxies or proxy groups, so this line was skipped.",
                                                             arguments: [])
     
    static let writtenForAnotherApp = ModuleSentence.app("This line is written for another app, so it was skipped.", arguments: [])
     
     
    static let catchAllBelongsToTheConfiguration = ModuleSentence.app("The catch-all rule comes from your configuration, so this line was skipped.",
                                                                       arguments: [])
     
     
    static let noCaptureSession = ModuleSentence.app("The capture option has no effect here, so it was skipped.", arguments: [])
     
     
     
    static let noEffectThereEither = ModuleSentence.app("This line doesn't work in the app it was written for either, so it was skipped.",
                                                         arguments: [])
     
    static let modulesCannotChangeCertificate = ModuleSentence.app("A module can't change the certificate, so this line was skipped.",
                                                                    arguments: [])
     
    static let clashCannotDoThis = ModuleSentence.app("Clash can't do what this line asks, so it was skipped.", arguments: [])
     
    static let doesNotApply = ModuleSentence.app("This line doesn't fit the current configuration, so it was skipped.", arguments: [])
     
     
    static let partCannotBeUsed = ModuleSentence.app("This part of the module can't be used, so it was skipped.", arguments: [])
     
     
     
     
    static let alsoAppliesToDirectSites = ModuleSentence.app("This also applies to sites you reach directly.", arguments: [])
}

 
 
 
 
extension ModuleChange.Key {
    var label: AuthoredText {
        switch self {
        case .logLevel: return .app("Log level")
        case .mode: return .app("Outbound Mode")
        case .lanSharing: return .app("LAN Proxy Share")
        case .httpPort: return .app("HTTP Port")
        case .socksPort: return .app("SOCKS Port")
        case .mixedPort: return .app("Proxy Port")
        case .bindAddress: return .app("Sharing Address")
        case .controller: return .app("External Controller")
        case .secret: return .app("Secret")
        case .listener: return .app("Proxy Service")
        case .hideVPNIcon: return .app("Hide VPN Icon")
        case .includeAllNetworks: return .app("Include All Networks")
        case .includeLocalNetworks: return .app("Include Local Networks")
        case .includeAPNs: return .app("Include APNs")
        case .includeCellularServices: return .app("Include Cellular Services")
        case .homeKitCompatibility: return .app("HomeKit Compatibility")
        case .testURL: return .app("Delay test URL")
        }
    }
}

extension ModuleCopy {
     
    static let deviceSettingsFootnote = AuthoredText.app("These settings return to yours when this module is off.")
     
    static let lanSharingOn = ModuleSentence.app("This module turned on LAN sharing.", arguments: [])
}

 
 
extension ModuleSentence {
     
     
    static let redirectAddressCannotUseDollarNumbers =
        ModuleSentence.app("A redirect address can't use $1, so this line has no effect and was skipped.", arguments: [])
}

 
 
 
 
 
extension ModuleSentence {
    static let anotherAppsFormatWorksHere =
        ModuleSentence.app("This line is in another app's format, and it works here as written.", arguments: [])
}

 
 
 
extension ModuleSentence {
    static let optionsWithNoEffect =
        ModuleSentence.app("Some options in this line have no effect, so they were skipped.", arguments: [])
}

extension ModuleRefusal {
    var authoredText: AuthoredText {
        switch self {
         
         
         
        case .quantumultX: return .app("This kind of module isn't supported.")
        case .notAModule, .notText: return .app("This isn't a module, so it wasn't added.")
        case .otherPlatform: return .app("This module is for another kind of device, so it wasn't added.")
        case .tooLarge: return .app("This module is too large, so it wasn't added.")
        case .unreadableYAML(let message):
            return .app("This module could not be read: %@",
                        arguments: [ModuleParser.prefix(message, bytes: ModuleParser.maximumShownBytes)])
        case .notAnAddress: return .app("No link found. Paste a module link or the module itself.")
        case .requirementNotMet: return .app("This module needs features Clash doesn't have yet.")
        }
    }
}

 
 
 
extension ModuleRefusal: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}
extension ModuleStoreError: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}
extension ModuleInjectionError: ClashAuthoredError {
    var displayText: ClashDisplayText { ModuleStoredSentence.current(authoredText).displayText }
}
