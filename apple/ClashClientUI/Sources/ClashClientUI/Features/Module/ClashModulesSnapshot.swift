import ClashClientKit
import Foundation

 
 
 
 
 
public struct ClashModulesSnapshot: Equatable, Sendable {
     
     
     
    public enum CertificateState: String, CaseIterable, Equatable, Sendable {
        case notGenerated
        case notInstalled
        case installedNotTrusted
        case ready
        case unreadable
    }

     
     
    public enum CertificateActionKind: Equatable, Sendable {
        case create
         
         
         
        case installProfile
         
         
        case installAndTrust
         
        case openInKeychainAccess
        case makeNew
    }

    public struct CertificateAction: Equatable, Sendable {
        public var kind: CertificateActionKind
        public var title: ClashDisplayText

        public init(kind: CertificateActionKind, title: ClashDisplayText) {
            self.kind = kind
            self.title = title
        }
    }

     
     
     
     
    public struct Certificate: Equatable, Sendable {
        public var state: CertificateState
         
         
        public var steps: [ClashDisplayText]
         
         
        public var note: ClashDisplayText?
        public var action: CertificateAction?
        public var renewWarning: ClashDisplayText

        public init(state: CertificateState, steps: [ClashDisplayText] = [],
                    note: ClashDisplayText? = nil, action: CertificateAction?, renewWarning: ClashDisplayText) {
            self.state = state
            self.steps = steps
            self.note = note
            self.action = action
            self.renewWarning = renewWarning
        }
    }

     
     
     
     
    public struct Install: Equatable, Sendable {
        public var action: CertificateAction
        public var effect: ClashDisplayText

        public init(action: CertificateAction, effect: ClashDisplayText) {
            self.action = action
            self.effect = effect
        }
    }

    public enum NoticeAction: Equatable, Sendable {
         
         
        case retryAfterMemoryStop
         
         
        case runScriptAgain(sha256: String)
    }

     
     
     
     
    public enum NoticePlace: Hashable, Sendable, Identifiable {
         
        case snifferSettings(profileID: String)

        public var id: Self { self }
    }

     
     
    public struct Notice: Equatable, Sendable, Identifiable {
         
         
        public enum Tone: Equatable, Sendable {
            case attention
            case onHold
        }

        public var id: String
        public var text: ClashDisplayText
        public var action: NoticeAction?
        public var actionTitle: ClashDisplayText?
        public var tone: Tone
         
         
        public var place: NoticePlace?

        public init(id: String, text: ClashDisplayText, action: NoticeAction? = nil, actionTitle: ClashDisplayText? = nil,
                    tone: Tone = .attention, place: NoticePlace? = nil) {
            self.id = id
            self.text = text
            self.action = action
            self.actionTitle = actionTitle
            self.tone = tone
            self.place = place
        }
    }

     
     
    public struct ModuleRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
         
         
        public var source: ClashModuleSource
        public var updatedAt: Date?
        public var effectiveCount: Int
        public var ignoredCount: Int
        public var enabled: Bool
         
         
        public var failure: ClashDisplayText?
         
         
         
         
        public var link: String?
         
         
         
        public var waitingCount: Int
        public var waitsFor: ClashModuleDecryptionWait?

        public init(id: String, name: String, source: ClashModuleSource, updatedAt: Date?, effectiveCount: Int,
                    ignoredCount: Int, enabled: Bool, failure: ClashDisplayText? = nil, link: String? = nil,
                    waitingCount: Int = 0, waitsFor: ClashModuleDecryptionWait? = nil) {
            self.id = id
            self.name = name
            self.source = source
            self.updatedAt = updatedAt
            self.effectiveCount = effectiveCount
            self.ignoredCount = ignoredCount
            self.enabled = enabled
            self.failure = failure
            self.link = link
            self.waitingCount = waitingCount
            self.waitsFor = waitsFor
        }

         
        public init(id: String, name: String, sourceHost: String?, updatedAt: Date?, effectiveCount: Int,
                    ignoredCount: Int, enabled: Bool, failure: ClashDisplayText? = nil, link: String? = nil) {
            self.init(id: id, name: name, source: sourceHost.map { .link($0) } ?? .local, updatedAt: updatedAt,
                      effectiveCount: effectiveCount, ignoredCount: ignoredCount, enabled: enabled, failure: failure,
                      link: link)
        }

         
         
         
         
         
         
         
        public static func distinguishingPaths(_ rows: [ModuleRow]) -> [String: String] {
            var paths: [String: String] = [:]
            let linked = rows.compactMap { row in row.link.map { (id: row.id, name: row.name, segments: pathSegments(of: $0)) } }
            for group in Dictionary(grouping: linked, by: \.name).values where group.count > 1 {
                guard let ends = shortestDistinctEnds(group.map { Array($0.segments.dropLast()) })
                    ?? shortestDistinctEnds(group.map(\.segments)) else { continue }
                for (member, end) in zip(group, ends) { paths[member.id] = "\u{2026}/" + end }
            }
            return paths
        }

         
        private static func pathSegments(of link: String) -> [String] {
            (URLComponents(string: link)?.percentEncodedPath ?? "").split(separator: "/").map(String.init)
        }

         
         
        private static func shortestDistinctEnds(_ lists: [[String]]) -> [String]? {
            let longest = lists.map(\.count).max() ?? 0
            guard longest > 0 else { return nil }
            for count in 1...longest {
                let ends = lists.map { $0.suffix(count).joined(separator: "/") }
                if !ends.contains(""), Set(ends).count == ends.count { return ends }
            }
            return nil
        }

         
         
        public var sourceHost: String? {
            get { if case .link(let host) = source { return host } else { return nil } }
            set { source = newValue.map { .link($0) } ?? .local }
        }

         
         
        public var isLocal: Bool { source == .local }
    }

     
    public var isOn: Bool
    public var isBusy: Bool
     
     
    public var certificate: Certificate?
     
    public var install: Install?
    public var notices: [Notice]
    public var modules: [ModuleRow]
     
     
     
    public var editor: ClashModuleEditorSnapshot?
     
     
    public var batch: Batch?

     
    public struct Batch: Equatable, Sendable {
        public var done: Int
        public var total: Int
        public var isRunning: Bool

        public init(done: Int, total: Int, isRunning: Bool) {
            self.done = done
            self.total = total
            self.isRunning = isRunning
        }
    }

     
    public var canRefreshAll: Bool { modules.contains { $0.link != nil } }

     
     
    func order(moving id: String, by offset: Int) -> [String]? {
        var ids = modules.map(\.id)
        guard let at = ids.firstIndex(of: id), ids.indices.contains(at + offset) else { return nil }
        ids.swapAt(at, at + offset)
        return ids
    }

    public init(isOn: Bool = false, isBusy: Bool = false, certificate: Certificate? = nil, install: Install? = nil,
                notices: [Notice] = [], modules: [ModuleRow] = [], editor: ClashModuleEditorSnapshot? = nil,
                batch: Batch? = nil) {
        self.isOn = isOn
        self.isBusy = isBusy
        self.certificate = certificate
        self.install = install
        self.notices = notices
        self.modules = modules
        self.editor = editor
        self.batch = batch
    }

    public static let off = ClashModulesSnapshot()
}

extension ClashModulesSnapshot.CertificateState {
     
     
    var title: ClashDisplayText {
        switch self {
        case .notGenerated: "Certificate Not Created"
        case .notInstalled: "Certificate Not Installed"
        case .installedNotTrusted: "Certificate Installed, Not Trusted"
        case .ready: "Certificate Ready"
        case .unreadable: "Certificate Can't Be Read"
        }
    }

     
     
    var rowValue: ClashDisplayText {
        switch self {
        case .notGenerated: "Not Created"
        case .notInstalled: "Not Installed"
        case .installedNotTrusted: "Not Trusted"
        case .ready: "Ready"
        case .unreadable: "Can't Be Read"
        }
    }
}

 
public enum ClashModulesAction: Equatable, Sendable {
     
    case setEnabled(Bool)
    case setModule(id: String, enabled: Bool)
    case removeModule(id: String)
    case refreshModule(id: String)
    case certificate(ClashModulesSnapshot.CertificateActionKind)
     
    case renewCertificate
    case notice(ClashModulesSnapshot.NoticeAction)
     
    case newModule
     
    case editModule(id: String)
     
     
    case saveModule(id: String?, text: String)
     
    case closeEditor
     
     
     
    case copy(String)
     
     
    case setArgument(module: String, name: String, value: String?)
     
    case resetArguments(module: String)
     
    case refreshPanel(id: String)
     
     
    case runAppScript(id: String)
     
     
    case renameModule(id: String, name: String)
     
     
    case moveModules([String])
     
     
    case refreshAll
     
     
    case panelsAppeared(module: String)
}

 
 
 
 
 
 
public enum ClashModuleDecryptionWait: Equatable, Sendable {
    case off
    case notReady
    case onHold
}

 
 
 
 
public struct ClashModuleScriptSource: Equatable, Sendable, Hashable {
    public var name: String
    public var link: String
    public var file: URL?

    public init(name: String, link: String, file: URL?) {
        self.name = name
        self.link = link
        self.file = file
    }
}

public struct ClashModuleDetailSnapshot: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String
         
        public var text: String
        public var detail: ClashDisplayText?
         
        public var secondary: String?
        public var action: ClashModulesSnapshot.NoticeAction?
        public var actionTitle: ClashDisplayText?
         
         
         
        public var place: ClashDisplayText?
         
         
        public var script: ClashModuleScriptSource?
         
         
         
        public var runNow: String?

        public init(id: String, text: String, detail: ClashDisplayText? = nil, secondary: String? = nil,
                    action: ClashModulesSnapshot.NoticeAction? = nil, actionTitle: ClashDisplayText? = nil,
                    place: ClashDisplayText? = nil, script: ClashModuleScriptSource? = nil, runNow: String? = nil) {
            self.id = id
            self.text = text
            self.detail = detail
            self.secondary = secondary
            self.action = action
            self.actionTitle = actionTitle
            self.place = place
            self.script = script
            self.runNow = runNow
        }
    }

     
     
    public struct Section: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: ClashDisplayText
        public var items: [Item]
         
         
         
        public var waiting: ClashDisplayText?

        public init(id: String, title: ClashDisplayText, items: [Item], waiting: ClashDisplayText? = nil) {
            self.id = id
            self.title = title
            self.items = items
            self.waiting = waiting
        }
    }

     
     
     
     
     
    public struct Panel: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var content: String?
         
         
        public var icon: String?
         
        public var iconColor: String?
         
        public var updatedAt: Date?
         
        public var refreshes: Bool
         
        public var canRefresh: Bool
        public var isRefreshing: Bool
         
        public var status: ClashDisplayText?
        public var statusIsFailure: Bool

        public init(id: String, title: String, content: String? = nil, icon: String? = nil, iconColor: String? = nil,
                    updatedAt: Date? = nil, refreshes: Bool = false, canRefresh: Bool = false, isRefreshing: Bool = false,
                    status: ClashDisplayText? = nil, statusIsFailure: Bool = false) {
            self.id = id
            self.title = title
            self.content = content
            self.icon = icon
            self.iconColor = iconColor
            self.updatedAt = updatedAt
            self.refreshes = refreshes
            self.canRefresh = canRefresh
            self.isRefreshing = isRefreshing
            self.status = status
            self.statusIsFailure = statusIsFailure
        }
    }

    public var id: String
    public var name: String
    public var summary: String?
    public var author: String?
     
     
    public var source: ClashModuleSource
    public var updatedAt: Date?
    public var enabled: Bool
    public var effectiveCount: Int
    public var ignoredCount: Int
    public var failure: ClashDisplayText?
     
     
    public var failureIsSentence: Bool
    public var isUpdating: Bool
    public var sections: [Section]
     
     
    public var needsDecryptionCount: Int
     
     
    public var date: String? = nil
    public var homepage: String? = nil
     
     
    public var settings: Settings? = nil
     
     
    public var waitsFor: ClashModuleDecryptionWait?
     
     
    public var unavailableCount: Int
     
    public var panels: [Panel] = []
     
     
     
     
    public var ownName: String? = nil

    public init(id: String, name: String, summary: String?, author: String?, source: ClashModuleSource,
                updatedAt: Date?, enabled: Bool, effectiveCount: Int, ignoredCount: Int, failure: ClashDisplayText?,
                isUpdating: Bool, sections: [Section], needsDecryptionCount: Int = 0, failureIsSentence: Bool = false,
                waitsFor: ClashModuleDecryptionWait? = nil, unavailableCount: Int = 0) {
        self.id = id
        self.name = name
        self.summary = summary
        self.author = author
        self.source = source
        self.updatedAt = updatedAt
        self.enabled = enabled
        self.effectiveCount = effectiveCount
        self.ignoredCount = ignoredCount
        self.failure = failure
        self.isUpdating = isUpdating
        self.sections = sections
        self.needsDecryptionCount = needsDecryptionCount
        self.failureIsSentence = failureIsSentence
        self.waitsFor = waitsFor
        self.unavailableCount = unavailableCount
    }

     
    public init(id: String, name: String, summary: String?, author: String?, link: String?, updatedAt: Date?,
                enabled: Bool, effectiveCount: Int, ignoredCount: Int, failure: ClashDisplayText?, isUpdating: Bool,
                sections: [Section], needsDecryptionCount: Int = 0) {
        self.init(id: id, name: name, summary: summary, author: author, source: link.map { .link($0) } ?? .local,
                  updatedAt: updatedAt, enabled: enabled, effectiveCount: effectiveCount, ignoredCount: ignoredCount,
                  failure: failure, isUpdating: isUpdating, sections: sections, needsDecryptionCount: needsDecryptionCount)
    }

     
     
    public var link: String? {
        get { if case .link(let link) = source { return link } else { return nil } }
        set { source = newValue.map { .link($0) } ?? .local }
    }

     
     
    public var isLocal: Bool { source == .local }
}

 
public enum ClashModuleSource: Equatable, Sendable {
     
     
    case link(String)
     
    case local
     
     
    case unknown
}

 
 
public struct ClashModuleEditorSnapshot: Equatable, Sendable, Identifiable {
     
    public var moduleID: String?
     
     
    public var text: String?
    public var isSaving: Bool
     
     
    public var refusal: ClashDisplayText?

    public init(moduleID: String? = nil, text: String? = nil, isSaving: Bool = false, refusal: ClashDisplayText? = nil) {
        self.moduleID = moduleID
        self.text = text
        self.isSaving = isSaving
        self.refusal = refusal
    }

    public var id: String { moduleID.map { "module|" + $0 } ?? "new" }

     
     
    public static func template(locale: Locale) -> String {
         
        ["#!name=" + ClashCopy.string("My Module", locale: locale), "#!desc=", "", ""].joined(separator: "\n")
    }

     
    public static func canSave(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
