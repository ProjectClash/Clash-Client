import Combine
import Foundation
import NetworkExtension

struct EgressLookupResult: Equatable {
    let address: String
    let countryName: String
    let countryCode: String
    let provider: String

    static func decode(_ data: Data) -> EgressLookupResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = object["ip"] as? String,
              !address.isEmpty
        else { return nil }
        let countryName = object["country"] as? String ?? ""
        let countryCode = (object["country_code"] as? String ?? "").uppercased()
        let isp = object["isp"] as? String
            ?? object["asn_organization"] as? String
            ?? object["organization"] as? String
            ?? "?"
        let asn: Int? = {
            if let value = object["asn"] as? Int { return value }
            if let value = object["asn"] as? NSNumber { return value.intValue }
            return nil
        }()
        return EgressLookupResult(
            address: address,
            countryName: countryName,
            countryCode: countryCode,
            provider: asn.map { "\(isp) · AS\($0)" } ?? isp)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let sources: [Source] = [
        Source(address: #"https://api.ip.sb/geoip"#, decode: decode),
        Source(address: #"https://www.cloudflare.com/cdn-cgi/trace"#, decode: decodeCloudflareTrace),
        Source(address: #"https://ipinfo.io/json"#, decode: { decodeJSON($0, address: "ip", countryCode: "country") }),
        Source(address: #"https://ipwho.is"#, decode: { decodeJSON($0, address: "ip", countryCode: "country_code") }),
         
         
        Source(address: #"http://ip-api.com/json"#, decode: { decodeJSON($0, address: "query", countryCode: "countryCode") }),
        Source(address: #"https://get.geojs.io/v1/ip/geo.json"#, decode: { decodeJSON($0, address: "ip", countryCode: "country_code") }),
        Source(address: #"https://api.country.is"#, decode: { decodeJSON($0, address: "ip", countryCode: "country") }),
        Source(address: #"https://api.ipquery.io/?format=json"#, decode: { decodeJSON($0, address: "ip", countryCode: "country_code", under: "location") }),
        Source(address: #"https://ident.me/json"#, decode: { decodeJSON($0, address: "ip", countryCode: "cc") }),
    ]

     
    struct Source {
        let address: String
        let decode: (Data) -> EgressLookupResult?
    }

     
     
    static func decodeCloudflareTrace(_ data: Data) -> EgressLookupResult? {
        var fields: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            fields[String(line[line.startIndex..<separator])] = String(line[line.index(after: separator)...])
        }
        guard let address = fields["ip"], !address.isEmpty else { return nil }
         
         
        return EgressLookupResult(address: address, countryName: "",
                                  countryCode: (fields["loc"] ?? "").uppercased(), provider: "")
    }

     
     
    static func decodeJSON(_ data: Data, address addressKey: String, countryCode countryCodeKey: String,
                           under container: String? = nil) -> EgressLookupResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = root[addressKey] as? String, !address.isEmpty
        else { return nil }
        let holder = container.flatMap { root[$0] as? [String: Any] } ?? root
        return EgressLookupResult(address: address, countryName: "",
                                  countryCode: (holder[countryCodeKey] as? String ?? "").uppercased(),
                                  provider: "")
    }

    static func flagEmoji(countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.count == 2,
              code.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) })
        else { return "" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value)
        }))
    }
}

 
 
@MainActor
final class StatsModel: ObservableObject {
    @Published var egressIP: String = "—"
    @Published var egressISP: String = "—"
    @Published var egressCountryName: String = "—"
    @Published var egressCountryCode: String = ""

    private var session: NETunnelProviderSession?
    private var command: ClashCommandClient?

    func bind(session: NETunnelProviderSession?, command: ClashCommandClient) {
        self.session = session
        self.command = command
    }

     
     
    var tunnelIsUpForLookup: (() -> Bool)?
    var answerForLookup: ((URLRequest) async throws -> Data)?

     
     
    private var tunnelRun: UInt64 = 0

     
     
     
     
     
     
     
     
    func tunnelStatusChanged(_ status: String) {
        guard !["connected", "reasserting"].contains(status) else { return }
        tunnelRun &+= 1
        guard egressIP != "—" || egressISP != "—" || egressCountryName != "—" || !egressCountryCode.isEmpty
        else { return }
        egressIP = "—"
        egressISP = "—"
        egressCountryName = "—"
        egressCountryCode = ""
    }

    @discardableResult
    func checkEgressIP() async -> Bool {
         
         
         
         
        await checkEgressIP(attempt: 1, deadline: Date().addingTimeInterval(Self.lookupBudget), run: tunnelRun)
    }

    private func checkEgressIP(attempt: Int, deadline: Date, run: UInt64) async -> Bool {
        egressIP = "checking…"
        egressISP = "…"
        egressCountryName = "…"
        egressCountryCode = ""
        guard tunnelIsUpForLookup?() ?? (isVPNActive && command?.isConnected == true) else {
            egressIP = "VPN not connected"
            egressISP = "—"
            egressCountryName = "—"
            return false
        }
         
         
         
         
         
        var lastError: Error?
        for source in EgressLookupResult.sources {
            guard Date() < deadline, let url = URL(string: source.address) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = min(Self.perSourceTimeout, deadline.timeIntervalSinceNow)
            do {
                let data: Data
                if let answerForLookup {
                    data = try await answerForLookup(request)
                } else {
                    data = try await OneShotHTTPSession.data(for: request).0
                }
                 
                 
                guard run == tunnelRun else { return false }
                if let result = source.decode(data) {
                    egressIP = result.address
                    egressISP = result.provider.isEmpty ? "—" : result.provider
                    egressCountryName = result.countryName.isEmpty ? result.countryCode : result.countryName
                    egressCountryCode = result.countryCode
                    return true
                }
            } catch {
                guard run == tunnelRun else { return false }
                lastError = error
            }
        }
        egressISP = "—"
        egressCountryName = "—"
        egressCountryCode = ""
        guard let lastError else {
             
            egressIP = "unexpected response"
            return false
        }
         
         
         
         
        if EgressRetryPolicy.shouldRetry(after: lastError, attempt: attempt,
                                         remaining: deadline.timeIntervalSinceNow, perSource: Self.perSourceTimeout) {
            return await checkEgressIP(attempt: attempt + 1, deadline: deadline, run: run)
        }
        egressIP = "error: \(lastError.localizedDescription)"
        return false
    }

     
    private static let lookupBudget: TimeInterval = 20
    private static let perSourceTimeout: TimeInterval = 6

    private var isVPNActive: Bool {
        session?.status == .connected || session?.status == .reasserting
    }
}

 
 
 
 
 
 
 
 
 
enum OneShotHTTPSession {
    static func data(
        for request: URLRequest,
        configuration: URLSessionConfiguration = .ephemeral,
        delegate: URLSessionDelegate? = nil
    ) async throws -> (Data, URLResponse) {
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }
}

 
 
 
 
 
enum EgressRetryPolicy {
    static let maximumAttempts = 2

     
     
    static func shouldRetry(after error: Error, attempt: Int,
                            remaining: TimeInterval = .infinity, perSource: TimeInterval = 0) -> Bool {
        guard attempt < maximumAttempts, remaining >= perSource else { return false }
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .timedOut
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
struct EgressRecheckDebt {
    private(set) var isOwed = false

     
    mutating func routeMoved(channelUp: Bool) -> Bool {
        isOwed = !channelUp
        return channelUp
    }

     
    mutating func channelChanged(up: Bool) -> Bool {
        guard up, isOwed else { return false }
        isOwed = false
        return true
    }
}
