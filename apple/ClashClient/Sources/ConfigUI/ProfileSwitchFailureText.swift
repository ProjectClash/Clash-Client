import Foundation
import ClashClientUI

 
 
 
 
 
 
 
 
 
enum ProfileSwitchFailureText {
     
     
     
     
    static func cardText(
        for failure: ConfigurationFailure,
        locale: Locale = .current
    ) -> String {
        hinted(composed(for: failure, locale: locale), failure, locale)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private static func hinted(
        _ text: String,
        _ failure: ConfigurationFailure,
        _ locale: Locale
    ) -> String {
        let lines = ClashKernelRefusalHint.lines(for: failure.kernelSentence, locale: locale)
        guard !lines.isEmpty else { return text }
        return ([text] + lines).joined(separator: "\n")
    }

    private static func composed(
        for failure: ConfigurationFailure,
        locale: Locale
    ) -> String {
        let failures = failure.providerFailures
        guard !failures.isEmpty else {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            let reason = ConfigurationRefusalReason.reading(failure.kernelSentence)
            if reason.isRecognized { return reason.alertMessage(locale: locale) }
            return failure.displayMessage.resolved(locale: locale)
        }
        var lines = failures.map { cardLine($0, locale: locale) }
        if failure.kind == .kernelRejected {
             
             
            return lines.map { "\($0)\n\(failure.message)" }
                .joined(separator: "\n")
        }
         
         
         
        if failures.contains(where: { !$0.kind.isServersRefusal }) {
            lines.append(ClashCopy.string(
                "Check the network and the source addresses, then try again.",
                locale: locale
            ))
        }
        return lines.joined(separator: "\n")
    }

     
     
     
     
    private static func cardLine(
        _ line: ProviderFailureLine,
        locale: Locale
    ) -> String {
        guard case .refusedLink(let status, let linkHasCredentials) = line.kind else {
            return detailLine(line, locale: locale)
        }
        return Self.line(line, reason: ClashCopy.format(
            ConfigurationFailureClassifier.refusedLinkRow(linkHasCredentials: linkHasCredentials),
            locale: locale,
            String(status)
        ), locale: locale)
    }

     
     
    static func detailLine(
        _ line: ProviderFailureLine,
        locale: Locale = .current
    ) -> String {
        Self.line(line, reason: shortReason(for: line.kind, locale: locale), locale: locale)
    }

     
    private static func line(
        _ line: ProviderFailureLine,
        reason: String,
        locale: Locale
    ) -> String {
        guard let host = line.url, !host.isEmpty else {
            return ClashCopy.format(
                "Provider “%@” — %@",
                locale: locale,
                line.name,
                reason
            )
        }
        return ClashCopy.format(
            "Provider “%@” (%@) — %@",
            locale: locale,
            line.name,
            host,
            reason
        )
    }


     
     
     
     
    private static func shortReason(
        for kind: ConfigurationFailureKind,
        locale: Locale
    ) -> String {
        switch kind {
        case .httpStatus(let status), .refusedLink(let status, _):
            return ClashCopy.format(
                "The server returned HTTP %@",
                locale: locale,
                String(status)
            )
        default:
            return ClashCopy.string(
                ConfigurationFailureClassifier.catalogTitle(for: kind),
                locale: locale
            )
        }
    }

}

private extension ConfigurationFailureKind {
     
     
     
    var isServersRefusal: Bool {
        switch self {
        case .refusedLink, .authentication: return true
        default: return false
        }
    }
}

#if os(iOS)
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum LinkAddFailureText {
     
    static let result = "Couldn’t add this link: %@"

    static func text(for failure: ConfigurationFailure, locale: Locale = .current) -> String {
        let sentence = sentence(for: failure, locale: locale)
        guard showsTheLink(failure.kind), let link = failure.transport?.failingURL, !link.isEmpty else {
            return sentence
        }
        return sentence + "\n" + link
    }

     
     
    private static func showsTheLink(_ kind: ConfigurationFailureKind) -> Bool {
        switch kind {
        case .tls, .certificate, .cleartextBlocked, .dns, .connection: return true
        default: return false
        }
    }

     
     
    private static func sentence(for failure: ConfigurationFailure, locale: Locale) -> String {
         
         
         
        if case .tls = failure.kind, failure.transport?.serverAnswered != true {
            if failure.transport?.handshakeRefused == true {
                 
                 
                 
                 
                return ClashCopy.string("Couldn’t add this link: this device and the server couldn’t set up a secure connection.",
                                        locale: locale)
            }
            return ClashCopy.string(cutHandshake(failure), locale: locale)
        }
        let reason: String
        if let row = Self.reason(for: failure) {
            reason = ClashCopy.string(for: row, locale: locale)
        } else if showsTheLink(failure.kind) {
             
             
             
             
             
            reason = ClashCopy.string(for: .copy(failure.message), locale: locale)
        } else {
             
             
             
             
             
            reason = ProfileSwitchFailureText.cardText(for: failure, locale: locale)
        }
        return ClashCopy.string(for: .format(result, [reason]), locale: locale)
    }

     
     
    private static func cutHandshake(_ failure: ConfigurationFailure) -> String {
        switch failure.transport?.throughTheTunnel {
        case false?:
             
             
             
             
             
             
            return "Couldn’t add this link: the connection was cut off before the server answered; the current network may be blocking this address. Connect Clash and try again, or try another network."
        default:
             
             
             
             
             
             
            return "Couldn’t add this link: the connection was cut off before the server answered."
        }
    }

     
    private static func reason(for failure: ConfigurationFailure) -> ClashDisplayText? {
        let code = failure.transport?.code
        switch failure.kind {
        case .connection where code.map(isOffline) == true:
             
             
            return "This device isn’t online. Try again once it is."
        case .connection where code.map(ResourceDownloader.noServerAnswered) == true
            && failure.transport?.serverAnswered != true:
             
             
             
            if failure.transport?.throughTheTunnel == false {
                return "The server couldn’t be reached. Connect Clash and try again, or try again later."
            }
            return "The server couldn’t be reached. Try again later."
        case .tls where failure.transport?.serverAnswered == true,
             .connection where code.map(ResourceDownloader.serverAnsweredUnreadably) == true
            || code.map(ResourceDownloader.noServerAnswered) == true:
             
             
             
             
            return "The server’s answer couldn’t be read. Try again later."
        case .dns:
             
             
            return "Its server can’t be found."
        case .certificate where !isClientCertificate(code):
             
            return "This device doesn’t trust the site’s security certificate."
        case .cleartextBlocked:
            return "This device can open this link only over https. Change it to start with https:// and try again."
        case .invalidURL:
            return "This isn’t a link that can be opened."
        case .refusedLink(let status, let linkHasCredentials):
             
             
            return .format(ConfigurationFailureClassifier.refusedLinkRow(linkHasCredentials: linkHasCredentials),
                           [String(status)])
        case .httpStatus(407):
             
             
            return "The server couldn’t be reached. Try again later."
        case .httpStatus(let status) where (500...599).contains(status) || status == 408 || status == 429:
            return .format("The server had a problem (HTTP %@). Try again later.", [String(status)])
        case .httpStatus(let status) where (300...499).contains(status) && status != 304:
            return .format("The link no longer opens (HTTP %@). Check it, or ask the provider for a new one.",
                           [String(status)])
        default:
            return nil
        }
    }

     
    private static func isOffline(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive: return true
        default: return false
        }
    }

     
     
    private static func isClientCertificate(_ code: URLError.Code?) -> Bool {
        code == .clientCertificateRequired || code == .clientCertificateRejected
    }
}
#endif

 
 
 
 
 
struct ProfileSwitchAlertFailure: LocalizedError {
    let titleText: String
    let messageText: String

    var errorDescription: String? { titleText }

    init(_ failure: ConfigurationFailure, locale: Locale = .current) {
         
         
         
        titleText = failure.putBackTitle?.resolved(locale: locale) ?? ClashCopy.string(failure.title, locale: locale)
        messageText = ProfileSwitchFailureText.cardText(
            for: failure, locale: locale
        )
    }
}
