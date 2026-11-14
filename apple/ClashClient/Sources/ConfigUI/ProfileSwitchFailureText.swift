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

 
 
 
 
 
struct ProfileSwitchAlertFailure: LocalizedError {
    let titleText: String
    let messageText: String

    var errorDescription: String? { titleText }

    init(_ failure: ConfigurationFailure, locale: Locale = .current) {
        titleText = ClashCopy.string(failure.title, locale: locale)
        messageText = ProfileSwitchFailureText.cardText(
            for: failure, locale: locale
        )
    }
}
