import ClashClientKit
import Foundation

 
extension ModuleSentence: Error {}

 
 
 
 
 
 
 
 
 
 
enum ModuleUserAgent {
    enum App: Equatable, Sendable {
        case surge, loon, shadowrocket, stash, quantumultX
    }

     
    static var clash: String { ClientUserAgent.Preset.clash.value }

     
    static func app(ofLink link: String?) -> App? {
        guard let path = link.flatMap({ URL(string: $0)?.path.lowercased() }) else { return nil }
        switch (path as NSString).pathExtension {
        case "sgmodule": return .surge
        case "plugin", "lpx": return .loon
        case "module", "srmodule": return .shadowrocket
        case "stoverride": return .stash
         
         
         
        case "conf", "snippet", "js": return .quantumultX
        default: return nil
        }
    }

     
     
    static func app(of manifest: ModuleManifest) -> App? {
        if manifest.sourceURL != nil { return app(ofLink: manifest.sourceURL) }
        switch manifest.format {
        case .surge: return .surge
        case .loon: return .loon
        case .stash: return .stash
        case .quantumultX: return .quantumultX
        }
    }

    static func forLink(_ link: String?) -> String { value(app(ofLink: link)) }
    static func forModule(_ manifest: ModuleManifest) -> String { value(app(of: manifest)) }

     
     
     
     
     
     
     
     
     
    static func value(_ app: App?) -> String {
        let darwin = "\(ClashDeviceModel.kernelName ?? "Darwin")/\(ClashDeviceModel.darwinRelease ?? "25.0.0")"
        switch app {
        case nil: return clash
        case .surge?: return #"Surge iOS/3908"#
        case .loon?: return "Loon/988 CFNetwork/\(cfNetwork) \(darwin)"
        case .shadowrocket?: return "Shadowrocket/3445 CFNetwork/\(cfNetwork) \(darwin) \(ClashDeviceModel.identifier)"
        case .stash?: return #"Stash/2.7.1 Clash/1.11.0"#
        case .quantumultX?: return "Quantumult%20X/1.5.5 (\(ClashDeviceModel.identifier); iOS \(systemVersion))"
        }
    }

     
    private static var cfNetwork: String {
        (Bundle(identifier: "com.apple.CFNetwork")?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap { $0.isEmpty || $0.contains(" ") ? nil : $0 } ?? "3860.500.112"
    }

     
    private static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.patchVersion == 0 ? "\(version.majorVersion).\(version.minorVersion)"
            : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

 
 
 
 
 
 
 
 
actor ModuleResourceFetcher {
    enum Place: String, Sendable {
         
        case files
         
        case sets
    }

     
    struct Request: Sendable {
        var url: String
        var place: Place
         
         
        var cap: Int
        var base64 = false
         
         
        var acceptsHTML = false
         
        var earlier: Earlier?
         
         
        var headers: [String: String] = [:]
    }

    struct Earlier: Sendable, Equatable {
        var sha256: String
        var etag: String?
        var lastModified: String?
    }

    enum Outcome: Equatable, Sendable {
         
        case fetched(sha256: String, byteCount: Int, etag: String?, lastModified: String?)
         
        case notModified(etag: String?, lastModified: String?)
         
        case failed(Failure)
         
        case notTried
    }

    enum Failure: Equatable, Sendable {
         
        case tooLarge(Int)
         
         
        case unusable
    }

    private let locations: ModuleLocations
    private let download: @Sendable (URL, Int, String?, String?, [String: String]) async throws -> DownloadResult
    private let isOutOfTime: @Sendable (Error) async -> Bool
    private let write: @Sendable (Data, URL) async throws -> Void
    private let log: @Sendable (String) -> Void

     
     
     
     
    init(locations: ModuleLocations,
         download: @escaping @Sendable (URL, Int, String?, String?, [String: String]) async throws -> DownloadResult,
         isOutOfTime: @escaping @Sendable (Error) async -> Bool,
         write: @escaping @Sendable (Data, URL) async throws -> Void,
         log: @escaping @Sendable (String) -> Void) {
        self.locations = locations
        self.download = download
        self.isOutOfTime = isOutOfTime
        self.write = write
        self.log = log
    }

    func published(_ id: String, sha256: String, in place: Place) -> URL {
        place == .files ? locations.file(id, sha256: sha256) : locations.ruleSet(id, sha256: sha256)
    }

     
    func fetch(_ request: Request, module id: String) async throws -> Outcome {
        let link = request.url
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else {
            log("module \(id): \(link) is no address a file can be downloaded from")
            return .failed(.unusable)
        }
        switch DownloadHostPlace.of(host) {
        case .thisDevice:
             
             
             
            log("module \(id): \(link) is on this device or its link-local network, which a module's file is never read from")
            return .failed(.unusable)
        case .localNetwork, .internet:
            break
        }
        let limit = max(1, request.cap)
        let asked = request.base64 ? Self.base64Length(of: limit) : limit
         
        let earlier = request.earlier.flatMap { earlier -> Earlier? in
            guard earlier.etag != nil || earlier.lastModified != nil,
                  FileManager.default.fileExists(atPath: published(id, sha256: earlier.sha256, in: request.place).path) else { return nil }
            return earlier
        }
        let answer: DownloadResult
        do {
            answer = try await download(url, asked, earlier?.etag, earlier?.lastModified, request.headers)
        } catch {
            if ModuleStore.isCancellation(error) { throw CancellationError() }
            if await isOutOfTime(error) {
                log("module \(id): \(link) was not downloaded: the background task's time ran out")
                return .notTried
            }
            if case DownloadError.tooLarge = error { return tooLarge(request, id: id) }
            log("module \(id): \(link) could not be downloaded (\(AuthoredText.of(error).englishText))")
            return .failed(.unusable)
        }
        if answer.notModified {
             
            guard let earlier else {
                log("module \(id): \(link) answered \"not modified\" to a request that asked about no copy")
                return .failed(.unusable)
            }
            log("module \(id): \(link) has not changed")
            return .notModified(etag: answer.etag ?? earlier.etag, lastModified: answer.lastModified ?? earlier.lastModified)
        }
        var body = answer.data
        if request.base64 {
            guard let decoded = Self.base64Decoded(body) else {
                log("module \(id): \(link) is not base64")
                return .failed(.unusable)
            }
            body = decoded
            guard body.count <= limit else { return tooLarge(request, id: id) }
        }
         
         
        if body.isEmpty {
            log("module \(id): \(link) answered with nothing")
            return .failed(.unusable)
        }
        if !request.acceptsHTML, Self.isWebPage(body) {
            log("module \(id): \(link) answered with a web page, not the file")
            return .failed(.unusable)
        }
        let sha = ModuleJSON.sha256(body)
        let target = published(id, sha256: sha, in: request.place)
        if !FileManager.default.fileExists(atPath: target.path) {
            do {
                try await write(body, target)
            } catch {
                log("module \(id): \(link) could not be written (\(error.localizedDescription))")
                return .failed(.unusable)
            }
        }
        log("module \(id): \(link) downloaded, \(body.count) bytes, sha256 \(sha)")
        return .fetched(sha256: sha, byteCount: body.count, etag: answer.etag, lastModified: answer.lastModified)
    }

    private func tooLarge(_ request: Request, id: String) -> Outcome {
        log("module \(id): \(request.url) is larger than \(request.cap) bytes")
        return .failed(.tooLarge(request.cap))
    }

     
     
     
    static func base64Length(of bytes: Int) -> Int {
        guard bytes < Int.max / 2 else { return .max }
        let encoded = (bytes + 2) / 3 * 4
        return encoded + encoded / 38 + 4
    }

     
    static func base64Decoded(_ data: Data) -> Data? {
        Data(base64Encoded: Data(data.filter { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }))
    }

     
     
    static func isWebPage(_ data: Data) -> Bool {
        var start = Data(data.prefix(512))
        if start.starts(with: [0xEF, 0xBB, 0xBF]) { start = start.dropFirst(3) }
        let text = String(decoding: start, as: UTF8.self).drop { $0.isWhitespace }.lowercased()
        return [#"<!doctype html"#, "<html", "<head", "<body", "<!--", "<title", "<meta", "<script"].contains { text.hasPrefix($0) }
    }

    typealias HostPlace = DownloadHostPlace

     
    static func place(ofHost raw: String) -> HostPlace { DownloadHostPlace.of(raw) }
}
