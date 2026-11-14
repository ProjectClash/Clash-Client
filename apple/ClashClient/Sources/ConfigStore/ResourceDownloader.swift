import Foundation
import ClashClientKit
import ClashClientUI

struct DownloadResult {
    let data: Data
    let etag: String?
    let lastModified: String?
    let subscriptionUserInfo: String?
     
     
    var contentDisposition: String? = nil
    let notModified: Bool
}

enum DownloadError: LocalizedError, Equatable {
    case invalidLimit
    case tooLarge(Int)
    case badStatus(Int)
     
     
     
     
     
    case refusedAuthorization(Int)
     
     
     
    case linkRefused(status: Int, carried: RefusedCredential)
     
    case invalidPayload(name: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidLimit:
            return "The download safety limit is invalid."
        case .tooLarge(let observedBytes):
            return "The download is too large (at least \(observedBytes) bytes)."
        case .invalidPayload(let name, let reason):
             
             
             
             
             
             
             
            var message = "%@ was not updated: %@."
            for argument in [name, reason] {
                guard let range = message.range(of: "%@") else { break }
                message.replaceSubrange(range, with: argument)
            }
            return message
        case .badStatus(let status), .refusedAuthorization(let status), .linkRefused(let status, _):
            if status < 0 { return "The server returned an invalid response." }
            return "The server returned HTTP \(status)."
        }
    }

     
     
    var authoredText: AuthoredText {
        switch self {
        case .invalidLimit: return .app("The download safety limit is invalid.")
        case .tooLarge(let observedBytes):
            return .app("The download is too large (at least %@ bytes).", arguments: [String(observedBytes)])
        case .invalidPayload(let name, let reason): return .app("%@ was not updated: %@.", arguments: [name, reason])
        case .badStatus(let status), .refusedAuthorization(let status), .linkRefused(let status, _):
            if status < 0 { return .app("The server returned an invalid response.") }
            return .app("The server returned HTTP %@", arguments: [String(status)])
        }
    }

     
     
     
    static func refusesTheLink(_ status: Int) -> Bool {
        status == 401 || status == 403
    }

     
     
     
     
     
    static func refusingALink(_ error: Error, sent: RefusedCredential) -> Error {
        switch error as? DownloadError {
        case .badStatus(let status)? where refusesTheLink(status):
            return DownloadError.linkRefused(status: status, carried: .other)
        case .refusedAuthorization(let status)?:
            return DownloadError.linkRefused(status: status, carried: sent)
        case .badStatus?, .linkRefused?, .tooLarge?, .invalidLimit?, .invalidPayload?, nil:
            return error
        }
    }
}

 
enum RefusedCredential: Equatable, Sendable {
     
     
    case other
     
     
    case theLinks
     
     
    case saved

     
     
     
    static func of(_ request: URLRequest, link: URL?, saved: String?) -> RefusedCredential {
        guard let header = request.value(forHTTPHeaderField: "Authorization") else { return .other }
        if let saved, header == saved { return .saved }
        if let link, header == ProviderMaterializer.basicAuthorization(from: link) { return .theLinks }
        return .other
    }
}

 
 
 
 
 
 
 
 
 
enum ConfigurationFailureContext: Equatable {
    case subscription
    case activation
    case provider
    case geodata
    case localImport
}

enum ConfigurationFailureKind: Equatable {
    case dns
    case connection
    case tls
    case certificate
    case cleartextBlocked
     
     
     
     
    case authentication
     
     
     
     
    case refusedLink(status: Int, linkHasCredentials: Bool)
    case httpStatus(Int)
    case invalidResponse
    case bodyTooLarge
    case invalidURL
    case invalidTextEncoding
    case yamlSyntax
    case mihomoSchema
    case resourcePlan
    case providerMaterialization
    case providerDownloads
    case kernelRejected
    case geodataMaterialization
    case preflight
    case credential
    case sourceMissing
    case legacyRelay
    case unknown
}

enum ConfigurationRecoveryAction: String, Equatable, Identifiable {
    case retry
    case editCredentials
    case editProfile
    case openProxyChains
    case viewDiagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .retry: return "Try Again"
        case .editCredentials: return "Edit Credentials"
        case .editProfile: return "Edit Profile"
        case .openProxyChains: return "Open Proxy Chains"
        case .viewDiagnostics: return "View Safe Diagnostics"
        }
    }
}

struct ConfigurationFailure: LocalizedError, Equatable {
    let kind: ConfigurationFailureKind
    let context: ConfigurationFailureContext
    let title: String
    let message: String
    let diagnosticCode: String
    let recoveryActions: [ConfigurationRecoveryAction]
    let preservesLastKnownGood: Bool
     
     
     
     
    let providerFailures: [ProviderFailureLine]
     
     
     
     
     
     
     
     
     
     
    let detail: String?

    init(
        kind: ConfigurationFailureKind,
        context: ConfigurationFailureContext,
        title: String,
        message: String,
        diagnosticCode: String,
        recoveryActions: [ConfigurationRecoveryAction],
        preservesLastKnownGood: Bool,
        providerFailures: [ProviderFailureLine] = [],
        detail: String? = nil
    ) {
        self.kind = kind
        self.context = context
        self.title = title
        self.message = message
        self.diagnosticCode = diagnosticCode
        self.recoveryActions = recoveryActions
        self.preservesLastKnownGood = preservesLastKnownGood
        self.providerFailures = providerFailures
        self.detail = detail
    }

    func carrying(_ lines: [ProviderFailureLine]) -> ConfigurationFailure {
        ConfigurationFailure(
            kind: kind, context: context, title: title, message: message,
            diagnosticCode: diagnosticCode, recoveryActions: recoveryActions,
            preservesLastKnownGood: preservesLastKnownGood,
            providerFailures: lines,
            detail: detail
        )
    }

    var errorDescription: String? { "\(title): \(message)" }

     
     
     
     
     
    var kernelSentence: String {
        if let detail, !detail.isEmpty { return detail }
        return message
    }

     
     
     
    var displayMessage: ClashDisplayText {
        if case .httpStatus(let status) = kind {
            return .format(
                "The server returned HTTP %@. Try again or check the profile source.",
                [String(status)]
            )
        }
        if case .refusedLink(let status, let linkHasCredentials) = kind {
            return .format(ConfigurationFailureClassifier.refusedLinkRow(linkHasCredentials: linkHasCredentials),
                           [String(status)])
        }
        if let detail, !detail.isEmpty {
            switch kind {
            case .mihomoSchema:
                return .format("The core rejected this configuration: %@", [detail])
            case .yamlSyntax:
                return .format("This is not valid configuration YAML: %@", [detail])
            case .resourcePlan:
                return .format("A resource in this configuration cannot be prepared on iOS: %@", [detail])
            case .preflight:
                return .format("The generated runtime was rejected: %@", [detail])
            case .tls, .certificate, .cleartextBlocked, .dns, .connection:
                 
                 
                 
                 
                return .formatCopy("%@\n%@", [message, detail])
            default:
                break
            }
        }
        return .copy(message)
    }
}

 
 
 
struct ProviderFailureLine: Equatable {
    let name: String
     
     
     
    let url: String?
    let kind: ConfigurationFailureKind
}

enum ConfigurationFailureClassifier {
    static func classify(
        _ error: Error,
        context: ConfigurationFailureContext,
        preservesLastKnownGood: Bool? = nil
    ) -> ConfigurationFailure? {
        if error is CancellationError { return nil }
         
         
         
        if ProfileActivationCoordinator.superseded(error)
            || ProfileActivationCoordinator.lostToASwitch(error) { return nil }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return nil }
            return classifyURL(urlError, context: context,
                               preservesLastKnownGood: preservesLastKnownGood)
        }
        if let download = error as? DownloadError {
            switch download {
            case .linkRefused(_, .saved):
                 
                 
                 
                return make(.authentication, context, preservesLastKnownGood)
            case .linkRefused(let status, let carried):
                 
                 
                 
                 
                return make(.refusedLink(status: status, linkHasCredentials: carried == .theLinks),
                            context, preservesLastKnownGood)
            case .badStatus(let status) where status >= 0, .refusedAuthorization(let status):
                 
                 
                 
                return make(.httpStatus(status), context, preservesLastKnownGood)
            case .badStatus:
                return make(.invalidResponse, context, preservesLastKnownGood)
            case .tooLarge:
                return make(.bodyTooLarge, context, preservesLastKnownGood)
            case .invalidLimit:
                return make(.unknown, context, preservesLastKnownGood,
                            diagnosticCode: "internal.download-limit")
            case .invalidPayload:
                 
                 
                return make(.invalidResponse, context, preservesLastKnownGood)
            }
        }
        if let subscription = error as? SubscriptionError {
            switch subscription {
            case .notARemoteSource:
                return make(.sourceMissing, context, preservesLastKnownGood)
            case .badURL:
                return make(.invalidURL, context, preservesLastKnownGood)
            case .notUTF8:
                return make(.invalidTextEncoding, context, preservesLastKnownGood)
            }
        }
        if let transforms = error as? ConfigTransformsError {
            switch transforms {
            case .invalidConfiguration(let reason):
                return make(refusalKind(reason), context, preservesLastKnownGood, detail: reason)
            case .bridgeReturnedNil:
                return make(.mihomoSchema, context, preservesLastKnownGood)
            }
        }
        if let bridge = error as? ProxyImportBridgeError,
           case .refusedConfiguration(let reason, _) = bridge {
             
             
             
             
            return make(refusalKind(reason), context, preservesLastKnownGood, detail: reason)
        }
        if let finding = error as? IOSExternalResourceFinding {
            return externalResourceFailure(
                message: finding.localizedDescription,
                context: context,
                preservesLastKnownGood: preservesLastKnownGood
            )
        }
        if let resource = error as? ProfileExternalResourceError {
            return externalResourceFailure(
                message: resource.localizedDescription,
                context: context,
                preservesLastKnownGood: preservesLastKnownGood
            )
        }
        if let relay = error as? LegacyRelayMigrationError {
            return ConfigurationFailure(
                kind: .legacyRelay,
                context: context,
                title: "Legacy relay needs attention",
                message: relay.localizedDescription,
                diagnosticCode: "config.legacy-relay",
                recoveryActions: [.openProxyChains, .editProfile, .viewDiagnostics],
                preservesLastKnownGood: preservesLastKnownGood
                    ?? (context == .activation || context == .subscription)
            )
        }
        if let pipeline = error as? PipelineError {
            switch pipeline {
            case .planRejected(let failures):
                 
                 
                 
                 
                let message = failures.isEmpty
                    ? "A provider or geodata entry cannot be materialized safely on iOS."
                    : failures.map { Self.readable($0) }.joined(separator: "\n")
                return externalResourceFailure(
                    message: message,
                    context: context,
                    preservesLastKnownGood: preservesLastKnownGood
                )
            case .externalResources(let findings):
                let message = findings.first?.errorDescription
                    ?? "A referenced configuration resource is unavailable on iOS."
                return externalResourceFailure(
                    message: message,
                    context: context,
                    preservesLastKnownGood: preservesLastKnownGood
                )
            case .preflightFailed(let reason):
                 
                 
                 
                 
                 
                if Self.isMissingPacketTunnelDNS(reason) {
                    return make(
                        .preflight, context, preservesLastKnownGood,
                        diagnosticCode: "config.preflight.dns",
                         
                         
                         
                        message: "iOS resolves DNS inside the tunnel, so this profile needs a dns section with enable turned on and at least one IP nameserver (for example 1.1.1.1). Add one to the profile, then try again."
                    )
                }
                return make(.preflight, context, preservesLastKnownGood, detail: reason)
            case .sourceUnavailable, .notModifiedWithoutActive:
                return make(.sourceMissing, context, preservesLastKnownGood)
            case .sourceSuperseded:
                return nil   
            case .providerNotFound:
                return make(.providerMaterialization, context, preservesLastKnownGood)
            case .activationReadback:
                 
                 
                 
                 
                 
                return make(
                    .unknown, context, preservesLastKnownGood,
                    diagnosticCode: "activation.readback",
                    message: "Clash wrote the switch but could not read it back as the active configuration. Try again."
                )
            }
        }
        if let vault = error as? ProxyCredentialVault.VaultError {
            switch vault {
            case .missingCredential, .credentialCollision:
                return make(.credential, context, preservesLastKnownGood)
            case .missingProxyIdentity:
                return make(.mihomoSchema, context, preservesLastKnownGood)
            case .invalidConfiguration:
                return make(.yamlSyntax, context, preservesLastKnownGood)
            }
        }
        if let aggregate = error as? ProviderDownloadFailuresError,
           let first = aggregate.failures.first {
            let lines = aggregate.failures.map { failure in
                ProviderFailureLine(
                    name: failure.provider,
                    url: failure.url,
                    kind: classify(
                        failure.underlying,
                        context: context,
                        preservesLastKnownGood: preservesLastKnownGood
                    )?.kind ?? .unknown
                )
            }
            if aggregate.failures.count == 1,
               let single = classify(
                   first.underlying,
                   context: context,
                   preservesLastKnownGood: preservesLastKnownGood
               ) {
                return single.carrying(lines)
            }
            return make(
                .providerDownloads, context, preservesLastKnownGood
            ).carrying(lines)
        }
        if let refused = error as? ProviderValidationFailure {
            let classified = classify(
                refused.underlying,
                context: context,
                preservesLastKnownGood: preservesLastKnownGood
            )
            guard classified?.kind == .kernelRejected else {
                return classified?.carrying([
                    ProviderFailureLine(
                        name: refused.provider, url: nil,
                        kind: classified?.kind ?? .unknown
                    ),
                ])
            }
            return classified?.carrying([
                ProviderFailureLine(
                    name: refused.provider, url: nil, kind: .kernelRejected
                ),
            ])
        }
        if let kernel = kernelSentence(from: error) {
             
             
             
             
            return make(
                .kernelRejected, context, preservesLastKnownGood,
                message: kernel
            )
        }
        if let materialize = error as? MaterializeError {
            switch materialize {
            case .ageKeyMissing, .ageDecryptFailed:
                return make(.credential, context, preservesLastKnownGood)
            case .badURL:
                return make(.invalidURL, context, preservesLastKnownGood)
            case .unsafePath, .unsafeHeader:
                return make(.providerMaterialization, context, preservesLastKnownGood)
            }
        }
        if let library = error as? ConfigurationLibraryError, case .missingNodes = library {
             
             
             
            return make(.invalidResponse, context, preservesLastKnownGood,
                        message: (error as NSError).localizedDescription)
        }
        switch context {
        case .provider:
            return make(.providerMaterialization, context, preservesLastKnownGood)
        case .geodata:
            return make(.geodataMaterialization, context, preservesLastKnownGood)
        case .localImport:
            return make(.invalidResponse, context, preservesLastKnownGood,
                        diagnosticCode: "import.read")
        case .subscription, .activation:
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            let underlying = (error as NSError).localizedDescription
            return make(
                .unknown, context, preservesLastKnownGood,
                message: underlying.isEmpty
                    ? "No changes were published, and the reason was not recognised."
                    : "No changes were published. The operation reported: \(underlying)"
            )
        }
    }

     
     
     
     
     
     
     
    private static func classifyURL(
        _ error: URLError,
        context: ConfigurationFailureContext,
        preservesLastKnownGood: Bool?
    ) -> ConfigurationFailure {
        let kind: ConfigurationFailureKind
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            kind = .dns
        case .timedOut, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed:
            kind = .connection
        case .secureConnectionFailed where ResourceDownloader.refusesTheCertificate(error):
             
             
            kind = .certificate
        case .secureConnectionFailed:
             
             
             
            kind = .tls
        case .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
             
             
             
             
            kind = .certificate
        case .appTransportSecurityRequiresSecureConnection:
             
             
             
            kind = .cleartextBlocked
        case .userAuthenticationRequired:
            kind = .authentication
        case .badURL, .unsupportedURL:
            kind = .invalidURL
        default:
            kind = .connection
        }
        return make(
            kind, context, preservesLastKnownGood,
            detail: urlErrorDetail(error)
        )
    }

     
    private static func urlErrorDetail(_ error: URLError) -> String? {
        let sentence = error.localizedDescription
        let failing = (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
            ?? error.failingURL?.absoluteString
        switch (sentence.isEmpty, failing) {
        case (true, .none): return nil
        case (true, .some(let url)): return url
        case (false, .none): return sentence
        case (false, .some(let url)): return "\(sentence) (\(url))"
        }
    }

    private static func externalResourceFailure(
        message: String,
        context: ConfigurationFailureContext,
        preservesLastKnownGood: Bool?
    ) -> ConfigurationFailure {
        ConfigurationFailure(
            kind: .resourcePlan,
            context: context,
            title: "Configuration resource needs attention",
            message: message,
            diagnosticCode: "config.external-resource",
            recoveryActions: [.editProfile, .viewDiagnostics],
            preservesLastKnownGood: preservesLastKnownGood
                ?? (context == .activation || context == .subscription)
        )
    }

     
     
     
    private static func isMissingPacketTunnelDNS(_ reason: String) -> Bool {
        let lowered = reason.lowercased()
        return lowered.contains("dns.enable must be true")
            || lowered.contains("dns.nameserver must be set")
    }

    private static func make(
        _ kind: ConfigurationFailureKind,
        _ context: ConfigurationFailureContext,
        _ preservesLastKnownGood: Bool?,
        diagnosticCode overrideCode: String? = nil,
        message overrideMessage: String? = nil,
        detail: String? = nil
    ) -> ConfigurationFailure {
        let presentation = presentation(for: kind)
        return ConfigurationFailure(
            kind: kind,
            context: context,
            title: presentation.title,
            message: overrideMessage ?? presentation.message,
            diagnosticCode: overrideCode ?? presentation.code,
            recoveryActions: recoveryActions(for: kind),
            preservesLastKnownGood: preservesLastKnownGood
                ?? (context == .activation || context == .subscription || context == .provider),
            detail: detail.map(readableDetail(from:))
        )
    }

     
     
     
    private static func readableDetail(from raw: String) -> String {
        raw
    }


     
     
    static func catalogMessage(for kind: ConfigurationFailureKind) -> String {
        presentation(for: kind).message
    }

     
     
    static func catalogTitle(for kind: ConfigurationFailureKind) -> String {
        presentation(for: kind).title
    }

     
     
     
     
    static func refusedLinkRow(linkHasCredentials: Bool) -> String {
        linkHasCredentials
            ? "The server refused this link (HTTP %@). Check the user name and password in the link. The link may also have expired or been reset, or the provider may limit which apps can use it."
            : "The server refused this link (HTTP %@). The link may have expired or been reset, or the provider may limit which apps can use it."
    }


     
     
     
     
     
     
     
    private static func refusalKind(_ reason: String) -> ConfigurationFailureKind {
        let normalized = reason.lowercased()
        let yamlMarkers = [
            "yaml", "line ", "mapping", "did not find expected",
            "cannot unmarshal", "could not find expected",
        ]
        return yamlMarkers.contains { normalized.contains($0) } ? .yamlSyntax : .mihomoSchema
    }

    private static func kernelSentence(from error: Error) -> String? {
        let nsError = error as NSError
        let text = nsError.localizedDescription
        guard nsError.domain == "go" || text.hasPrefix("clash:") || text.hasPrefix("clash:") else {
            return nil
        }
        return readableDetail(from: text)
    }

     
     
    private static func recoveryActions(
        for kind: ConfigurationFailureKind
    ) -> [ConfigurationRecoveryAction] {
        switch kind {
        case .authentication, .credential:
             
            return [.editCredentials, .retry, .viewDiagnostics]
        case .refusedLink(_, linkHasCredentials: true):
             
             
            return [.editProfile, .retry, .viewDiagnostics]
        case .refusedLink(_, linkHasCredentials: false):
             
             
            return [.retry, .editProfile, .viewDiagnostics]
        case .invalidURL, .invalidTextEncoding, .yamlSyntax, .mihomoSchema,
             .resourcePlan, .preflight, .sourceMissing, .bodyTooLarge:
            return [.editProfile, .viewDiagnostics]
        case .legacyRelay:
            return [.openProxyChains, .editProfile, .viewDiagnostics]
        case .providerMaterialization, .providerDownloads, .kernelRejected:
            return [.retry, .editCredentials, .viewDiagnostics]
        case .dns, .connection, .tls, .certificate, .cleartextBlocked,
             .httpStatus, .invalidResponse, .geodataMaterialization, .unknown:
            return [.retry, .viewDiagnostics]
        }
    }

    private static func presentation(
        for kind: ConfigurationFailureKind
    ) -> (title: String, message: String, code: String) {
        switch kind {
        case .dns:
            return (title: "DNS lookup failed", message: "The server name could not be resolved. Check the network, then try again.", code: "network.dns")
        case .connection:
            return (title: "Connection failed", message: "The server could not be reached after retrying. Check connectivity and try again.", code: "network.connect")
        case .tls:
            return (title: "Secure connection failed", message: "The TLS handshake was cut off before the server answered. If this address is blocked on the current network, connect first and try again.", code: "network.tls")
        case .certificate:
            return (title: "Certificate rejected", message: "The server's certificate isn't trusted on this device, or the server asked for a client certificate.", code: "network.certificate")
        case .cleartextBlocked:
            return (title: "Plain HTTP is not allowed", message: "This platform only allows https for this address.", code: "network.cleartext")
        case .authentication:
            return (title: "Authentication failed", message: "The server rejected the saved credentials. Update them before retrying.", code: "http.auth")
        case .refusedLink(let status, let linkHasCredentials):
             
             
             
            return (title: "Server refused the link",
                    message: refusedLinkRow(linkHasCredentials: linkHasCredentials)
                        .replacingOccurrences(of: "%@", with: String(status)),
                    code: linkHasCredentials ? "http.refused.credentials" : "http.refused")
        case .httpStatus(let status):
             
             
            return (title: "Server rejected the request", message: "The server returned HTTP \(status). Try again or check the profile source.", code: "http.\(status)")
        case .invalidResponse:
            return (title: "Invalid server response", message: "The response was not a usable configuration resource.", code: "http.invalid-response")
        case .bodyTooLarge:
            return (title: "Download is too large", message: "The resource exceeded Clash’s safety limit and was not saved.", code: "download.too-large")
        case .invalidURL:
            return (title: "Invalid resource address", message: "Edit the profile and enter a valid address.", code: "source.invalid-url")
        case .invalidTextEncoding:
            return (title: "Unreadable configuration", message: "The profile URL response is not UTF-8 YAML.", code: "config.encoding")
        case .yamlSyntax:
            return (title: "YAML syntax error", message: "The downloaded text is not valid configuration YAML. Edit the profile or contact the provider.", code: "config.yaml")
        case .mihomoSchema:
            return (title: "Unsupported configuration", message: "The core rejected the configuration structure or one of its fields.", code: "config.schema")
        case .resourcePlan:
            return (title: "Resource plan rejected", message: "A provider or geodata entry cannot be materialized safely on iOS.", code: "config.resource-plan")
        case .providerMaterialization:
            return (title: "Provider update failed", message: "The provider could not be downloaded, decrypted, or validated. The published revision was kept.", code: "provider.materialize")
        case .providerDownloads:
            return (title: "Provider downloads failed", message: "More than one provider could not be downloaded.", code: "provider.downloads")
        case .kernelRejected:
            return (title: "The core refused this configuration", message: "The core refused this configuration.", code: "config.kernel")
        case .geodataMaterialization:
            return (title: "Geo resource update failed", message: "The geo resource could not be downloaded or staged. The existing file was kept.", code: "geodata.materialize")
        case .preflight:
            return (title: "Configuration preflight failed", message: "The generated runtime was rejected before it could become active.", code: "config.preflight")
        case .credential:
            return (title: "Credential needs attention", message: "A required credential is missing, invalid, or conflicts with the proxy identity.", code: "credential.repair")
        case .sourceMissing:
            return (title: "Profile source is unavailable", message: "Re-import or edit the profile before trying again.", code: "source.missing")
        case .legacyRelay:
            return (title: "Legacy relay needs attention", message: "Review the removed relay group in Proxy Chains.", code: "config.legacy-relay")
        case .unknown:
            return (title: "Configuration operation failed", message: "No changes were published. Try again and use the safe diagnostic code if the problem continues.", code: "config.unknown")
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum DirectFetchFallback {
    @MainActor static var perform: ((_ request: URLRequest, _ maxBytes: Int, _ timeout: TimeInterval,
                                     _ redirectPolicy: DownloadRedirectPolicy) async throws -> DownloadResult)?

     
     
     
     
     
     
    @TaskLocal static var deadline: Date? = nil

     
     
     
     
    @MainActor static var isUsable: (() async -> Bool)?

    static func usable() async -> Bool {
        guard let check = await isUsable else { return await perform != nil }
        return await check()
    }
}

 
 
struct DirectFetchUnavailable: Error {}

protocol HTTPFetching {
    func fetch(
        _ request: URLRequest,
        maxBytes: Int,
        redirectPolicy: DownloadRedirectPolicy
    ) async throws -> DownloadResult
}



enum DownloadRedirectPolicy: Equatable, Sendable {
    case sameOrigin
     
     
     
    case followAcrossOrigins(maxHops: Int)
     
     
     
    case followWithinAModulesReach(maxHops: Int)
}

 
enum DownloadHostPlace: Equatable, Sendable {
     
    case thisDevice
     
    case localNetwork
    case internet

    static func of(_ raw: String) -> DownloadHostPlace {
        var host = raw.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".localhost") { return .thisDevice }
        if host.hasSuffix(".local") { return .localNetwork }
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return of(ipv4: UInt32(bigEndian: v4.s_addr)) }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, host, &v6) == 1 else { return .internet }
        let bytes = withUnsafeBytes(of: v6) { Array($0) }
        if bytes.allSatisfy({ $0 == 0 }) || bytes == [UInt8](repeating: 0, count: 15) + [1] { return .thisDevice }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return .thisDevice }
        if bytes[0] & 0xFE == 0xFC { return .localNetwork }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return of(ipv4: bytes[12..<16].reduce(0) { $0 << 8 | UInt32($1) })
        }
        return .internet
    }

    private static func of(ipv4 address: UInt32) -> DownloadHostPlace {
        let a = address >> 24, b = (address >> 16) & 0xFF
        if a == 127 || a == 0 || (a == 169 && b == 254) { return .thisDevice }
        if a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) { return .localNetwork }
        return .internet
    }

     
     
    static func reachableByAModule(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        return of(host) != .thisDevice
    }
}

 
 
struct UnprotectedRedirectRefused: LocalizedError, Equatable {
    let from: String
    let to: String

    var errorDescription: String? { "the download was sent on from \(from) to \(to), which is not protected" }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class SecureRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let policy: DownloadRedirectPolicy
    private var redirectCount = 0
    private let lock = NSLock()
    private var refused: UnprotectedRedirectRefused?
     
     
    private var handedOn: (followed: Bool, authorization: String?) = (false, nil)

    init(policy: DownloadRedirectPolicy) {
        self.policy = policy
    }

     
    var refusedRedirect: UnprotectedRedirectRefused? {
        lock.lock(); defer { lock.unlock() }
        return refused
    }

     
     
     
     
     
    func finalAuthorization(of original: URLRequest) -> String? {
        lock.lock(); defer { lock.unlock() }
        return handedOn.followed ? handedOn.authorization : original.value(forHTTPHeaderField: "Authorization")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
         
         
        let handOn: (URLRequest?) -> Void = { [self] next in
            if let next {
                lock.lock(); handedOn = (true, next.value(forHTTPHeaderField: "Authorization")); lock.unlock()
            }
            completionHandler(next)
        }
        guard let destination = request.url,
              let original = task.originalRequest?.url else {
            handOn(nil)
            return
        }
         
        if case .followWithinAModulesReach = policy, !DownloadHostPlace.reachableByAModule(destination) {
            let refusal = UnprotectedRedirectRefused(from: response.url?.absoluteString ?? original.absoluteString,
                                                     to: destination.absoluteString)
            lock.lock(); refused = refusal; lock.unlock()
            handOn(nil)
            return
        }
        let sameOrigin = Self.origin(of: original) == Self.origin(of: destination)
        switch policy {
        case .sameOrigin:
            handOn(sameOrigin ? request : nil)
        case .followAcrossOrigins(let maxHops), .followWithinAModulesReach(let maxHops):
            redirectCount += 1
            guard maxHops > 0, redirectCount <= maxHops else {
                handOn(nil)
                return
            }
            guard !sameOrigin else {
                handOn(request)
                return
            }
            var sanitized = request
            if let headers = sanitized.allHTTPHeaderFields {
                for header in headers.keys {
                    sanitized.setValue(nil, forHTTPHeaderField: header)
                }
            }
            for header in [
                "Authorization", "Proxy-Authorization", "Cookie",
                "If-None-Match", "If-Modified-Since",
            ] {
                sanitized.setValue(nil, forHTTPHeaderField: header)
            }
            if let userAgent = task.originalRequest?.value(forHTTPHeaderField: "User-Agent") {
                sanitized.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            handOn(sanitized)
        }
    }

    private static func origin(of url: URL) -> String {
        let port = url.port.map(String.init) ?? ""
        return "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(port)"
    }
}

 
 
final class ResourceDownloader: HTTPFetching {
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    private struct RetryableStatus: Error {
        let status: Int
        let delayNanoseconds: UInt64?
    }

    private let session: URLSession
    let maximumAttempts: Int
     
     
     
     
     
     
    static let quickTimeoutSeconds: TimeInterval = 8

    static func quick() -> ResourceDownloader {
         
        ResourceDownloader(session: bounded(seconds: quickTimeoutSeconds), maximumAttempts: 1, fallsBackDirect: false)
    }

     
     
     
    static let connectTimeoutSeconds: TimeInterval = 30

    static func connect() -> ResourceDownloader {
        ResourceDownloader(session: bounded(seconds: connectTimeoutSeconds), maximumAttempts: 1, fallsBackDirect: false)
    }
     
     
     
     
    static func verified() -> ResourceDownloader {
        ResourceDownloader(fallsBackDirect: false)
    }

     
     
     
     
    let fallsBackDirect: Bool
    private let timeoutSeconds: TimeInterval
    private let sleeper: Sleeper

     
     
     
     
     
     
     
     
     
    static func bounded(seconds: TimeInterval = 20) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
         
         
         
         
        configuration.timeoutIntervalForRequest = seconds
        configuration.timeoutIntervalForResource = seconds
         
         
         
        configuration.waitsForConnectivity = false
         
         
         
         
         
         
         
         
         
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    init(
        session: URLSession = ResourceDownloader.bounded(),
        maximumAttempts: Int = 3,
        fallsBackDirect: Bool = true,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.session = session
        self.maximumAttempts = max(1, maximumAttempts)
        self.fallsBackDirect = fallsBackDirect
        self.timeoutSeconds = session.configuration.timeoutIntervalForResource
        self.sleeper = sleeper
    }

     
     
     
     
     
    func fetch(
        _ request: URLRequest,
        maxBytes: Int,
        redirectPolicy: DownloadRedirectPolicy
    ) async throws -> DownloadResult {
         
         
         
         
        var reservesDirect = false
        if DirectFetchFallback.deadline != nil, fallsBackDirect,
           Self.directMayRetry(request, redirectPolicy: redirectPolicy, after: URLError(.timedOut)) {
            reservesDirect = await DirectFetchFallback.usable()
        }
        do {
            return try await fetchThroughTheTunnel(request, maxBytes: maxBytes, redirectPolicy: redirectPolicy,
                                                   reservesDirect: reservesDirect)
        } catch is CancellationError {
            throw CancellationError()
        } catch DownloadError.invalidLimit {
            throw DownloadError.invalidLimit
        } catch DownloadError.tooLarge(let size) {
            throw DownloadError.tooLarge(size)
        } catch {
            guard fallsBackDirect, Self.directMayRetry(request, redirectPolicy: redirectPolicy, after: error),
                  !Task.isCancelled,
                  let direct = await DirectFetchFallback.perform else { throw error }
            do {
                 
                 
                let result = try await direct(request, maxBytes, max(timeoutSeconds, 10), redirectPolicy)
                ClashLogStore.shared.append(
                    "download through the tunnel failed (\(error.localizedDescription)); fetched over DIRECT instead (\(request.url?.absoluteString ?? "?"))",
                    stream: .app, level: .info)
                return result
            } catch is DirectFetchUnavailable {
                 
                 
                guard reservesDirect else { throw error }
                return try await fetchThroughTheTunnel(request, maxBytes: maxBytes, redirectPolicy: redirectPolicy,
                                                       reservesDirect: false)
            } catch is CancellationError {
                throw CancellationError()
            } catch let directFailure {
                ClashLogStore.shared.append(
                    "download over DIRECT failed too: \(directFailure.localizedDescription) (\(request.url?.absoluteString ?? "?"))",
                    stream: .app, level: .warning)
                throw error
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func directMayRetry(_ request: URLRequest, redirectPolicy: DownloadRedirectPolicy, after error: Error) -> Bool {
         
         
        guard (request.httpMethod ?? "GET").uppercased() == "GET", request.httpBody == nil,
              request.httpBodyStream == nil else { return false }
        guard let urlError = error as? URLError else { return false }
         
         
         
         
        return urlError.code != .cancelled && !refusesTheCertificate(urlError)
    }

     
     
     
     
     
    static func refusesTheCertificate(_ error: URLError) -> Bool {
        switch error.code {
        case .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return true
        case .secureConnectionFailed:
             
             
             
            if error.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] != nil { return true }
            let code = (error.userInfo["_kCFStreamErrorCodeKey"] as? NSNumber)?.intValue
            return code.map { [-9807, -9808, -9812, -9813, -9814, -9815, -9843].contains($0) } ?? false
        default:
            return false
        }
    }

     
     
     
    static let backgroundDirectReserve: TimeInterval = 10 + ClashCommandClient.directFetchCoreAnswerGrace + 1

     
     
     
    static func backgroundTunnelSeconds(_ timeout: TimeInterval, deadline: Date, reservesDirect: Bool,
                                        now: Date = Date()) -> TimeInterval? {
        let left = deadline.timeIntervalSince(now) - (reservesDirect ? backgroundDirectReserve : 0)
        guard left >= 1 else { return nil }
        return min(timeout, left)
    }

    private func fetchThroughTheTunnel(
        _ request: URLRequest,
        maxBytes: Int,
        redirectPolicy: DownloadRedirectPolicy,
        reservesDirect: Bool
    ) async throws -> DownloadResult {
        guard maxBytes > 0 else { throw DownloadError.invalidLimit }
         
         
         
         
         
        let deadline = DirectFetchFallback.deadline
        let maximumAttempts = deadline == nil ? self.maximumAttempts : 1
        var attempt = 0
        while true {
            try Task.checkCancellation()
            var within: TimeInterval?
            if let deadline {
                guard let seconds = Self.backgroundTunnelSeconds(timeoutSeconds, deadline: deadline,
                                                                 reservesDirect: reservesDirect) else {
                    throw URLError(.timedOut)
                }
                within = seconds
            }
            do {
                return try await fetchOnce(
                    request,
                    maxBytes: maxBytes,
                    redirectPolicy: redirectPolicy,
                    within: within
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let status as RetryableStatus {
                attempt += 1
                guard attempt < maximumAttempts else {
                    throw DownloadError.badStatus(status.status)
                }
                try await sleeper(status.delayNanoseconds ?? backoff(forAttempt: attempt))
            } catch let error as URLError where isRetryable(error) {
                attempt += 1
                guard attempt < maximumAttempts else {
                    Self.logTransportFailure(error, attempts: attempt)
                    throw error
                }
                try await sleeper(backoff(forAttempt: attempt))
            } catch let error as URLError {
                Self.logTransportFailure(error, attempts: attempt + 1)
                throw error
            }
        }
    }

     
     
     
    private static func logTransportFailure(_ error: URLError, attempts: Int) {
        let failing = (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
            ?? error.failingURL?.absoluteString ?? "?"
        ClashLogStore.shared.append(
            "download failed code=\(error.code.rawValue) attempts=\(attempts) \(error.localizedDescription) (\(failing))",
            stream: .app,
            level: .warning
        )
    }

     
     
     
    private func fetchOnce(
        _ request: URLRequest,
        maxBytes: Int,
        redirectPolicy: DownloadRedirectPolicy,
        within seconds: TimeInterval?
    ) async throws -> DownloadResult {
        guard let seconds else {
            return try await fetchOnce(request, maxBytes: maxBytes, redirectPolicy: redirectPolicy)
        }
        return try await withThrowingTaskGroup(of: DownloadResult.self) { group in
            group.addTask { try await self.fetchOnce(request, maxBytes: maxBytes, redirectPolicy: redirectPolicy) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }

    private func fetchOnce(
        _ request: URLRequest,
        maxBytes: Int,
        redirectPolicy: DownloadRedirectPolicy
    ) async throws -> DownloadResult {
        let delegate = SecureRedirectDelegate(policy: redirectPolicy)
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        if let refused = delegate.refusedRedirect {
            ClashLogStore.shared.append("download refused: \(refused.localizedDescription)", stream: .app, level: .warning)
            throw refused
        }
        guard let http = response as? HTTPURLResponse else { throw DownloadError.badStatus(-1) }
        if http.statusCode == 304 {
            return DownloadResult(data: Data(), etag: header(http, "Etag"),
                                  lastModified: header(http, "Last-Modified"),
                                  subscriptionUserInfo: nil,
                                  contentDisposition: nil, notModified: true)
        }
        if isRetryableStatus(http.statusCode) {
            throw RetryableStatus(
                status: http.statusCode,
                delayNanoseconds: retryAfterNanoseconds(http)
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.statusError(http.statusCode, of: request,
                                   finalAuthorization: delegate.finalAuthorization(of: request))
        }
        if http.expectedContentLength > Int64(maxBytes) {
            throw DownloadError.tooLarge(Int(http.expectedContentLength))
        }
        var data = Data()
        data.reserveCapacity(min(maxBytes, max(0, Int(http.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maxBytes else {
                throw DownloadError.tooLarge(data.count + 1)
            }
            data.append(byte)
        }
        return DownloadResult(data: data, etag: header(http, "Etag"),
                              lastModified: header(http, "Last-Modified"),
                              subscriptionUserInfo: header(http, "subscription-userinfo"),
                              contentDisposition: header(http, "Content-Disposition"),
                              notModified: false)
    }

    private func header(_ r: HTTPURLResponse, _ name: String) -> String? {
        r.value(forHTTPHeaderField: name)
    }

     
     
     
     
    static func statusError(_ status: Int, of request: URLRequest, finalAuthorization: String?) -> DownloadError {
        guard DownloadError.refusesTheLink(status), let sent = request.value(forHTTPHeaderField: "Authorization"),
              finalAuthorization == sent else { return .badStatus(status) }
        return .refusedAuthorization(status)
    }

    private func isRetryableStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }

    private func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func backoff(forAttempt attempt: Int) -> UInt64 {
        UInt64(min(2.0, 0.25 * pow(2.0, Double(max(0, attempt - 1)))) * 1_000_000_000)
    }

    private func retryAfterNanoseconds(_ response: HTTPURLResponse) -> UInt64? {
        guard let value = header(response, "Retry-After"),
              let seconds = Double(value), seconds >= 0 else { return nil }
        return UInt64(min(seconds, 5) * 1_000_000_000)
    }
}

extension ConfigurationFailureClassifier {
     
     
     
     
     
     
     
     
     
    static func readable(
        _ failure: RemoteResourcePlan.Failure,
        locale: Locale = .current
    ) -> String {
        let field = failure.field
         
         
         
         
         
         
        if field.hasSuffix(".url") {
             
             
             
             
            let parts = field.split(separator: ".").map(String.init)
            let provider = parts.count >= 3 ? parts[1] : (parts.first ?? field)
            return ClashCopy.format(
                "“%@” has no profile URL yet — this profile is a template, and that line still holds placeholder text. Open it and paste your own profile URL.",
                locale: locale,
                provider
            )
        }
        return "\(field): \(failure.reason)"
    }
}
