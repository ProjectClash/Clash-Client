import ClashClientKit
import Foundation

 
extension AdBlockSentence: Error {}

 
 
 
 
 

 
 
 
 
 
 
 
 
actor AdBlockModuleResourceFetcher {
    enum Place: String, Sendable {
         
        case files
         
        case sets
    }

     
    struct Request: Sendable {
        var url: String
        var place: Place
         
        var cap: Int
         
         
        var budget: Int
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
         
         
        case failed(Failure, read: Int)
         
        case notTried
    }

    enum Failure: Equatable, Sendable {
         
        case tooLarge(Int)
         
        case overTheModuleBudget
         
        case notSecure
         
         
        case unusable
    }

    private let locations: AdBlockModuleLocations
    private let download: @Sendable (URL, Int, String?, String?, [String: String]) async throws -> DownloadResult
    private let isOutOfTime: @Sendable (Error) async -> Bool
    private let write: @Sendable (Data, URL) async throws -> Void
    private let log: @Sendable (String) -> Void

     
     
     
     
    init(locations: AdBlockModuleLocations,
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
            log("ad-block module \(id): \(link) is no address a file can be downloaded from")
            return .failed(.unusable, read: 0)
        }
        switch DownloadHostPlace.of(host) {
        case .thisDevice:
             
             
             
            log("ad-block module \(id): \(link) is on this device or its link-local network, which a module's file is never read from")
            return .failed(.unusable, read: 0)
        case .internet where scheme == "http":
            log("ad-block module \(id): \(link) is plain http, which a module's file is not read from off the local network")
            return .failed(.notSecure, read: 0)
        case .localNetwork, .internet:
            break
        }
         
        let limit = max(1, min(request.cap, request.budget))
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
            if AdBlockModuleStore.isCancellation(error) { throw CancellationError() }
            if await isOutOfTime(error) {
                log("ad-block module \(id): \(link) was not downloaded: the background task's time ran out")
                return .notTried
            }
             
            if case DownloadError.tooLarge(let observed) = error { return tooLarge(request, id: id, read: min(max(0, observed), asked + 1)) }
            log("ad-block module \(id): \(link) could not be downloaded (\(AuthoredText.of(error).englishText))")
            return .failed(.unusable, read: 0)
        }
        if answer.notModified {
             
            guard let earlier else {
                log("ad-block module \(id): \(link) answered \"not modified\" to a request that asked about no copy")
                return .failed(.unusable, read: 0)
            }
            log("ad-block module \(id): \(link) has not changed")
            return .notModified(etag: answer.etag ?? earlier.etag, lastModified: answer.lastModified ?? earlier.lastModified)
        }
        let read = answer.data.count
        var body = answer.data
        if request.base64 {
            guard let decoded = Self.base64Decoded(body) else {
                log("ad-block module \(id): \(link) is not base64")
                return .failed(.unusable, read: read)
            }
            body = decoded
            guard body.count <= limit else { return tooLarge(request, id: id, read: read) }
        }
         
         
        if body.isEmpty {
            log("ad-block module \(id): \(link) answered with nothing")
            return .failed(.unusable, read: read)
        }
        if !request.acceptsHTML, Self.isWebPage(body) {
            log("ad-block module \(id): \(link) answered with a web page, not the file")
            return .failed(.unusable, read: read)
        }
        let sha = AdBlockJSON.sha256(body)
        let target = published(id, sha256: sha, in: request.place)
        if !FileManager.default.fileExists(atPath: target.path) {
            do {
                try await write(body, target)
            } catch {
                log("ad-block module \(id): \(link) could not be written (\(error.localizedDescription))")
                return .failed(.unusable, read: read)
            }
        }
        log("ad-block module \(id): \(link) downloaded, \(body.count) bytes, sha256 \(sha)")
        return .fetched(sha256: sha, byteCount: body.count, etag: answer.etag, lastModified: answer.lastModified)
    }

    private func tooLarge(_ request: Request, id: String, read: Int) -> Outcome {
        if request.budget < request.cap {
            log("ad-block module \(id): \(request.url) is larger than the \(request.budget) bytes the module's files have left")
            return .failed(.overTheModuleBudget, read: read)
        }
        log("ad-block module \(id): \(request.url) is larger than \(request.cap) bytes")
        return .failed(.tooLarge(request.cap), read: read)
    }

     
     
    static func base64Length(of bytes: Int) -> Int {
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
