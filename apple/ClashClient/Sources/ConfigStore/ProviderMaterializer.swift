import Foundation
import CryptoKit
import Clash
import struct ClashClientKit.ConfigurationCollection
import struct ClashClientKit.ProviderRefreshState
import enum ClashClientKit.AuthoredText

enum MaterializeError: Error, Equatable {
    case badURL(provider: String)
    case ageKeyMissing(provider: String)
     
     
    case ageDecryptFailed(provider: String, detail: String? = nil)
    case unsafePath(provider: String)
    case unsafeHeader(provider: String)

     
    var provider: String {
        switch self {
        case .badURL(let provider), .ageKeyMissing(let provider), .ageDecryptFailed(let provider, _),
             .unsafePath(let provider), .unsafeHeader(let provider):
            return provider
        }
    }

     
     
     
    var providerRowText: AuthoredText? {
        switch self {
        case .ageKeyMissing: return .app(Self.sealedWithoutKeyReason)
        case .ageDecryptFailed(_, let detail):
             
            return detail.map { .app(Self.undecryptableFormat, arguments: [$0]) } ?? .app(Self.undecryptableReason)
        case .unsafeHeader: return .app(Self.unsafeHeaderReason)
        case .badURL, .unsafePath: return nil
        }
    }

    static let sealedWithoutKeyReason = "this provider is encrypted and the configuration has no key for it"
    static let undecryptableReason = "this provider could not be decrypted with the configuration's key"
     
    static let undecryptableFormat = "this provider could not be decrypted with the configuration's key: %@"
    static let unsafeHeaderReason = "this provider's header cannot be sent as written"
}

 
 
 
 
 
 
 
 
struct ProviderDownloadFailure: Error, LocalizedError {
    let provider: String
    let url: String?
    let underlying: Error
     
     
    var errorDescription: String? { underlying.localizedDescription }
}

 
 
struct ProviderRequest {
    let request: URLRequest
    let sent: RefusedCredential
}

 
 
 
 
struct ProviderValidationFailure: Error, LocalizedError {
    let provider: String
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}

 
 
 
 
struct ProviderDownloadFailuresError: Error, LocalizedError {
    let failures: [ProviderDownloadFailure]
     
     
     
    var errorDescription: String? {
        failures.count == 1
            ? failures[0].underlying.localizedDescription
            : failures.map { $0.provider + ": " + $0.underlying.localizedDescription }.joined(separator: "\n")
    }
}

 
 
 
 
 
 
 
struct ProviderValidationWarning: Equatable {
     
     
    static let clientAuthoredReason = "the core could not read this rule set"

    let provider: String
     
     
     
     
     
     
     
    let note: ProviderNote
     
     
    var notedAt: Date? = nil

     
    var reason: String { note.englishText }
}

 
 
extension AuthoredText {
     
     
    static func of(_ error: Error) -> AuthoredText {
        switch error {
        case let authored as AuthoredError: return authored.text
        case let refusal as DownloadError: return refusal.authoredText
        case let refusal as MaterializeError: return refusal.providerRowText ?? .verbatim(error.localizedDescription)
        case let failure as ProviderDownloadFailure: return of(failure.underlying)
        case let failure as ProviderValidationFailure: return of(failure.underlying)
        case let batch as ProviderDownloadFailuresError where batch.failures.count == 1:
            return of(batch.failures[0].underlying)
        case let pipeline as PipelineError: return pipeline.authoredText
         
        case let refusal as ModuleRefusal: return refusal.authoredText
        case let refusal as ModuleStoreError: return refusal.authoredText
        case let refusal as ModuleInjectionError: return refusal.authoredText
        #if os(iOS) || os(macOS)
        case let certificate as ModuleCertificateError: return certificate.authoredText
        #endif
        default:
             
             
             
            if !(type(of: error) is NSError.Type),
               let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
                return .app(description)
            }
            return .verbatim(error.localizedDescription)
        }
    }
}

 
 
struct AuthoredError: LocalizedError, Equatable {
    let text: AuthoredText
    var errorDescription: String? { text.englishText }
}

 
 
 
 
enum ProviderNote: Hashable, Codable, Sendable {
     
     
    case fetchedByCore(outbound: String?)
     
    case notDownloadedYet
     
    case downloading
     
    case downloadFailed(url: String?, reason: AuthoredText)
     
     
    case held(AuthoredText)
     
     
     
     
    case checkFailed(AuthoredText)
     
     
    case failed(AuthoredText)

    var isFailure: Bool {
        switch self {
        case .downloadFailed, .failed, .checkFailed: return true
        case .fetchedByCore, .notDownloadedYet, .downloading, .held: return false
        }
    }

     
     
     
     
    var isShown: Bool {
        if case .fetchedByCore = self { return false }
        return true
    }

     
     
    var isTunnelWord: Bool {
        switch self {
        case .held, .checkFailed: return true
        case .fetchedByCore, .notDownloadedYet, .downloading, .downloadFailed, .failed: return false
        }
    }

     
    var englishText: String {
        switch self {
        case .fetchedByCore: return Self.legacyFetchedByCoreSentence
        case .notDownloadedYet: return ProviderFetchDeferred.sentence
        case .downloading: return ProviderDownloadActivity.downloadingNote
        case .downloadFailed(let url, let reason):
            return url.map { "download failed (\($0)): \(reason.englishText)" } ?? "download failed: \(reason.englishText)"
        case .failed(let text), .held(let text), .checkFailed(let text): return text.englishText
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func merging(catalog note: ProviderNote?, tunnel entry: ProviderRefreshState.Entry?,
                        line: (key: String, arguments: [String])?, catalogDate: Date?) -> ProviderNote? {
        guard let entry else { return note }
         
         
         
         
         
         
         
        var coreOnly = false
        if case .fetchedByCore? = note { coreOnly = true }
        func later(_ seconds: Int64?) -> Bool {
            if coreOnly { return true }
            guard let catalogDate else { return true }
            guard let seconds, seconds > 0 else { return false }
            return seconds >= Int64(catalogDate.timeIntervalSince1970.rounded(.down))
        }
        switch entry.result {
        case .failed?:
            guard later(entry.lastAttemptAt) else { return note }
            return .checkFailed(line.map { .app($0.key, arguments: $0.arguments) }
                ?? entry.error.map { .app("Update failed: %@", arguments: [$0]) } ?? .app("Update failed"))
        case .pendingApp?:
            guard later(entry.pendingCheckedAt ?? entry.lastAttemptAt) else { return note }
             
             
             
             
             
            guard let line else {
                if case .fetchedByCore? = note { return note }
                return nil
            }
            return .held(.app(line.key, arguments: line.arguments))
        case .updated?, .unchanged?:
            guard entry.checkedAt != nil, later(entry.lastCheckedAt) else { return note }
            if case .fetchedByCore? = note { return note }
            return nil
        case .scheduled?, nil:
            return note
        }
    }

     
     
     
    init(recorded sentence: String) {
        switch sentence {
        case ProviderFetchDeferred.sentence, ProviderFetchDeferred.sentenceUntil1012,
             ProviderFetchDeferred.previousSentence:
            self = .notDownloadedYet
        case Self.legacyFetchedByCoreSentence:
            self = .fetchedByCore(outbound: nil)
        case ProviderDownloadActivity.downloadingNote:
            self = .downloading
        case ProviderValidationWarning.clientAuthoredReason, MaterializeError.sealedWithoutKeyReason,
             MaterializeError.undecryptableReason, MaterializeError.unsafeHeaderReason:
            self = .failed(.app(sentence))
        default:
            let undecryptable = MaterializeError.undecryptableFormat.replacingOccurrences(of: "%@", with: "")
            if sentence.hasPrefix(undecryptable), sentence.count > undecryptable.count {
                self = .failed(.app(MaterializeError.undecryptableFormat,
                                    arguments: [String(sentence.dropFirst(undecryptable.count))]))
            } else if sentence.hasPrefix("download failed ("), let close = sentence.range(of: "): ") {
                let url = String(sentence[sentence.index(sentence.startIndex, offsetBy: 17)..<close.lowerBound])
                self = .downloadFailed(url: url, reason: .verbatim(String(sentence[close.upperBound...])))
            } else if sentence.hasPrefix("download failed: ") {
                self = .downloadFailed(url: nil, reason: .verbatim(String(sentence.dropFirst(17))))
            } else {
                self = .failed(.verbatim(sentence))
            }
        }
    }

     
    static let legacyFetchedByCoreSentence =
        "Fetched by Clash through the proxy it names, after the switch; the app does not download it."
}

 
enum ProviderFetchBudget: Equatable {
     
     
    case patient
     
    case quick
     
     
     
     
     
     
     
     
     
     
     
    case activation
     
     
     
     
     
     
     
     
    case connect

     
     
     
    static func forActivation(connectInFront: Bool, tunnelRunning: Bool) -> ProviderFetchBudget {
        connectInFront && !tunnelRunning ? .connect : .activation
    }
}

 
 
 
 
 
struct ProviderFetchDeferred: LocalizedError, Equatable {
    let provider: String
     
     
    static let sentence = "Not downloaded yet — downloads after you connect"
     
    static let sentenceUntil1012 = "Not downloaded yet — downloads after you connect, or tap Sync."
     
    static let previousSentence = "Not downloaded yet; Clash fetches it in the background after the switch."
    var errorDescription: String? { Self.sentence }
}

 
 
 
 
 
 
 
struct ProviderFetchedByCore: LocalizedError, Equatable {
    let provider: String
    let proxy: String
    var errorDescription: String? { ProviderNote.legacyFetchedByCoreSentence }

     
     
     
    static func applies(toProxy proxy: String) -> Bool {
        ConfigurationCollection.namesOutbound(proxy)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProviderRequestIdentity {
    static func of(url: String, headers: [String: [String]]) -> String {
        var fields: [String: [String]] = [:]
        for (name, values) in headers {
            fields[name.lowercased(), default: []].append(values.joined(separator: ", "))
        }
        var lines = [url.trimmingCharacters(in: .whitespacesAndNewlines)]
        for name in fields.keys.sorted() {
            lines.append(name + ": " + (fields[name] ?? []).sorted().joined(separator: ", "))
        }
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

     
     
    static func bare(url: String) -> String {
        of(url: url, headers: [:])
    }

     
    static func of(_ provider: RemoteResourcePlan.Provider) -> String {
        of(url: provider.url, headers: provider.requestHeaders)
    }
}

struct ProviderMaterializationResult: Equatable {
    let paths: [String: String]
     
     
     
     
    var readPaths: [String: String] = [:]
    let entryCounts: [String: Int]
    let subscriptionUserInfo: [String: String]
    let refreshedNames: Set<String>
     
     
     
     
    let refreshedPayloads: [String: Data]
     
    var validationWarnings: [ProviderValidationWarning] = []
     
     
     
    var reusedCount: Int = 0
    var fetchedCount: Int = 0
     
     
    var downloadedNames: Set<String> = []
     
     
     
    var firstLoadPending: [String] = []
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    var payloadSourceURLs: [String: String] = [:]
     
     
     
    var payloadRequests: [String: String] = [:]
     
     
     
    var coreRouteSeeds: Set<String> = []
     
     
     
     
     
     
     
    var staleFallbacks: [String] = []
     
     
     
     
     
     
     
     
    var libraryCopyDates: [String: Date] = [:]
     
     
     
    var acquiredAt: [String: Date] = [:]
     
     
     
    var seedPaths: [String: String] = [:]
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ProviderDownloadRound: @unchecked Sendable {
    enum Answer {
        case fetched(data: Data, subscriptionUserInfo: String?)
        case failed(Error)
    }

    private struct Recorded {
        let answer: Answer
        let at: Date
        let limit: Int
    }

    private let lock = NSLock()
    private var answers: [URLRequest: Recorded] = [:]

    init() {}

     
     
     
    func answer(for request: URLRequest, limit: Int) -> (answer: Answer, at: Date)? {
        lock.lock(); defer { lock.unlock() }
        guard let recorded = answers[request] else { return nil }
        if case .failed(let error) = recorded.answer, Self.cutOffAtTheLimit(error), limit > recorded.limit { return nil }
        return (recorded.answer, recorded.at)
    }

     
    func record(_ answer: Answer, for request: URLRequest, limit: Int, at: Date = Date()) {
        if case .failed(let error) = answer,
           error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        lock.lock(); answers[request] = Recorded(answer: answer, at: at, limit: limit); lock.unlock()
    }

     
     
     
     
     
     
    func forgetBodies() {
        lock.lock(); defer { lock.unlock() }
        answers = answers.filter { if case .failed = $0.value.answer { return true }; return false }
    }

     
    var bodiesHeld: Int {
        lock.lock(); defer { lock.unlock() }
        return answers.values.filter { if case .fetched = $0.answer { return true }; return false }.count
    }

    private static func cutOffAtTheLimit(_ error: Error) -> Bool {
        if case .tooLarge? = error as? DownloadError { return true }
        return false
    }
}

 
 
 
 
 
 
 
 
final class ProviderMaterializer {
    static let ageArmorPrefix = "-----BEGIN AGE ENCRYPTED FILE-----"

    typealias AgeDecryptor = (_ payload: Data, _ key: String, _ provider: String) throws -> Data

    private static let writeOptions: Data.WritingOptions =
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

     
     
     
     
    static func write(
        _ data: Data, to target: URL, reusedFrom source: URL?, payloadStore: ProviderPayloadStore?
    ) throws {
        if let payloadStore {
            if let source, (try? ProviderPayloadStore.link(source, to: target)) != nil {
                return
            }
            try payloadStore.place(data, at: target)
            return
        }
         
         
         
        if let source, (try? FileManager.default.copyItem(at: source, to: target)) != nil {
            return
        }
        try data.write(to: target, options: writeOptions)
    }

    private let downloader: HTTPFetching
     
     
     
    private let quickDownloader: HTTPFetching
     
     
    private let connectDownloader: HTTPFetching
    private let credentials: CredentialStore
    private let decryptor: AgeDecryptor

    init(downloader: HTTPFetching, credentials: CredentialStore,
         quickDownloader: HTTPFetching? = nil,
         connectDownloader: HTTPFetching? = nil,
         decryptor: @escaping AgeDecryptor = { payload, key, provider in
              
              
              
              
              
              
             var error: NSError?
             guard let decrypted = AppCore.decryptAge(payload, key, &error) else {
                 throw MaterializeError.ageDecryptFailed(provider: provider, detail: error?.localizedDescription)
             }
             return decrypted
         }) {
        self.downloader = downloader
        self.quickDownloader = quickDownloader
            ?? (downloader is ResourceDownloader ? ResourceDownloader.quick() : downloader)
        self.connectDownloader = connectDownloader
            ?? (downloader is ResourceDownloader ? ResourceDownloader.connect() : downloader)
        self.credentials = credentials
        self.decryptor = decryptor
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func slimmedForRuntime(kind: String, payload: Data) -> Data {
        guard kind == "proxy" else { return payload }
         
         
         
         
         
         
         
         
        if payload.starts(with: Data(#"{"proxies":"#.utf8)) {
            guard let object = try? JSONSerialization.jsonObject(
                      with: payload
                  ) as? [String: Any],
                  let proxies = object["proxies"] as? [Any], !proxies.isEmpty,
                  let slim = try? JSONSerialization.data(
                      withJSONObject: ["proxies": proxies],
                      options: [.withoutEscapingSlashes, .sortedKeys]
                  )
            else { return payload }
            return slim
        }
        guard let text = String(data: payload, encoding: .utf8),
              let json = try? ConfigTransforms.yamlToJSON(text),
              let object = try? JSONSerialization.jsonObject(
                  with: Data(json.utf8)
              ) as? [String: Any],
              let proxies = object["proxies"] as? [Any],
              !proxies.isEmpty,
               
               
               
               
               
               
               
               
              let slim = try? JSONSerialization.data(
                  withJSONObject: ["proxies": proxies],
                  options: [.withoutEscapingSlashes, .sortedKeys]
              )
        else { return payload }
        return slim
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static func bytesOnDiskStillAnswerFor(
        _ provider: RemoteResourcePlan.Provider,
        record: ProviderCatalog.Entry?
    ) -> Bool {
        guard let record else { return true }
         
         
         
         
         
         
        guard let recorded = record.payloadURL else { return false }
         
         
         
         
         
         
         
         
         
         
         
         
         
        return recorded == provider.url && answers(record, requestOf: provider)
    }

     
     
     
     
    private static func record(_ record: ProviderCatalog.Entry?,
                               namesAnotherRequestThan provider: RemoteResourcePlan.Provider) -> Bool {
        guard let record, let address = record.payloadURL else { return false }
        if address != provider.url { return true }
        guard let request = record.payloadRequest else { return false }
        return request != ProviderRequestIdentity.of(provider)
    }

     
     
     
     
     
     
     
     
    private static func answers(_ record: ProviderCatalog.Entry, requestOf provider: RemoteResourcePlan.Provider) -> Bool {
        let answered = record.payloadRequest
            ?? ProviderRequestIdentity.bare(url: record.payloadURL ?? record.url)
        return answered == ProviderRequestIdentity.of(provider)
    }

     
     
     
     
     
     
    static func failureText(of note: ProviderNote) -> AuthoredText {
        switch note {
        case .failed(let text), .checkFailed(let text): return text
        case .downloadFailed(_, let reason): return reason
        case .fetchedByCore, .notDownloadedYet, .downloading, .held:
            return .app(ProviderValidationWarning.clientAuthoredReason)
        }
    }

    static func isOwed(_ record: ProviderCatalog.Entry) -> Bool {
        record.lastUpdatedAt == nil && record.note != nil
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func received(_ record: ProviderCatalog.Entry) -> Date? {
        record.acquiredAt ?? record.lastUpdatedAt
    }

     
     
     
     
    func materialize(plan: RemoteResourcePlan, into providersDir: URL,
                     publishedProvidersDir: URL,
                     maxBytesEach: Int,
                     reuseDir: URL? = nil,
                     reuseDirIsOwnRevision: Bool = true,
                     forceRefresh: Set<String> = [],
                     ageSecretKeys: [String: String] = [:],
                     userAgent: String? = nil,
                     payloadStore: ProviderPayloadStore? = nil) async throws -> [String: String] {
        try await materializeDetailed(
            plan: plan,
            into: providersDir,
            publishedProvidersDir: publishedProvidersDir,
            maxBytesEach: maxBytesEach,
            reuseDir: reuseDir,
            reuseDirIsOwnRevision: reuseDirIsOwnRevision,
            forceRefresh: forceRefresh,
            ageSecretKeys: ageSecretKeys,
            userAgent: userAgent,
            payloadStore: payloadStore
        ).paths
    }

     
     
     
    func materializeDetailed(
        plan: RemoteResourcePlan,
        into providersDir: URL,
        publishedProvidersDir: URL,
        maxBytesEach: Int,
        reuseDir: URL? = nil,
         
         
         
         
         
         
         
         
         
         
        reuseDirIsOwnRevision: Bool = true,
        forceRefresh: Set<String> = [],
         
         
         
         
         
         
        ageSecretKeys: [String: String] = [:],
        localOverrides: [String: Data] = [:],
        cachedNodeFiles: [String: URL] = [:],
         
         
         
         
         
         
        cachedRuleFiles: [String: URL] = [:],
        captureRefreshedPayloads: Set<String> = [],
        userAgent: String? = nil,
         
         
         
        routeSetProviders: Set<String> = [],
        coreRouteSnapshots: [String: Data] = [:],
         
        coreRouteDates: [String: Date] = [:],
        reusedCoreFilePaths: Set<String> = [],
         
         
        fetchOnly: Set<String>? = nil,
        fetchBudget: ProviderFetchBudget = .patient,
         
         
         
         
        payloadStore: ProviderPayloadStore? = nil,
         
         
        downloadRound: ProviderDownloadRound? = nil
    ) async throws -> ProviderMaterializationResult {
        var mapping: [String: String] = [:]
        var readPaths: [String: String] = [:]
        var entryCounts: [String: Int] = [:]
        var subscriptionUserInfo: [String: String] = [:]
         
         
         
        let isRouteSet: (RemoteResourcePlan.Provider) -> Bool = {
            $0.kind == "rule" && $0.behavior.lowercased() == "ipcidr"
                && routeSetProviders.contains($0.name)
        }
        var refreshedNames: Set<String> = []
        var refreshedPayloads: [String: Data] = [:]
        var validationWarnings: [ProviderValidationWarning] = []
        var reusedCount = 0
        var fetchedCount = 0
        var downloadedNames: Set<String> = []
        var payloadSourceURLs: [String: String] = [:]
        var payloadRequests: [String: String] = [:]
        var staleFallbackNames: [String] = []
        var libraryCopyDates: [String: Date] = [:]
        var acquiredAt: [String: Date] = [:]
        var coreRouteSeeds: Set<String> = []
        var seedPaths: [String: String] = [:]
        guard !plan.providers.isEmpty else {
            return ProviderMaterializationResult(
                paths: mapping,
                entryCounts: entryCounts,
                subscriptionUserInfo: subscriptionUserInfo,
                refreshedNames: refreshedNames,
                refreshedPayloads: refreshedPayloads
            )
        }
        try FileManager.default.createDirectory(at: providersDir, withIntermediateDirectories: true)
        var downloadFailures: [ProviderDownloadFailure] = []
         
        func libraryCopy(_ provider: RemoteResourcePlan.Provider) -> URL? {
            switch provider.kind {
            case "proxy": return cachedNodeFiles[provider.name]
            case "rule": return cachedRuleFiles[provider.name]
            default: return nil
            }
        }

         
        let reusableCatalog = reuseDir
            .flatMap { ProviderCatalog.load(providersDir: $0) }
        let knownVerdicts: [String: ProviderCatalog.Entry] = reusableCatalog
            .map { catalog in
                Dictionary(catalog.entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            } ?? [:]
         
         
         
         
         
         
         
        let recordFor: [String: ProviderCatalog.Entry] = reusableCatalog
            .map { catalog in
                Dictionary(catalog.entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            } ?? [:]
         
         
         
         
         
        let owedSince: Date? = reuseDir.flatMap { directory in
            let manifest = directory.deletingLastPathComponent().appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: manifest),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let milliseconds = (object["createdAtUnixMilliseconds"] as? NSNumber)?.doubleValue {
                return Date(timeIntervalSince1970: milliseconds / 1_000)
            }
            return (try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(ProviderCatalog.fileName).path)[.modificationDate]) as? Date
        }

         
         
         
        var requests: [Int: ProviderRequest] = [:]
        var onHand: [Int: AcquiredPayload] = [:]
         
         
        var keptBytes: [Int: AcquiredPayload] = [:]
        for (index, provider) in plan.providers.enumerated() {
            guard !provider.path.isEmpty,
                  provider.path != ".",
                  provider.path != "..",
                  URL(fileURLWithPath: provider.path).lastPathComponent == provider.path,
                  !provider.path.contains("/") && !provider.path.contains("\\") else {
                throw MaterializeError.unsafePath(provider: provider.name)
            }
            guard let url = URL(string: provider.url) else {
                throw MaterializeError.badURL(provider: provider.name)
            }
             
             
             
             
             
            if let local = localOverrides[provider.name] {
                guard local.count <= maxBytesEach else {
                    throw DownloadError.tooLarge(local.count)
                }
                onHand[index] = AcquiredPayload(
                    data: local, refreshed: true, subscriptionUserInfo: nil, failure: nil, acquiredAt: Date())
                continue
            }
             
             
            let libraryFile = libraryCopy(provider)
            let libraryDate = libraryFile.flatMap {
                (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date
            }
            let cachedFile: URL? = libraryFile.map { libraryFile in
                guard let reuseDir, let record = recordFor[provider.path] else { return libraryFile }
                let previous = reuseDir.appendingPathComponent(provider.path)
                 
                 
                 
                 
                 
                 
                 
                 
                if provider.kind == "rule", provider.updateIntervalSeconds <= 0, Self.isOwed(record),
                   (libraryDate ?? .distantPast).timeIntervalSince(owedSince ?? .distantPast) <= 0 {
                    return previous
                }
                 
                 
                 
                if provider.kind == "rule", record.payloadURL == nil {
                    return (Self.received(record) ?? .distantPast).timeIntervalSince(libraryDate ?? .distantPast) >= 0 ? previous : libraryFile
                }
                guard record.payloadURL == provider.url, Self.answers(record, requestOf: provider) else { return libraryFile }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                return (Self.received(record) ?? .distantPast).timeIntervalSince(libraryDate ?? .distantPast) >= 0 ? previous : libraryFile
            }
             
             
             
             
             
             
             
            if provider.kind == "proxy" || (provider.kind == "rule" && cachedFile != nil && cachedFile == libraryFile),
               !forceRefresh.contains(provider.name),
               !ProviderFetchedByCore.applies(toProxy: provider.proxy),
               let file = cachedFile,
               let bytes = try? Data(contentsOf: file, options: .mappedIfSafe),
               bytes.count <= maxBytesEach,
               provider.maximumBytes <= 0 || bytes.count <= Int(clamping: provider.maximumBytes) {
                var count = 0
                var error: NSError?
                if AppCore.inspectProvider(provider.kind, provider.behavior, provider.format, bytes, &count, &error) {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    let takesLibraryCopy = file == libraryFile
                    if takesLibraryCopy { libraryCopyDates[provider.name] = libraryDate }
                    onHand[index] = AcquiredPayload(data: bytes, reusedFrom: file,
                        refreshed: fetchOnly?.contains(provider.name) == true || takesLibraryCopy,
                        subscriptionUserInfo: nil, failure: nil,
                        acquiredAt: file == libraryFile ? libraryDate : nil)
                    continue
                }
            }
            if ProviderFetchedByCore.applies(toProxy: provider.proxy) {
                 
                 
                if reusedCoreFilePaths.contains(provider.path), let reuseDir {
                    let source = reuseDir.appendingPathComponent(provider.path)
                    if let bytes = try? Data(contentsOf: source), bytes.count <= maxBytesEach {
                        onHand[index] = AcquiredPayload(data: bytes, reusedFrom: source,
                            refreshed: false, subscriptionUserInfo: nil, failure: nil)
                        continue
                    }
                }
                 
                 
                onHand[index] = AcquiredPayload(
                    data: nil, refreshed: false, subscriptionUserInfo: nil,
                    failure: ProviderDownloadFailure(
                        provider: provider.name, url: provider.url,
                        underlying: ProviderFetchedByCore(provider: provider.name, proxy: provider.proxy)
                    )
                )
                continue
            }
             
             
             
            if let seed = reusableCatalog?.seedPaths?[provider.name].map({ URL(fileURLWithPath: $0) }),
               !forceRefresh.contains(provider.name),
               Self.bytesOnDiskStillAnswerFor(provider, record: recordFor[provider.path]),
               let bytes = try? Data(contentsOf: seed, options: .mappedIfSafe) {
                onHand[index] = AcquiredPayload(
                    data: bytes, reusedFrom: seed, refreshed: false, subscriptionUserInfo: nil, failure: nil)
                continue
            }
            if let reuseDir, !forceRefresh.contains(provider.name) {
                let source = reuseDir.appendingPathComponent(provider.path)
                guard Self.bytesOnDiskStillAnswerFor(
                    provider, record: recordFor[provider.path]
                ) else {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if reuseDirIsOwnRevision,
                       !Self.record(recordFor[provider.path], namesAnotherRequestThan: provider),
                       let kept = try? Data(contentsOf: source),
                       kept.count <= maxBytesEach
                    {
                        keptBytes[index] = AcquiredPayload(
                            data: kept, reusedFrom: source, refreshed: false,
                            subscriptionUserInfo: nil, failure: nil)
                    }
                    requests[index] = try request(for: provider, at: url, userAgent: userAgent)
                    continue
                }
                if let reused = try? Data(contentsOf: source), reused.count <= maxBytesEach {
                     
                    onHand[index] = AcquiredPayload(
                        data: reused, reusedFrom: source, refreshed: false,
                        subscriptionUserInfo: nil, failure: nil)
                    continue
                }
            }
            requests[index] = try request(for: provider, at: url, userAgent: userAgent)
        }

         
         
         
         
         
         
        var revisionDownloads: [Int: (date: Date, file: URL)] = [:]
        if downloadRound != nil, let reuseDir, reuseDirIsOwnRevision {
            for index in requests.keys {
                let provider = plan.providers[index]
                 
                 
                 
                 
                guard let record = recordFor[provider.path], record.payloadURL == provider.url,
                      record.payloadRequest == ProviderRequestIdentity.of(provider),
                      record.note == nil, let date = record.acquiredAt else { continue }
                 
                 
                 
                let file = reusableCatalog?.seedPaths?[provider.name].map { URL(fileURLWithPath: $0) }
                    ?? reuseDir.appendingPathComponent(provider.path)
                revisionDownloads[index] = (date, file)
            }
        }

         
         
         
         
         
        let payloads = try await acquirePayloads(
            plan: plan,
            requests: requests,
            onHand: onHand,
            maxBytesEach: maxBytesEach,
            budget: fetchBudget,
            fetchOnly: fetchOnly,
            round: downloadRound,
            revisionDownloads: revisionDownloads,
            seeds: payloadStore.map { ProviderSeeds.directory(payloadStore: $0) }
        )
        var firstLoadPendingNames: [String] = []

         
         
         
        for (index, provider) in plan.providers.enumerated() {
            guard var acquired = payloads[index] else { continue }
            var fellBack = false
            if acquired.failure != nil, let kept = keptBytes[index] {
                fellBack = true
                 
                 
                 
                 
                acquired = kept
            }
            if let failure = acquired.failure, failure.underlying is ProviderFetchedByCore {
                 
                 
                 
                 
                if isRouteSet(provider), let bytes = coreRouteSnapshots[provider.name] {
                    var count = 0
                    var error: NSError?
                    if AppCore.inspectProvider(provider.kind, provider.behavior, provider.format,
                                                bytes, &count, &error) {
                        let target = providersDir.appendingPathComponent(provider.path)
                        try Self.write(bytes, to: target, reusedFrom: nil, payloadStore: payloadStore)
                        readPaths[provider.name] = target.path
                         
                         
                         
                         
                         
                        mapping[provider.name] = publishedProvidersDir.appendingPathComponent(provider.path).path
                        coreRouteSeeds.insert(provider.name)
                        entryCounts[provider.name] = count
                        payloadSourceURLs[provider.path] = provider.url
                        payloadRequests[provider.path] = ProviderRequestIdentity.of(provider)
                        let previous = reuseDir.flatMap { try? Data(contentsOf: $0.appendingPathComponent(provider.path)) }
                        if previous != bytes { refreshedNames.insert(provider.name) }
                         
                         
                         
                         
                        if let date = coreRouteDates[provider.name] { acquiredAt[provider.path] = date }
                        reusedCount += 1
                        continue
                    }
                }
                if isRouteSet(provider) { firstLoadPendingNames.append(provider.name) }
                validationWarnings.append(ProviderValidationWarning(
                    provider: provider.name,
                    note: .fetchedByCore(outbound: (failure.underlying as? ProviderFetchedByCore)?.proxy)
                ))
                continue
            }
            if let failure = acquired.failure, failure.underlying is ProviderFetchDeferred {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                let previous = recordFor[provider.path]
                let carried = previous.flatMap { record -> ProviderNote? in
                    guard Self.isOwed(record), record.url == provider.url,
                          record.requestFingerprint.map({ $0 == ProviderCatalog.requestFingerprint(of: provider) }) ?? true,
                          let note = record.note, note != .notDownloadedYet
                    else { return nil }
                    return note
                }
                validationWarnings.append(ProviderValidationWarning(
                    provider: provider.name,
                    note: carried ?? .notDownloadedYet,
                    notedAt: carried == nil ? nil : previous?.notedAt
                ))
                firstLoadPendingNames.append(provider.name)
                continue
            }
            if let failure = acquired.failure {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if provider.kind == "proxy", let fetchOnly, fetchOnly.contains(provider.name),
                   !forceRefresh.contains(provider.name) {
                    validationWarnings.append(ProviderValidationWarning(
                        provider: provider.name,
                        note: .downloadFailed(url: failure.url, reason: .of(failure.underlying))
                    ))
                    firstLoadPendingNames.append(provider.name)
                    continue
                }
                guard provider.kind == "rule",
                      !forceRefresh.contains(provider.name)
                else {
                    downloadFailures.append(failure)
                    continue
                }
                validationWarnings.append(ProviderValidationWarning(
                    provider: provider.name,
                    note: failure.underlying is ProviderFetchDeferred
                        ? .notDownloadedYet
                        : .downloadFailed(url: failure.url, reason: .of(failure.underlying))
                ))
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                firstLoadPendingNames.append(provider.name)
                continue
            }
            guard let payload = acquired.data else { continue }
             
             
             
             
            if provider.kind == "rule", payload.isEmpty, let reusedFrom = acquired.reusedFrom,
               reusedFrom != libraryCopy(provider),
               let record = recordFor[provider.path], Self.isOwed(record) {
                validationWarnings.append(ProviderValidationWarning(provider: provider.name,
                    note: record.note ?? .notDownloadedYet, notedAt: record.note == nil ? nil : record.notedAt))
                firstLoadPendingNames.append(provider.name)
                continue
            }
            if acquired.reusedFrom != nil {
                reusedCount += 1
                 
                 
                 
                 
                 
                 
                 
                 
                if let reusedFrom = acquired.reusedFrom, reusedFrom == libraryCopy(provider) {
                    payloadSourceURLs[provider.path] = provider.url
                    payloadRequests[provider.path] = ProviderRequestIdentity.of(provider)
                } else if let known = recordFor[provider.path]?.payloadURL {
                    payloadSourceURLs[provider.path] = known
                    payloadRequests[provider.path] = recordFor[provider.path]?.payloadRequest
                }
                if fellBack { staleFallbackNames.append(provider.name) }
                 
                 
                 
                 
                 
                 
                if acquired.reusedFrom != libraryCopy(provider),
                   let record = recordFor[provider.path], Self.isOwed(record) {
                    firstLoadPendingNames.append(provider.name)
                }
            } else {
                 
                 
                if !acquired.answeredByRound { fetchedCount += 1 }
                payloadSourceURLs[provider.path] = provider.url
                payloadRequests[provider.path] = ProviderRequestIdentity.of(provider)
                if localOverrides[provider.name] == nil { downloadedNames.insert(provider.name) }
            }
            if acquired.refreshed {
                refreshedNames.insert(provider.name)
            }
            if let at = acquired.acquiredAt ?? (acquired.reusedFrom != nil ? recordFor[provider.path]?.acquiredAt : nil) {
                acquiredAt[provider.path] = at
            }
            if let header = acquired.subscriptionUserInfo {
                subscriptionUserInfo[provider.name] = header
            }
            let data = Self.slimmedForRuntime(
                kind: provider.kind,
                payload: try decryptIfArmored(payload, provider: provider, ageSecretKeys: ageSecretKeys)
            )
             
             
             
             
             
             
             
             
             
            var validationError: NSError?
            var counted = 0
            var readable: Bool
             
             
            var knownNote: ProviderNote?
            var knownNotedAt: Date?
            if acquired.reusedFrom != nil,
               acquired.reusedFrom != libraryCopy(provider),
               data == acquired.data,
               let known = knownVerdicts[provider.name],
               known.url == provider.url {
                readable = known.note == nil
                counted = known.count ?? 0
                knownNote = known.note
                 
                knownNotedAt = known.notedAt
            } else {
                readable = AppCore.inspectProvider(
                    provider.kind,
                    provider.behavior,
                    provider.format,
                    data,
                    &counted,
                    &validationError
                )
            }
            if !readable {
                 
                 
                 
                 
                 
                if forceRefresh.contains(provider.name) || localOverrides[provider.name] != nil {
                    throw ProviderValidationFailure(
                        provider: provider.name,
                        underlying: validationError
                            ?? knownNote.map { AuthoredError(text: Self.failureText(of: $0)) }
                            ?? AuthoredError(text: .app(ProviderValidationWarning.clientAuthoredReason))
                    )
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                validationWarnings.append(ProviderValidationWarning(
                    provider: provider.name,
                    note: knownNote
                        ?? validationError.map { .failed(.verbatim($0.localizedDescription)) }
                        ?? .failed(.app(ProviderValidationWarning.clientAuthoredReason)),
                    notedAt: knownNote == nil ? nil : knownNotedAt
                ))
            }
            let count: Int? = readable ? counted : nil
            if data.count > ConfigResourceStore.maximumCandidateResourceBytes {
                 
                 
                 
                 
                 
                guard let payloadStore,
                      let seed = try? ProviderSeeds.place(data, in: ProviderSeeds.directory(payloadStore: payloadStore))
                else {
                    validationWarnings.append(ProviderValidationWarning(
                        provider: provider.name,
                        note: .downloadFailed(url: provider.url, reason: .of(DownloadError.tooLarge(data.count)))))
                    firstLoadPendingNames.append(provider.name)
                    continue
                }
                mapping[provider.name] = seed.path
                readPaths[provider.name] = seed.path
                seedPaths[provider.name] = seed.path
            } else {
                let target = providersDir.appendingPathComponent(provider.path)
                 
                 
                 
                 
                 
                try Self.write(
                    data, to: target,
                    reusedFrom: data == acquired.data ? acquired.reusedFrom : nil,
                    payloadStore: payloadStore
                )
                mapping[provider.name] = publishedProvidersDir
                    .appendingPathComponent(provider.path).path
                readPaths[provider.name] = target.path
            }
            entryCounts[provider.name] = count
            if captureRefreshedPayloads.contains(provider.name),
               refreshedNames.contains(provider.name) {
                refreshedPayloads[provider.name] = data
            }
        }
        if !downloadFailures.isEmpty {
            throw ProviderDownloadFailuresError(failures: downloadFailures)
        }
        return ProviderMaterializationResult(
            paths: mapping,
            readPaths: readPaths,
            entryCounts: entryCounts,
            subscriptionUserInfo: subscriptionUserInfo,
            refreshedNames: refreshedNames,
            refreshedPayloads: refreshedPayloads,
            validationWarnings: validationWarnings,
            reusedCount: reusedCount,
            fetchedCount: fetchedCount,
            downloadedNames: downloadedNames,
            firstLoadPending: firstLoadPendingNames,
            payloadSourceURLs: payloadSourceURLs,
            payloadRequests: payloadRequests,
            coreRouteSeeds: coreRouteSeeds,
            staleFallbacks: staleFallbackNames,
            libraryCopyDates: libraryCopyDates,
            acquiredAt: acquiredAt,
            seedPaths: seedPaths
        )
    }

     
     
     
     
     
     
     
     
    private func request(for provider: RemoteResourcePlan.Provider, at url: URL,
                         userAgent: String?) throws -> ProviderRequest {
        var request = URLRequest(url: Self.stripUserinfo(from: url))
        if let authorization = Self.basicAuthorization(from: url) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        try applyHeaders(provider.requestHeaders, to: &request, provider: provider.name)
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(
                userAgent ?? ClientUserAgent.resolved(),
                forHTTPHeaderField: "User-Agent"
            )
        }
        var saved: String?
        if let auth = credentials.get("provider.auth.\(provider.name)"),
           let authString = String(data: auth, encoding: .utf8) {
            request.setValue(authString, forHTTPHeaderField: "Authorization")
            saved = authString
        }
        return ProviderRequest(request: request, sent: RefusedCredential.of(request, link: url, saved: saved))
    }

     
     
    static func stripUserinfo(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user != nil || components.password != nil else {
            return url
        }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }

     
    static func basicAuthorization(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let user = components.user else { return nil }
        let pair = "\(user):\(components.password ?? "")"
        guard let encoded = pair.data(using: .utf8)?.base64EncodedString() else { return nil }
        return "Basic \(encoded)"
    }

     
    private struct AcquiredPayload {
        let data: Data?
         
         
        var reusedFrom: URL? = nil
         
         
        let refreshed: Bool
        let subscriptionUserInfo: String?
        let failure: ProviderDownloadFailure?
         
        var answeredByRound = false
         
         
        var acquiredAt: Date? = nil
    }

     
     
     
     
    nonisolated(unsafe) static var receiptClock: @Sendable (URL?) -> Date = { _ in Date() }

     
     
     
     
     
    private static let concurrentFetches = 6

     
     
     
     
     
     
     
     
    static let spoolFromBytes = 1 << 20

     
     
    final class RetainedBodies: @unchecked Sendable {
        private let lock = NSLock()
        private var held = 0
        let limit: Int
        init(limit: Int = 64 << 20) { self.limit = limit }
         
        func keep(_ bytes: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard held + bytes <= limit else { return false }
            held += bytes
            return true
        }
    }

    static func spooled(_ data: Data, seeds: URL? = nil, retained: RetainedBodies? = nil) -> Data {
        if data.count < spoolFromBytes, retained?.keep(data.count) ?? true { return data }
         
         
         
        if let seeds, data.count > ConfigResourceStore.maximumCandidateResourceBytes {
            let partial = seeds.appendingPathComponent(ProviderSeeds.partialPrefix + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: seeds, withIntermediateDirectories: true)
                try data.write(to: partial, options: [.completeFileProtectionUntilFirstUserAuthentication])
                let seed = try ProviderSeeds.place(contentsOf: partial, in: seeds)
                return try Data(contentsOf: seed, options: .alwaysMapped)
            } catch {
                try? FileManager.default.removeItem(at: partial)
            }
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-spool-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try data.write(to: file)
            return try Data(contentsOf: file, options: .alwaysMapped)
        } catch {
            return data
        }
    }
     
     
     
    private static let quickConcurrentFetches = 12

    private func acquirePayloads(
        plan: RemoteResourcePlan,
        requests: [Int: ProviderRequest],
        onHand: [Int: AcquiredPayload],
        maxBytesEach: Int,
        budget: ProviderFetchBudget = .patient,
        fetchOnly: Set<String>? = nil,
        round: ProviderDownloadRound? = nil,
        revisionDownloads: [Int: (date: Date, file: URL)] = [:],
        seeds: URL? = nil
    ) async throws -> [Int: AcquiredPayload] {
        let fetcher: HTTPFetching = switch budget {
        case .patient: downloader
        case .connect: connectDownloader
        case .quick, .activation: quickDownloader
        }
        var acquired = onHand
         
         
        @Sendable func payload(_ answer: ProviderDownloadRound.Answer, at: Date, name: String, url: String?, cap: Int,
                               sent: RefusedCredential) throws -> AcquiredPayload {
            switch answer {
            case .failed(let error):
                 
                 
                return AcquiredPayload(data: nil, refreshed: false, subscriptionUserInfo: nil,
                    failure: ProviderDownloadFailure(provider: name, url: url,
                        underlying: DownloadError.refusingALink(error, sent: sent)))
            case .fetched(let data, let subscriptionUserInfo):
                 
                 
                 
                 
                 
                 
                guard data.count <= maxBytesEach else { throw DownloadError.tooLarge(data.count) }
                 
                 
                guard data.count <= cap else {
                    return AcquiredPayload(data: nil, refreshed: false, subscriptionUserInfo: nil,
                        failure: ProviderDownloadFailure(provider: name, url: url,
                                                         underlying: DownloadError.tooLarge(data.count)))
                }
                return AcquiredPayload(data: data, refreshed: true, subscriptionUserInfo: subscriptionUserInfo,
                                       failure: nil, acquiredAt: at)
            }
        }
        var toFetch: [(index: Int, request: URLRequest, name: String, url: String?, cap: Int)] = []
        for (index, provider) in plan.providers.enumerated() {
            guard acquired[index] == nil, let request = requests[index]?.request else { continue }
             
             
             
             
             
             
             
             
             
             
             
            let cap = min(provider.maximumBytes > 0
                ? Int(clamping: provider.maximumBytes)
                : maxBytesEach, ProviderSeeds.largestBytes)
            let excludedFromRound = fetchOnly.map { !$0.contains(provider.name) } ?? false
             
             
            let deferredAtConnect = budget == .connect && provider.kind != "rule"
            if budget == .activation || excludedFromRound || deferredAtConnect {
                 
                 
                 
                acquired[index] = AcquiredPayload(
                    data: nil, refreshed: false, subscriptionUserInfo: nil,
                    failure: ProviderDownloadFailure(
                        provider: provider.name, url: provider.url,
                        underlying: ProviderFetchDeferred(provider: provider.name)
                    )
                )
                continue
            }
             
             
             
            if let (answer, at) = round?.answer(for: request, limit: cap) {
                if let newer = revisionDownloads[index], newer.date > at,
                   let bytes = try? Data(contentsOf: newer.file, options: .mappedIfSafe),
                   bytes.count <= maxBytesEach, bytes.count <= cap {
                    acquired[index] = AcquiredPayload(data: bytes, reusedFrom: newer.file, refreshed: false,
                                                      subscriptionUserInfo: nil, failure: nil, acquiredAt: newer.date)
                } else {
                    var answered = try payload(answer, at: at, name: provider.name, url: provider.url, cap: cap,
                                               sent: requests[index]?.sent ?? .other)
                    answered.answeredByRound = true
                    acquired[index] = answered
                }
                continue
            }
            toFetch.append((index, request, provider.name, provider.url, cap))
        }
        guard !toFetch.isEmpty else { return acquired }

         
         
         
         
         
         
         
         
         
         
         
         
        var leaders: [(index: Int, request: URLRequest, name: String, url: String?, cap: Int)] = []
        var leaderIndex: [URLRequest: Int] = [:]
        var followers: [Int: [(index: Int, name: String, url: String?, cap: Int)]] = [:]
        for item in toFetch {
            if let leader = leaderIndex[item.request] {
                followers[leader, default: []].append((item.index, item.name, item.url, item.cap))
            } else {
                leaderIndex[item.request] = item.index
                leaders.append(item)
            }
        }
        let leaderItems = Dictionary(uniqueKeysWithValues: leaders.map { ($0.index, $0) })
        let groupLimits = Dictionary(uniqueKeysWithValues: leaders.map { leader in
            (leader.index, ([leader.cap] + (followers[leader.index] ?? []).map(\.cap)).max() ?? leader.cap)
        })

        let retained = RetainedBodies()
        try await withThrowingTaskGroup(of: (Int, ProviderDownloadRound.Answer, Date).self) { group in
            var next = 0
            let inFlight = min(budget == .patient || budget == .connect ? Self.concurrentFetches : Self.quickConcurrentFetches,
                               leaders.count)
            func start(_ item: (index: Int, request: URLRequest, name: String, url: String?, cap: Int)) {
                let limit = groupLimits[item.index] ?? item.cap
                group.addTask { [fetcher] in
                    let answer: ProviderDownloadRound.Answer
                    do {
                         
                         
                         
                         
                         
                        let result = try await fetcher.fetch(
                            item.request,
                            maxBytes: limit,
                            redirectPolicy: .followAcrossOrigins(maxHops: 5)
                        )
                         
                         
                         
                        answer = .fetched(data: Self.spooled(result.data, seeds: seeds, retained: retained),
                                          subscriptionUserInfo: result.subscriptionUserInfo)
                    } catch {
                         
                         
                         
                         
                         
                        answer = .failed(error)
                    }
                     
                     
                    let at = Self.receiptClock(item.request.url)
                    round?.record(answer, for: item.request, limit: limit, at: at)
                    return (item.index, answer, at)
                }
            }
            while next < inFlight {
                start(leaders[next])
                next += 1
            }
            for try await (index, answer, at) in group {
                if let leader = leaderItems[index] {
                    acquired[index] = try payload(answer, at: at, name: leader.name, url: leader.url, cap: leader.cap,
                                                  sent: requests[index]?.sent ?? .other)
                }
                 
                 
                for follower in followers[index] ?? [] {
                    acquired[follower.index] = try payload(answer, at: at, name: follower.name, url: follower.url,
                                                           cap: follower.cap,
                                                           sent: requests[follower.index]?.sent ?? .other)
                }
                if next < leaders.count {
                    start(leaders[next])
                    next += 1
                }
            }
        }
        return acquired
    }

     
     
     
     
    private func decryptIfArmored(_ data: Data, provider: RemoteResourcePlan.Provider,
                                  ageSecretKeys: [String: String]) throws -> Data {
        guard data.starts(with: Data(Self.ageArmorPrefix.utf8)) else { return data }
        guard let resourceKey = provider.resourceKey,
              let key = ageSecretKeys[resourceKey], !key.isEmpty else {
            throw MaterializeError.ageKeyMissing(provider: provider.name)
        }
        return try decryptor(data, key, provider.name)
    }

    private func applyHeaders(
        _ headers: [String: [String]],
        to request: inout URLRequest,
        provider: String
    ) throws {
         
         
         
        let forbidden = Set([
            "host", "content-length", "transfer-encoding", "connection",
            "proxy-authorization", "proxy-connection", "upgrade",
        ])
        let allowedName = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        for (name, values) in headers {
            guard !name.isEmpty,
                  name.unicodeScalars.allSatisfy({ allowedName.contains($0) }),
                  !forbidden.contains(name.lowercased()),
                  !values.isEmpty,
                   
                   
                  values.allSatisfy({ !$0.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) }) else {
                throw MaterializeError.unsafeHeader(provider: provider)
            }
            request.setValue(values.joined(separator: ", "), forHTTPHeaderField: name)
        }
    }
}

 
 
 
 
 
struct CoreOwnedRouteCache {
    static let maximumBytes = 16 * 1024 * 1024  
    let runtimeYAML: String
    let snapshots: [String: Data]
    let paths: [String: String]
     
     
    let dates: [String: Date]

    init(mergedYAML: String, plan: RemoteResourcePlan, routeSetProviders: Set<String>,
         profileID: String, workingDirectory: URL) throws {
        let providers = plan.providers.filter {
            $0.kind == "rule" && $0.behavior.lowercased() == "ipcidr"
                && routeSetProviders.contains($0.name) && ProviderFetchedByCore.applies(toProxy: $0.proxy)
        }
        guard !providers.isEmpty else {
            runtimeYAML = mergedYAML; snapshots = [:]; paths = [:]; dates = [:]; return
        }
        let json = try ConfigTransforms.yamlToJSON(mergedYAML)
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
        let definitions = root["rule-providers"] as? [String: [String: Any]] ?? [:]
        let directory = workingDirectory.appendingPathComponent("tv-rule-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var paths: [String: [String: String]] = [:]
        var bytes: [String: Data] = [:]
        var written: [String: Date] = [:]
        for provider in providers {
            var definition = definitions[provider.name] ?? [:]
            definition.removeValue(forKey: "path")
            let identity: [String: Any] = ["profile": profileID, "kind": "rule", "name": provider.name,
                "definition": definition, "globalUA": root["global-ua"] ?? ""]
            let identityData = try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])
            let hash = SHA256.hash(data: identityData).map { String(format: "%02x", $0) }.joined()
            let url = directory.appendingPathComponent(hash)
            paths[provider.name] = ["path": url.path]
            let cap = provider.maximumBytes > 0 ? min(Self.maximumBytes, Int(clamping: provider.maximumBytes)) : Self.maximumBytes
            if let (data, modified) = Self.stableBytes(at: url, maximumBytes: cap) {
                var count = 0
                var error: NSError?
                if AppCore.inspectProvider(provider.kind, provider.behavior, provider.format, data, &count, &error) {
                    bytes[provider.name] = data
                    written[provider.name] = modified
                }
            }
        }
        let patch = try JSONSerialization.data(withJSONObject: ["patch": ["rule-providers": paths]], options: [.sortedKeys])
        runtimeYAML = try ConfigTransforms.mergeOverride(raw: mergedYAML, overrideJSON: String(decoding: patch, as: UTF8.self))
        snapshots = bytes
         
         
         
         
        let checked = Self.lastChecked(rules: Set(bytes.keys), workingDirectory: workingDirectory)
        dates = written.merging(checked) { _, check in check }
        self.paths = paths.mapValues { $0["path"]! }
    }

     
     
    private static func lastChecked(rules: Set<String>, workingDirectory: URL) -> [String: Date] {
        guard !rules.isEmpty,
              let data = try? Data(contentsOf: workingDirectory.appendingPathComponent("provider-refresh/state.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == 2,
              let running = (root["running"] as? [String: Any])?["providers"] as? [String: String],
              let entries = root["entries"] as? [String: [String: Any]] else { return [:] }
        var dates: [String: Date] = [:]
        for name in rules {
            guard let key = running["rule:" + name],
                  let seconds = (entries[key]?["lastCheckedAt"] as? NSNumber)?.int64Value, seconds > 0 else { continue }
            dates[name] = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return dates
    }

    private static func stableBytes(at url: URL, maximumBytes: Int) -> (Data, Date)? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= maximumBytes,
              let data = try? file.read(upToCount: maximumBytes + 1), data.count == before.st_size else { return nil }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { return nil }
        return (data, Date(timeIntervalSince1970: TimeInterval(after.st_mtimespec.tv_sec)))
    }
}
