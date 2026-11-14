import Foundation

 
 
 
 
 
 
 
enum PastedContent: Equatable {
    case empty
     
     
    case link(url: String, unwrapped: Unwrap?, rules: InstallLinkRuleScheme? = nil)
    case nodeShareLinks([String])
    case configText(String)
    case unrecognized

    enum Unwrap: Equatable {
        case installLink
        case subScheme
    }
}

enum PastedContentClassifier {
     
     
     
     
     
    static let nodeSchemes = ProxyImportBridge.profilePasteNodeSchemes

    static func classify(_ raw: String) -> PastedContent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

         
         
         
         
        if let inner = shadowrocketAddTarget(trimmed) {
            return classify(inner)
        }
        if let target = installLinkTarget(trimmed) {
            return .link(url: target.url, unwrapped: .installLink, rules: target.rules)
        }
        if !trimmed.contains(where: \.isNewline), let inner = subSchemeTarget(trimmed) {
             
             
             
            if nodeShareLinks(inner) != nil { return .configText(inner) }
            return .link(url: inner, unwrapped: .subScheme)
        }
        if let links = nodeShareLinks(trimmed) {
            return .nodeShareLinks(links)
        }
        if !trimmed.contains("\n"), scheme(of: trimmed) != nil {
            return .link(url: trimmed, unwrapped: nil)
        }
        if trimmed.contains("\n") || trimmed.contains(":") {
            return .configText(raw)
        }
         
         
         
         
         
        if let decoded = base64Body(trimmed), nodeShareLinks(decoded) != nil {
            return .configText(raw)
        }
        return .unrecognized
    }

     
     
    private static func base64Body(_ text: String) -> String? {
        guard !text.contains(where: \.isNewline), text.count >= 8 else { return nil }
        var padded = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        let inner = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    private static func scheme(of text: String) -> String? {
        guard let range = text.range(of: "://"), range.lowerBound != text.startIndex else {
            return nil
        }
        let candidate = String(text[text.startIndex..<range.lowerBound]).lowercased()
        return candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "+" }
            ? candidate : nil
    }

     
     
     
     
    private static func installLinkTarget(_ text: String) -> FlClashInstallLink.Target? {
        guard let components = URLComponents(string: text) else { return nil }
        return try? FlClashInstallLink.target(of: components)
    }

    private static func shadowrocketAddTarget(_ text: String) -> String? {
        let prefix = "shadowrocket://add/"
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        let rest = String(text.dropFirst(prefix.count))
         
        let inner = rest.contains("://") ? rest : (rest.removingPercentEncoding ?? rest)
        return inner.isEmpty || shadowrocketAddTarget(inner) != nil ? nil : inner
    }

    private static func subSchemeTarget(_ text: String) -> String? {
        guard scheme(of: text) == "sub" else { return nil }
         
         
         
         
         
         
        var payload = String(text.dropFirst("sub://".count)
            .prefix { $0 != "#" && $0 != "?" && !$0.isWhitespace })
        if payload.contains("%") { payload = payload.removingPercentEncoding ?? payload }
         
        var padded = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        let inner = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

     
     
     
     
    static func isShadowrocketProxyLink(_ line: String) -> Bool {
        guard let scheme = scheme(of: line), scheme == "http" || scheme == "https" else { return false }
         
         
         
        let rest = String(line.dropFirst(scheme.count + 3).prefix { $0 != "?" && $0 != "#" })
        guard rest.count >= 8, !rest.contains("."), let decoded = base64Body(rest) else { return false }
         
         
         
         
         
         
        let endpoint = #"^(\[[0-9A-Fa-f:.]+\]|[^\s@:/?#\[\]]+):[0-9]{1,5}([-,][0-9]{1,5})*($|[/?#])"#
        func isEndpoint(_ text: Substring) -> Bool {
            guard let range = text.range(of: endpoint, options: .regularExpression) else { return false }
            var match = text[range]
            if let last = match.last, "/?#".contains(last) { match = match.dropLast() }
            guard let colon = match.lastIndex(of: ":"),
                  let port = Int(match[match.index(after: colon)...].prefix(while: \.isNumber)) else { return false }
            return (1...65535).contains(port)
        }
        var index = decoded.startIndex
        while let at = decoded[index...].firstIndex(of: "@") {
            if at > decoded.startIndex, isEndpoint(decoded[decoded.index(after: at)...]) { return true }
            index = decoded.index(after: at)
        }
        let title = decoded.firstIndex(of: "#") ?? decoded.endIndex
        return !decoded[..<title].contains("@") && isEndpoint(decoded[...])
    }

    private static func nodeShareLinks(_ text: String) -> [String]? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        guard lines.allSatisfy({ line in
            guard let scheme = scheme(of: line) else { return false }
            return nodeSchemes.contains(scheme) || isShadowrocketProxyLink(line)
        }) else { return nil }
        return lines
    }
}
