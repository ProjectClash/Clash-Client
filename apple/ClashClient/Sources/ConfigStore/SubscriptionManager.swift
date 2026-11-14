import Foundation
import ClashClientKit

struct FetchedConfig {
    let yaml: String
     
     
    let rawSource: Data
    let etag: String?
    let lastModified: String?
    let subscriptionInfo: SubscriptionInfo?
     
     
     
    var suggestedName: String? = nil

    init(
        yaml: String,
        rawSource: Data? = nil,
        etag: String?,
        lastModified: String?,
        subscriptionInfo: SubscriptionInfo?,
        suggestedName: String? = nil
    ) {
        self.yaml = yaml
        self.rawSource = rawSource ?? Data(yaml.utf8)
        self.etag = etag
        self.lastModified = lastModified
        self.subscriptionInfo = subscriptionInfo
        self.suggestedName = suggestedName
    }
}

 
 
 
 
final class SubscriptionManager {
     
    static let maxConfigBytes = Int.max

    private let downloader: HTTPFetching
    private let credentials: CredentialStore
    private let userAgent: () -> String

    init(downloader: HTTPFetching, credentials: CredentialStore,
         userAgent: @escaping () -> String = { ClientUserAgent.resolved() }) {
        self.downloader = downloader
        self.credentials = credentials
        self.userAgent = userAgent
    }

    func fetch(
        profile: Profile,
        etag: String? = nil,
        lastModified: String? = nil,
        useConditionalValidators: Bool = true,
        nodesOnly: Bool = false,
         
         
         
        unreadBody: ((Data) -> Void)? = nil
    ) async throws -> FetchedConfig? {
        guard case .url(let urlString) = profile.source else {
            throw SubscriptionError.notARemoteSource
        }
        guard var components = URLComponents(string: urlString),
              components.scheme != nil,
              components.host != nil else {
            throw SubscriptionError.badURL
        }
         
         
         
         
         
         
        let link = components.url
        components.user = nil
        components.password = nil
        guard let url = components.url else { throw SubscriptionError.badURL }
        var request = URLRequest(url: url)
         
         
        request.setValue(
            ClientUserAgent.explicitValue(for: profile) ?? userAgent(),
            forHTTPHeaderField: "User-Agent"
        )
         
         
         
         
         
         
         
         
        let labelStillAuto = !ProfileLabelPolicy.isUserAssigned(profile)
         
         
         
         
         
         
        for (field, value) in Self.conditionalHeaders(
            profile: profile,
            etag: etag,
            lastModified: lastModified,
            useConditionalValidators: useConditionalValidators,
            labelStillAuto: labelStillAuto
        ) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        var saved: String?
        if let token = credentials.get("sub.token.\(profile.id)"),
           let tokenString = String(data: token, encoding: .utf8) {
            saved = "Bearer \(tokenString)"
            request.setValue(saved, forHTTPHeaderField: "Authorization")
        } else if let basic = link.flatMap(ProviderMaterializer.basicAuthorization(from:)) {
            request.setValue(basic, forHTTPHeaderField: "Authorization")
        }
         
         
        let sent = RefusedCredential.of(request, link: link, saved: saved)
        let result: DownloadResult
        do {
            result = try await fetch(request, sent: sent)
        } catch DownloadError.badStatus(let status)
            where (300...399).contains(status)
                && request.value(forHTTPHeaderField: "User-Agent")
                    != ClientUserAgent.Preset.flclash.value {
             
             
             
            var compatibilityRequest = request
            compatibilityRequest.setValue(
                ClientUserAgent.Preset.flclash.value,
                forHTTPHeaderField: "User-Agent"
            )
            result = try await fetch(compatibilityRequest, sent: sent)
        }
        if result.notModified { return nil }
        let yaml: String
        do {
            yaml = try ProxyImportBridge.derivedSubscriptionYAML(from: result.data, nodesOnly: nodesOnly)
        } catch {
            unreadBody?(result.data)
            throw error
        }
        return FetchedConfig(yaml: yaml, rawSource: result.data, etag: result.etag,
                             lastModified: result.lastModified,
                             subscriptionInfo: result.subscriptionUserInfo.flatMap(SubscriptionInfo.parse(header:)),
                             suggestedName: Self.suggestedName(
                                fromContentDisposition: result.contentDisposition
                             ))
    }

     
     
     
    static func suggestedName(fromContentDisposition header: String?) -> String? {
         
         
         
         
        PanelName.suggested(fromContentDisposition: header)
    }

     
     
    private func fetch(_ request: URLRequest, sent: RefusedCredential) async throws -> DownloadResult {
        do {
            return try await downloader.fetch(
                request,
                maxBytes: Self.maxConfigBytes,
                redirectPolicy: .followAcrossOrigins(maxHops: 5)
            )
        } catch {
            throw DownloadError.refusingALink(error, sent: sent)
        }
    }
}

enum SubscriptionSourceRefreshResult: Equatable {
    case updated
    case unchanged
}

 
 
 
 
enum SubscriptionSourceRefresher {
     
     
    nonisolated(unsafe) static var beforeSourceWrite: (() throws -> Void)?

     
     
     
     
     
     
     
     
     
     
    static func refresh(
        profile given: Profile,
        manager: SubscriptionManager,
        profileStore: ProfileStore,
        credentials: CredentialStore,
        workingDirectory: URL,
        now: Date = Date(),
        expecting expected: ProfileSourceIdentity? = nil,
        conditional: Bool = true,
        scripts caller: ScriptEngine.Caller = .surfaced
    ) async throws -> SubscriptionSourceRefreshResult {
         
         
         
         
        let profile = profileStore.load().first(where: { $0.id == given.id }) ?? given
        let identity = ProfileSourceIdentity(profile, workingDirectory: workingDirectory)
        if let expected, expected != identity { return .unchanged }
        func sourceIsAsItWas(_ current: Profile) -> Bool {
            ProfileSourceIdentity(current, workingDirectory: workingDirectory) == identity
        }
         
         
         
         
         
         
         
         
        let sourceURL = workingDirectory
            .appendingPathComponent("store/\(profile.id)/source.yaml")
         
         
         
         
         
         
        let hasLocalSource = Self.hasUsableSource(at: sourceURL)
         
         
         
         
         
         
         
         
         
        guard let fetched = try await manager.fetch(
            profile: profile,
            useConditionalValidators: conditional && hasLocalSource
        ) else {
             
             
             
             
             
             
             
             
             
            try profileStore.updateIfPresent(id: profile.id, when: sourceIsAsItWas) { current in
                current.lastUpdatedAt = now
                current.labelIsUserAssigned = ProfileLabelPolicy.isUserAssigned(current)
            }
            return .unchanged
        }

        try Task.checkCancellation()
        try ConfigTransforms.validateSource(fetched.yaml)
         
         
         
         
         
         
        _ = try ProfileRuntimeConfigBuilder.runtimePreview(
            raw: fetched.yaml,
            profile: profile, scripts: caller
        )

         
         
         
         
         
         
        let sidecar = ProfileSourceStore.runnableURL(
            workingDirectory: workingDirectory, profileID: profile.id
        )
        let previousSource = try? String(contentsOf: sidecar, encoding: .utf8)
         
         
         
         
         
         
         
         
         
         
        if profile.usesLocalSourceOverride != true, let previousSource, previousSource == fetched.yaml {
            try profileStore.updateIfPresent(id: profile.id, when: sourceIsAsItWas) { current in
                current.lastUpdatedAt = now
                current.labelIsUserAssigned = ProfileLabelPolicy.isUserAssigned(current)
                current.subscriptionInfo = fetched.subscriptionInfo ?? current.subscriptionInfo
                current.subscriptionETag = fetched.etag ?? current.subscriptionETag
                current.subscriptionLastModified = fetched.lastModified ?? current.subscriptionLastModified
            }
            return .unchanged
        }
        let heldBack = SubscriptionUpdateSuppression.suppressed(
            previousYAML: previousSource,
            newYAML: fetched.yaml,
             
             
            appPatchJSON: OverridePatch(patchJSON: FlClashRuntimeConfig.load().patchJSON)
                .overlaying(OverridePatch(patchJSON: profile.legacyRuntimePatchJSON ?? "")).patchJSON
        )
        let suppressed = heldBack.isEmpty ? nil : heldBack
         
         
         
         
         
         
        let staged = try ProfileSourceStore.stage(
            document: fetched.yaml, derivedFrom: fetched.rawSource,
            workingDirectory: workingDirectory, profileID: profile.id
        )
        var replaced: ProfileSourceStore.Replaced?
        defer {
            if let replaced { ProfileSourceStore.retire(replaced) } else { ProfileSourceStore.discard(staged) }
        }
        let legacyCredentials: [ProxyCredentialReference]? = try ProfileStore.withWriteLock {
             
             
             
             
            let profiles = profileStore.load()
            guard let asItWas = profiles.first(where: { $0.id == profile.id }),
                  sourceIsAsItWas(asItWas) else { return nil }
            let otherLabels = profiles.filter { $0.id != profile.id }.map(\.label)
            do {
                 
                 
                 
                try profileStore.updateIfPresent(id: profile.id) { current in
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    current.proxyCredentials = nil
                    current.sourceCredentials = nil
                    current.sourceCredentialsRedacted = false
                    current.usesLocalSourceOverride = false
                    current.subscriptionInfo = fetched.subscriptionInfo ?? current.subscriptionInfo
                     
                     
                     
                     
                     
                     
                     
                     
                    let named = current
                    ProfileLabelPolicy.adoptPanelName(fetched.suggestedName, into: &current, for: named,
                                                      otherLabels: otherLabels)
                    current.subscriptionETag = fetched.etag ?? current.subscriptionETag
                    current.subscriptionLastModified = fetched.lastModified ?? current.subscriptionLastModified
                    current.lastUpdatedAt = now
                    current.suppressedUpdates = suppressed
                }
                 
                 
                 
                 
                try beforeSourceWrite?()
                replaced = try ProfileSourceStore.swapIn(staged)
            } catch {
                 
                 
                try? profileStore.updateIfPresent(id: profile.id) { $0 = asItWas }
                throw error
            }
            return (asItWas.proxyCredentials ?? []) + (asItWas.sourceCredentials ?? [])
        }
        guard let legacyCredentials else { return .unchanged }

         
         
         
         
        try? ProxyCredentialVault.remove(legacyCredentials, store: credentials)
        return .updated
    }
}


extension SubscriptionManager {
     
     
     
     
     
     
     
     
    static func conditionalHeaders(
        profile: Profile,
        etag: String? = nil,
        lastModified: String? = nil,
        useConditionalValidators: Bool,
        labelStillAuto: Bool = false
    ) -> [String: String] {
        let showingLocalEdit = profile.usesLocalSourceOverride == true
        guard useConditionalValidators, !labelStillAuto, !showingLocalEdit else {
            return [:]
        }
        var headers: [String: String] = [:]
        if let etag = etag ?? profile.subscriptionETag {
            headers["If-None-Match"] = etag
        }
        if let lastModified = lastModified ?? profile.subscriptionLastModified {
            headers["If-Modified-Since"] = lastModified
        }
        return headers
    }
}


extension SubscriptionSourceRefresher {
     
    static func hasUsableSource(at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
