import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 

enum AdBlockModuleCopy {
     
     
     
     
    static func size(_ bytes: Int) -> String {
        Foundation.ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

extension AdBlockIgnoredReason {
     
     
     
     
     
     
     
    var authoredText: AuthoredText {
        switch self {
        case .sectionNotSupported, .settingNotSupported, .mapLocalNotSupported, .unsupportedRewriteType,
             .unsupportedRuleType, .ruleListNotSupported, .boxJSNotSupported, .newerSyntaxNotSupported:
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
        case .headerOverLimit, .argumentsOverLimit:
            return .app("This module has too much in it, so the extra was skipped.")
        case .scriptDownloadFailed(let why):
             
             
             
             
             
            switch why {
            case .app(let key, _) where AdBlockStoredSentence.isServerAnswer(key): return AdBlockStoredSentence.scriptNotDownloaded
            case .app: return AdBlockStoredSentence.current(why)
            case .verbatim: return AdBlockStoredSentence.scriptNotDownloaded
            }
        case .fileDownloadFailed(let why):
            switch why {
             
            case .app(let key, _) where AdBlockStoredSentence.isServerAnswer(key): return AdBlockStoredSentence.fileNotDownloaded
            case .app: return AdBlockStoredSentence.current(why)
             
             
            case .verbatim: return AdBlockStoredSentence.fileNotDownloaded
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
            case .vpnIcon:
                return .app("The system decides when the VPN icon shows, so this line was skipped.")
            case .systemProxy, .pingForwarding, .snellVersion, .networkSwitching, .noSuchSetting, .cellularServices:
                 
                 
                 
                return AdBlockModuleCopy.deviceCannot
            }
        case .waitingForKernel:
             
             
            return .app("This line can't take effect yet, so it was skipped.")
        case .setInClashSettings:
             
             
             
            return .app("Clash's own setting is used for this, so it was skipped.")
        case .noEffectInItsOwnApp(let why):
            switch why {
            case .app: return AdBlockStoredSentence.current(why)
            case .verbatim(let text):
                return .app("This line doesn't work in the app it was written for either (%@), so it was skipped.", arguments: [text])
            }
         
         
        case .answerFileTooLarge:
            return .app("The file this line returns is too large, so it was skipped.")
        case .lineTooLong:
            return .app("This line is too long, so it was skipped.")
        case .policyNotFound(let policy):
            return .app("This rule's destination %@ isn't in the current configuration, so it was skipped.",
                        arguments: [policy])
        case .notApplicable(let why):
            switch why {
            case .app: return AdBlockStoredSentence.current(why)
             
             
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

 
 
 
 
 
 
 
 
 
enum AdBlockStoredSentence {
     
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
         
        case sectionLayout, noRulesSection: return AdBlockDegradeReason.refusedWithAdBlocking.authoredText
         
         
         
        case let key where serverAnswers.contains(key): return AdBlockModuleStoreError.serverNotVerified.authoredText
        default: return text
        }
    }

     
     
     
     
     
     
    static func failure(_ text: AuthoredText, linked: Bool) -> AuthoredText {
        guard case .app(let key, _) = text else { return text }
        if linked, isServerAnswer(key) { return linkDidNotOpenLastCopyInUse }
        if let refusal = addTimeRefusals[key] {
            return current(AdBlockModuleStore.updateFailureText(for: refusal, linked: linked))
        }
        return current(text)
    }

     
     
    private static let addTimeRefusals: [String: AdBlockModuleRefusal] = {
        let all: [AdBlockModuleRefusal] = [.quantumultX(""), .notAModule, .otherPlatform([]), .notText, .tooLarge(0),
                                           .unreadableYAML(""), .notAnAddress, .requirementNotMet]
        var keys: [String: AdBlockModuleRefusal] = [:]
        for refusal in all {
            switch refusal {
            case .quantumultX, .notAModule, .otherPlatform, .notText, .tooLarge, .unreadableYAML, .notAnAddress,
                 .requirementNotMet:
                guard case .app(let key, _) = refusal.authoredText,
                      AdBlockModuleStore.updateFailureText(for: refusal, linked: true) != refusal.authoredText else { continue }
                keys[key] = refusal
            }
        }
        return keys
    }()

     
     
    private static let serverAnswers: Set<String> = Set([DownloadError.badStatus(404), .badStatus(-1)].compactMap { error in
        if case .app(let key, _) = error.authoredText { return key }
        return nil
    })

     
     
    static func isServerAnswer(_ key: String) -> Bool {
        if serverAnswers.contains(key) { return true }
        guard case .app(let verified, _) = AdBlockModuleStoreError.serverNotVerified.authoredText else { return false }
        return key == verified
    }

    static func current(_ sentence: AdBlockSentence) -> AuthoredText {
        switch sentence {
        case .app(let key, let arguments): return current(AuthoredText.app(key, arguments: arguments))
        case .verbatim(let words): return .verbatim(words)
        }
    }
}

 
 
extension AdBlockSentence {
     
     
    static let noEffect = AdBlockSentence.app("This line has no effect, so it was skipped.", arguments: [])
     
    static let modulesCannotAddProxies = AdBlockSentence.app("A module can't add proxies or proxy groups, so this line was skipped.",
                                                             arguments: [])
     
    static let writtenForAnotherApp = AdBlockSentence.app("This line is written for another app, so it was skipped.", arguments: [])
     
     
    static let catchAllBelongsToTheConfiguration = AdBlockSentence.app("The catch-all rule comes from your configuration, so this line was skipped.",
                                                                       arguments: [])
     
     
    static let noCaptureSession = AdBlockSentence.app("The capture option has no effect here, so it was skipped.", arguments: [])
     
     
     
    static let noEffectThereEither = AdBlockSentence.app("This line doesn't work in the app it was written for either, so it was skipped.",
                                                         arguments: [])
     
    static let modulesCannotChangeCertificate = AdBlockSentence.app("A module can't change the certificate, so this line was skipped.",
                                                                    arguments: [])
     
    static let clashCannotDoThis = AdBlockSentence.app("Clash can't do what this line asks, so it was skipped.", arguments: [])
     
    static let doesNotApply = AdBlockSentence.app("This line doesn't fit the current configuration, so it was skipped.", arguments: [])
     
     
    static let partCannotBeUsed = AdBlockSentence.app("This part of the module can't be used, so it was skipped.", arguments: [])
     
     
     
     
    static let alsoAppliesToDirectSites = AdBlockSentence.app("This also applies to sites you reach directly.", arguments: [])
}

 
 
 
 
extension AdBlockModuleChange.Key {
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

extension AdBlockModuleCopy {
     
    static let deviceSettingsFootnote = AuthoredText.app("These settings return to yours when this module is off.")
     
    static let deviceCannot = AuthoredText.app("This device can't do this, so it was skipped.")
     
    static let lanSharingOn = AdBlockSentence.app("This module turned on LAN sharing.", arguments: [])
}

 
 
extension AdBlockSentence {
     
     
    static let redirectAddressCannotUseDollarNumbers =
        AdBlockSentence.app("A redirect address can't use $1, so this line has no effect and was skipped.", arguments: [])
}

 
 
 
 
 
extension AdBlockSentence {
    static let anotherAppsFormatWorksHere =
        AdBlockSentence.app("This line is in another app's format, and it works here as written.", arguments: [])
}

 
 
 
extension AdBlockSentence {
    static let optionsWithNoEffect =
        AdBlockSentence.app("Some options in this line have no effect, so they were skipped.", arguments: [])
}

extension AdBlockModuleRefusal {
    var authoredText: AuthoredText {
        switch self {
         
         
         
        case .quantumultX(let section):
            return .app(section.isEmpty ? "This kind of module isn't supported."
                            : "This kind of module has a section this build cannot use (\(section)).")
        case .notAModule, .notText: return .app("This isn't a module, so it wasn't added.")
        case .otherPlatform: return .app("This module is for another kind of device, so it wasn't added.")
        case .tooLarge: return .app("This module is too large, so it wasn't added.")
        case .unreadableYAML(let message):
            return .app("This module could not be read: %@",
                        arguments: [AdBlockModuleParser.prefix(message, bytes: AdBlockModuleParser.maximumShownBytes)])
        case .notAnAddress: return .app("No link found. Paste a module link or the module itself.")
        case .requirementNotMet: return .app("This module needs features Clash doesn't have yet.")
        }
    }
}

 
 
 
extension AdBlockModuleRefusal: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}
extension AdBlockModuleStoreError: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}
extension AdBlockInjectionError: ClashAuthoredError {
    var displayText: ClashDisplayText { AdBlockStoredSentence.current(authoredText).displayText }
}
