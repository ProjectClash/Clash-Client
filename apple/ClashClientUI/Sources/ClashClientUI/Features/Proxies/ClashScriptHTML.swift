import Foundation
import SwiftUI

 
 
 
 
 
 
 
 
 
 
public enum ClashScriptHTML {
    public struct Rendered: Equatable, Sendable {
        public var text: AttributedString
         
         
        public var centered: Bool

        public init(text: AttributedString, centered: Bool) {
            self.text = text
            self.centered = centered
        }
    }

     
    static let maximumCharacters = 100_000

     
    private static let unread: Set<String> = [
        "script", "style", "head", "title", "iframe", "frame", "frameset", "object", "embed", "svg", "math",
        "template", "noscript", "audio", "video", "canvas", "picture", "select", "datalist",
    ]
     
    private static let void: Set<String> = [
        "br", "img", "hr", "meta", "link", "input", "source", "wbr", "area", "base", "col", "track", "param",
    ]
    private static let blocks: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "blockquote", "center",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "table", "tr", "pre", "figure",
        "figcaption", "address", "body", "html",
    ]

    private struct Style: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var monospaced = false
        var preformatted = false
        var heading: Int?
        var color: Color?
    }

     
     
     
     
    public static func plainText(_ text: String) -> Rendered {
        let source = text.count > maximumCharacters ? String(text.prefix(maximumCharacters)) : text
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return Rendered(text: AttributedString(lines.trimmingCharacters(in: .newlines)), centered: false)
    }

    public static func render(_ html: String) -> Rendered {
        let source = html.count > maximumCharacters ? String(html.prefix(maximumCharacters)) : html
         
        guard source.contains("<") else {
            return Rendered(text: AttributedString(decodingEntities(source).trimmingCharacters(in: .whitespacesAndNewlines)),
                            centered: false)
        }
        var reader = Reader()
        reader.read(source)
        return Rendered(text: reader.finished(), centered: reader.centered ?? false)
    }

    private struct Reader {
        var out = AttributedString()
        var stack: [(name: String, style: Style)] = []
        var style = Style()
        var skipping: String?
        var pendingSpace = false
        var atLineStart = true
        var centered: Bool?
         
        var written = 0
        var trailingBreaks = 0
         
         
        var pending = ""
        var pendingStyle = Style()
         
         
         
         
        var unclosedFrom: String.Index?
        var commentsNeverEnd = false

        mutating func read(_ source: String) {
            var index = source.startIndex
            while index < source.endIndex {
                let character = source[index]
                if character == "<", let end = tagEnd(in: source, from: index) {
                    let inside = source[source.index(after: index)..<end]
                    tag(inside)
                    index = source.index(after: end)
                    continue
                }
                guard skipping == nil else {
                    index = source.index(after: index)
                    continue
                }
                if character == "&", let (decoded, next) = entity(in: source, at: index) {
                    text(decoded, literalSpace: decoded == "\u{00A0}")
                    index = next
                    continue
                }
                text(String(character), literalSpace: false)
                index = source.index(after: index)
            }
        }

         
         
        private mutating func tagEnd(in source: String, from start: String.Index) -> String.Index? {
            if let unclosedFrom, start >= unclosedFrom { return nil }
            let next = source.index(after: start)
            guard next < source.endIndex else { return nil }
            let first = source[next]
            guard first.isLetter || first == "/" || first == "!" || first == "?" else { return nil }
            if source[next...].hasPrefix("!--") {
                guard !commentsNeverEnd, let end = source.range(of: "-->", range: next..<source.endIndex) else {
                    commentsNeverEnd = true
                    return nil
                }
                return source.index(before: end.upperBound)
            }
            var quote: Character?
            var index = next
            while index < source.endIndex {
                let character = source[index]
                if let open = quote {
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    return index
                }
                index = source.index(after: index)
            }
            unclosedFrom = start
            return nil
        }

        private mutating func tag(_ inside: Substring) {
            var body = inside.trimmingCharacters(in: .whitespacesAndNewlines)[...]
            guard let first = body.first, first != "!", first != "?" else { return }
            let closing = first == "/"
            if closing { body = body.dropFirst() }
            let name = String(body.prefix { $0.isLetter || $0.isNumber }).lowercased()
            guard !name.isEmpty else { return }
            if let skipped = skipping {
                if closing, name == skipped { skipping = nil }
                return
            }
            if closing {
                close(name)
                return
            }
            let attributes = Self.attributes(body.dropFirst(name.count))
            open(name, attributes: attributes, selfClosing: body.hasSuffix("/"))
        }

        private mutating func open(_ name: String, attributes: [String: String], selfClosing: Bool) {
            if ClashScriptHTML.unread.contains(name) {
                if !selfClosing { skipping = name }
                return
            }
            switch name {
            case "br":
                lineBreak()
                return
            case "hr":
                block()
                return
            case "img", "meta", "link", "input", "source", "wbr", "area", "base", "col", "track", "param":
                 
                return
            default:
                break
            }
            let isBlock = ClashScriptHTML.blocks.contains(name)
            if isBlock { block() } else { flushSpace() }
            var next = style
            switch name {
            case "b", "strong": next.bold = true
            case "i", "em", "cite", "var": next.italic = true
            case "u", "ins": next.underline = true
            case "s", "del", "strike": next.strike = true
            case "code", "kbd", "samp", "tt": next.monospaced = true
            case "pre":
                next.monospaced = true
                next.preformatted = true
            case "h1", "h2", "h3", "h4", "h5", "h6":
                next.heading = Int(name.dropFirst())
                next.bold = true
            case "font":
                if let color = attributes["color"].flatMap(Self.color) { next.color = color }
            default:
                break
            }
            if let css = attributes["style"] { apply(css, to: &next, block: isBlock) }
            if name == "center", centered == nil { centered = true }
            if isBlock, centered == nil, attributes["align"]?.lowercased() == "center" { centered = true }
            if name == "li" { text("• ", literalSpace: true) }
            guard !selfClosing, !ClashScriptHTML.void.contains(name) else { return }
            stack.append((name, style))
            style = next
        }

        private mutating func close(_ name: String) {
            if name == "br" {
                 
                lineBreak()
                return
            }
            guard let at = stack.lastIndex(where: { $0.name == name }) else { return }
            if !ClashScriptHTML.blocks.contains(name) { flushSpace() }
            style = stack[at].style
            stack.removeSubrange(at...)
            if ClashScriptHTML.blocks.contains(name) { block() }
        }

        private mutating func apply(_ css: String, to next: inout Style, block isBlock: Bool) {
            for declaration in css.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                guard parts.count == 2 else { continue }
                let (property, value) = (parts[0], parts[1])
                switch property {
                case "color":
                    if let color = Self.color(value) { next.color = color }
                case "font-weight":
                    next.bold = value == "bold" || value == "bolder" || (Int(value) ?? 0) >= 600
                case "font-style":
                    next.italic = value == "italic" || value == "oblique"
                case "text-decoration", "text-decoration-line":
                    if value.contains("underline") { next.underline = true }
                    if value.contains("line-through") { next.strike = true }
                case "text-align":
                    if isBlock, centered == nil { centered = value == "center" }
                default:
                     
                    break
                }
            }
        }

         

        private mutating func text(_ words: String, literalSpace: Bool) {
            for character in words {
                if character.isWhitespace, !literalSpace {
                    if style.preformatted {
                        if character.isNewline { lineBreak() } else { emit(String(character)) }
                    } else {
                        pendingSpace = !atLineStart
                    }
                    continue
                }
                if pendingSpace {
                    emit(" ")
                    pendingSpace = false
                }
                emit(String(character))
                atLineStart = false
            }
        }

         
         
        private mutating func flushSpace() {
            guard pendingSpace else { return }
            emit(" ")
            pendingSpace = false
        }

        private mutating func lineBreak() {
            pendingSpace = false
            emit("\n")
            atLineStart = true
        }

         
        private mutating func block() {
            pendingSpace = false
            atLineStart = true
            guard written > 0 else { return }
            while trailingBreaks < 2 {
                emitBreak()
            }
        }

        private mutating func emitBreak() {
            flush()
            out.append(AttributedString("\n"))
            written += 1
            trailingBreaks += 1
        }

        private mutating func emit(_ piece: String) {
            if piece == "\n" {
                 
                guard trailingBreaks < 2 else { return }
                emitBreak()
                return
            }
            if style != pendingStyle { flush() }
            pendingStyle = style
            pending += piece
            written += 1
            trailingBreaks = 0
        }

         
        private mutating func flush() {
            guard !pending.isEmpty else { return }
            let style = pendingStyle
            var run = AttributedString(pending)
            pending = ""
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if style.strike { intent.insert(.strikethrough) }
            if style.monospaced { intent.insert(.code) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if style.underline { run[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single }
            if let color = style.color { run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color }
            if let level = style.heading {
                run[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = level <= 2 ? Font.title3.bold() : Font.headline
            }
            out.append(run)
        }

        mutating func finished() -> AttributedString {
            flush()
            var text = out
            while let last = text.characters.last, last.isWhitespace {
                text.characters.removeLast()
            }
            return text
        }

         

        private static func attributes(_ text: Substring) -> [String: String] {
            var found: [String: String] = [:]
            var index = text.startIndex
            func skipSpace() { while index < text.endIndex, text[index].isWhitespace || text[index] == "/" { index = text.index(after: index) } }
            while true {
                skipSpace()
                guard index < text.endIndex else { break }
                let nameStart = index
                while index < text.endIndex, !text[index].isWhitespace, text[index] != "=", text[index] != "/" {
                    index = text.index(after: index)
                }
                let name = text[nameStart..<index].lowercased()
                while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
                var value = ""
                if index < text.endIndex, text[index] == "=" {
                    index = text.index(after: index)
                    while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
                    if index < text.endIndex, text[index] == "\"" || text[index] == "'" {
                        let quote = text[index]
                        index = text.index(after: index)
                        let valueStart = index
                        while index < text.endIndex, text[index] != quote { index = text.index(after: index) }
                        value = String(text[valueStart..<index])
                        if index < text.endIndex { index = text.index(after: index) }
                    } else {
                        let valueStart = index
                        while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
                        value = String(text[valueStart..<index])
                    }
                }
                if !name.isEmpty, found[name] == nil { found[name] = ClashScriptHTML.decodingEntities(value) }
                if nameStart == index { index = text.index(after: index) }
            }
            return found
        }

        private func entity(in source: String, at start: String.Index) -> (String, String.Index)? {
            guard let semicolon = source[start...].prefix(12).firstIndex(of: ";") else { return nil }
            let name = String(source[source.index(after: start)..<semicolon])
            guard let decoded = ClashScriptHTML.entity(name) else { return nil }
            return (decoded, source.index(after: semicolon))
        }

         
         
         
         
        static func color(_ written: String) -> Color? {
            let value = written.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var rgb: (Double, Double, Double)?
            if value.hasPrefix("#") {
                let hex = String(value.dropFirst())
                let digits = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
                if digits.count == 6, let number = UInt32(digits, radix: 16) {
                    rgb = (Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255)
                }
            } else if value.hasPrefix("rgb") {
                let numbers = value.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
                    .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if numbers.count >= 3 { rgb = (numbers[0] / 255, numbers[1] / 255, numbers[2] / 255) }
            } else {
                switch value {
                case "red": return .red
                case "green", "lime": return .green
                case "blue": return .blue
                case "orange": return .orange
                case "yellow", "gold": return .yellow
                case "purple", "violet": return .purple
                case "pink": return .pink
                case "brown": return .brown
                case "teal": return .teal
                case "cyan", "aqua": return .cyan
                case "gray", "grey", "silver": return .gray
                default: return nil
                }
            }
            guard let rgb else { return nil }
            let (r, g, b) = rgb
            if (r, g, b) == (0, 0, 0) || (r, g, b) == (1, 1, 1) { return nil }
            return Color(red: r, green: g, blue: b)
        }
    }

     

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "ensp": "\u{2002}",
        "emsp": "\u{2003}", "thinsp": "\u{2009}", "copy": "©", "reg": "®", "trade": "™", "hellip": "…",
        "mdash": "—", "ndash": "–", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»", "times": "×",
        "divide": "÷", "deg": "°", "plusmn": "±", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "yen": "¥", "euro": "€", "pound": "£",
    ]

    static func entity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[name]
    }

    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";"),
               let decoded = entity(String(text[text.index(after: index)..<semicolon])) {
                out += decoded
                index = text.index(after: semicolon)
            } else {
                out.append(text[index])
                index = text.index(after: index)
            }
        }
        return out
    }
}
