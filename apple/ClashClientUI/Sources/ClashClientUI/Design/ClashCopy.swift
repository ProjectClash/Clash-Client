import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashCopy {
     
     
     
     
     
     
     
     
     
    public static func key(_ value: String) -> LocalizedStringKey {
        LocalizedStringKey(value)
    }

     
     
     
     
     
     
     
     
     
    public static func string(_ value: String, locale: Locale) -> String {
        let bundle = languageBundle(for: locale) ?? .main
        return bundle.localizedString(forKey: value, value: value, table: nil)
    }

     
     
    public static func composedString(_ value: String, locale: Locale) -> String {
        let exact = string(value, locale: locale)
        guard exact == value, value.contains(" · ") else {
            return exact
        }
        return value
            .components(separatedBy: " · ")
            .map { string($0, locale: locale) }
            .joined(separator: " · ")
    }

     
     
     
    public static func string(
        for text: ClashDisplayText,
        locale: Locale
    ) -> String {
        switch text {
        case .copy(let value):
            return string(value, locale: locale)
        case .verbatim(let value):
            return value
        case .format(let format, let arguments), .formatCopy(let format, let arguments):
             
             
             
             
            var arguments = arguments
            if case .formatCopy = text { arguments = arguments.map { string($0, locale: locale) } }
            let source = ClashDisplayText.formatSegments(of: format)
            var pieces = string(format, locale: locale)
                .components(separatedBy: "%@")
            if pieces.count != source.count {
                pieces = source
            }
            var line = pieces.removeFirst()
            for (index, piece) in pieces.enumerated() {
                var argument = index < arguments.count ? arguments[index] : "%@"
                if case .formatCopy = text { argument = nestingQuotes(argument, opening: line.last, closing: piece.first) }
                line += argument
                line += piece
            }
            return line
        }
    }

     
     
     
     
     
     
    static func nestingQuotes(_ argument: String, opening: Character?, closing: Character?) -> String {
        switch (opening, closing) {
        case ("“", "”"): return argument.replacingOccurrences(of: "“", with: "‘").replacingOccurrences(of: "”", with: "’")
        case ("「", "」"): return argument.replacingOccurrences(of: "「", with: "『").replacingOccurrences(of: "」", with: "』")
        case ("\"", "\""): return argument.replacingOccurrences(of: "\"", with: "'")
        default: return argument
        }
    }

     
     
     
    public static func count(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

     
    public static func format(
        _ value: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(value, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }

     
     
    nonisolated(unsafe) private static let languageBundles = NSCache<NSString, Bundle>()
    nonisolated(unsafe) private static let tableNames = NSCache<NSString, NSString>()

    private static func languageBundle(for locale: Locale) -> Bundle? {
        let code = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if let cached = languageBundles.object(forKey: code as NSString) {
            return cached
        }
        guard let name = tableName(for: locale),
              let path = Bundle.main.path(forResource: name, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        languageBundles.setObject(bundle, forKey: code as NSString)
        return bundle
    }

     
     
     
     
     
    static func tableName(for locale: Locale) -> String? {
        let code = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if let cached = tableNames.object(forKey: code as NSString) {
            return cached.length == 0 ? nil : cached as String
        }
        let name = tableName(for: locale, has: { Bundle.main.path(forResource: $0, ofType: "lproj") != nil })
        tableNames.setObject((name ?? "") as NSString, forKey: code as NSString)
        return name
    }

     
     
     
     
    static func tableName(for locale: Locale, has: (String) -> Bool) -> String? {
        var candidate = locale.identifier.replacingOccurrences(of: "_", with: "-")
        while !candidate.isEmpty {
            if has(candidate) { return candidate }
            guard let cut = candidate.lastIndex(of: "-") else { break }
            candidate = String(candidate[candidate.startIndex..<cut])
        }
        return nil
    }
}

public extension ClashDisplayText {
     
     
     
     
    func resolved(locale: Locale) -> String {
        switch self {
        case .verbatim(let value):
            return value
        case .copy(let value):
            return ClashCopy.string(value, locale: locale)
        case .format(let format, let arguments), .formatCopy(let format, let arguments):
            var line = ClashCopy.string(format, locale: locale)
            var arguments = arguments
            if case .formatCopy = self { arguments = arguments.map { ClashCopy.string($0, locale: locale) } }
            for argument in arguments {
                guard let range = line.range(of: "%@")
                    ?? line.range(of: "%d")
                    ?? line.range(of: "%@", options: .literal)
                else { break }
                line.replaceSubrange(range, with: argument)
            }
            return line
        }
    }
}

public extension String {
     
    var clashLocalized: LocalizedStringKey {
        ClashCopy.key(self)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashDisplayText:
    Codable,
    Equatable,
    Hashable,
    Sendable,
    ExpressibleByStringLiteral
{
     
    case copy(String)
     
    case verbatim(String)
     
     
     
     
    case format(String, [String])
     
     
     
     
     
     
     
     
     
    case formatCopy(String, [String])

     
     
    public var isBlank: Bool {
        switch self {
        case .copy(let key), .verbatim(let key), .format(let key, _), .formatCopy(let key, _): return key.isEmpty
        }
    }

    public init(stringLiteral value: String) {
        self = .copy(value)
    }

     
     
     
     
     
     
    var frameWatchLabel: String {
        switch self {
        case .copy(let value): return value
        case .verbatim: return "(verbatim)"
        case .format(let format, _), .formatCopy(let format, _): return format
        }
    }

     
     
     
     
     
     
     
    func frameWatchLabel(overriddenBy explicit: String?) -> String {
        explicit ?? frameWatchLabel
    }

     
     
    public var rawValue: String {
        switch self {
        case .copy(let value), .verbatim(let value): return value
        case .format(let format, let arguments), .formatCopy(let format, let arguments):
            var pieces = Self.formatSegments(of: format)
            var line = pieces.removeFirst()
            for (index, piece) in pieces.enumerated() {
                line += (index < arguments.count ? arguments[index] : "%@")
                line += piece
            }
            return line
        }
    }

     
     
     
     
     
     
    func bounded(to limit: Int) -> ClashDisplayText {
        switch self {
        case .copy(let value):
            return .copy(String(value.prefix(limit)))
        case .verbatim(let value):
            return .verbatim(String(value.prefix(limit)))
        case .format(let format, let arguments):
            return .format(
                String(format.prefix(limit)),
                arguments.map { String($0.prefix(limit)) }
            )
        case .formatCopy(let format, let arguments):
            return .formatCopy(
                String(format.prefix(limit)),
                arguments.map { String($0.prefix(limit)) }
            )
        }
    }

     
     
     
     
     
     
     
    static func formatSegments(of format: String) -> [String] {
        format.components(separatedBy: "%@")
    }
}

public extension Text {
     
    init(clash text: ClashDisplayText) {
        switch text {
        case .copy(let value):
            self.init(ClashCopy.key(value))
        case .verbatim(let value):
            self.init(verbatim: value)
        case .format(let format, let arguments), .formatCopy(let format, let arguments):
             
             
             
             
             
             
             
            let translatesArguments: Bool
            if case .formatCopy = text { translatesArguments = true } else { translatesArguments = false }
            var interpolation = LocalizedStringKey.StringInterpolation(
                literalCapacity: format.count,
                interpolationCount: arguments.count
            )
            var pieces = ClashDisplayText.formatSegments(of: format)
            interpolation.appendLiteral(pieces.removeFirst())
            for (index, piece) in pieces.enumerated() {
                let argument = index < arguments.count ? arguments[index] : "%@"
                if translatesArguments {
                    interpolation.appendInterpolation(Text(ClashCopy.key(argument)))
                } else {
                    interpolation.appendInterpolation(argument)
                }
                interpolation.appendLiteral(piece)
            }
            self.init(LocalizedStringKey(stringInterpolation: interpolation))
        }
    }
}

