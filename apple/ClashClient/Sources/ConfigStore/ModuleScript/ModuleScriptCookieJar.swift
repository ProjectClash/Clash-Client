#if os(iOS) || os(macOS)
import Foundation

 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
struct ModuleScriptCookieJar {
    private struct Cookie {
        let domain: String
        let hostOnly: Bool
        let name: String
        var value: String
        let secure: Bool
         
        let fromHTTPS: Bool
    }

    static let maximumCookies = 64
    static let maximumCookieBytes = 4096
    private var cookies: [Cookie] = []

    mutating func store(_ setCookies: [String], from host: String, overHTTPS: Bool, now: Date) {
        for line in setCookies {
            let parts = line.split(separator: ";", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let pair = parts.first, let equals = pair.firstIndex(of: "="), line.utf8.count <= Self.maximumCookieBytes else { continue }
            let name = String(pair[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var domain = host
            var hostOnly = true
            var removes = false
            var refused = false
            var secure = false
            var maxAge: Int?
            var expires: Date?
            for attribute in parts.dropFirst() {
                let pieces = attribute.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let argument = pieces.count > 1 ? pieces[1] : ""
                switch pieces.first?.lowercased() {
                case "domain"?:
                    let named = argument.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                     
                    guard named.contains(".") else { refused = true; break }
                     
                    guard host == named || host.hasSuffix("." + named) else { removes = true; break }
                    domain = named
                    hostOnly = false
                case "max-age"?:
                    if let seconds = Int(argument) { maxAge = seconds }
                case "expires"?:
                    expires = Self.httpDate(argument)
                case "secure"?:
                    secure = true
                default:
                    break
                }
            }
            if refused { continue }
             
             
             
             
             
            if let maxAge { if maxAge <= 0 { removes = true } } else if let expires, expires.timeIntervalSince(now) <= 0 { removes = true }
            cookies.removeAll { $0.domain == domain && $0.name == name }
            guard !removes, !value.isEmpty else { continue }
            cookies.append(Cookie(domain: domain, hostOnly: hostOnly, name: name, value: value, secure: secure,
                                  fromHTTPS: overHTTPS))
            if cookies.count > Self.maximumCookies { cookies.removeFirst(cookies.count - Self.maximumCookies) }
        }
    }

    func header(for host: String, overHTTPS: Bool) -> String? {
        let sent = cookies.filter { cookie in
            guard overHTTPS || (!cookie.secure && !cookie.fromHTTPS) else { return false }
            return cookie.hostOnly ? cookie.domain == host : (host == cookie.domain || host.hasSuffix("." + cookie.domain))
        }
        guard !sent.isEmpty else { return nil }
        return sent.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

     
     
    static func httpDate(_ text: String) -> Date? {
        for formatter in httpDateFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

     
     
     
    private static let httpDateFormatters: [DateFormatter] = [
        #"EEE, dd MMM yyyy HH:mm:ss zzz"#, #"EEE, dd-MMM-yyyy HH:mm:ss zzz"#, #"EEEE, dd-MMM-yy HH:mm:ss zzz"#,
        #"EEE, dd-MMM-yy HH:mm:ss zzz"#, #"EEE MMM d HH:mm:ss yyyy"#,
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = format
        return formatter
    }
}
#endif
