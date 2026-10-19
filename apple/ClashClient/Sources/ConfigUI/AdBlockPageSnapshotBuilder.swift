#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
struct AdBlockPageFacts {
    var platform: AdBlockPlatform
    var state: AdBlockModuleState
     
    var modules: [String: AdBlockModuleIR] = [:]
     
     
    var sources: [String: Data] = [:]
    var certificate: AdBlockCertificateState = .notGenerated
     
     
     
     
    var certificateUnreadable = false
     
     
    var certificateName: String? = nil
     
     
    var keychainFallback: AdBlockKeychainFallback? = nil
     
     
    var oldCertificateLeft: String? = nil
     
    var report: AdBlockEngineReport? = nil
     
     
     
    var summary: AdBlockPublicationSummary? = nil
     
     
    var actionFailure: AuthoredText? = nil

    /// What each `generic` script answered the last time it was run, keyed by
    /// the body hash the row's button carries.
    ///
    /// These scripts exist to tell the user something — a node's country, its
    /// unlock status — and Loon hands that answer back to the entry point that
    /// started them. A run whose answer went only to the log would leave the
    /// button looking like it did nothing, which is exactly the complaint this
    /// feature exists to avoid.
    var scriptResults: [String: ScriptResult] = [:]
     
    var actionModuleID: String? = nil
     
     
    var certificateFailure: AuthoredText? = nil
     
    var isConnected = false
    var isBusy = false
}

 
 
 
 
 
enum AdBlockPageSnapshotBuilder {
     
     
    static func page(_ facts: AdBlockPageFacts, locale: Locale) -> ClashAdBlockSnapshot {
         
         
         
         
        let decryption = decryption(facts)
        let rows = facts.state.modules.map { record in
             
            let ir = facts.modules[record.id]
            let lines = ir.flatMap { AdBlockModuleDetailBuilder.writtenLines(facts.sources[record.id], of: $0) }
            return row(record, ir: ir.map {
                AdBlockModuleDetailBuilder.published($0, record: record, publication: facts.summary, written: lines)
            }, locale: locale, decryption: decryption, written: lines)
        }
        let install = install(facts)
        guard facts.state.enabled else {
             
             
             
             
             
            return ClashAdBlockSnapshot(isOn: false, isBusy: facts.isBusy,
                                        certificate: install == nil ? nil : certificate(facts, locale: locale), install: install,
                                        notices: notices(facts, decryptionOn: false, locale: locale), modules: rows)
        }
        return ClashAdBlockSnapshot(isOn: true, isBusy: facts.isBusy, certificate: certificate(facts, locale: locale),
                                    install: install, notices: notices(facts, decryptionOn: true, locale: locale), modules: rows)
    }

     
     
    static func wantsDecryption(_ facts: AdBlockPageFacts) -> Bool {
        facts.state.modules.contains { record in
            record.enabled && facts.modules[record.id]?.mitmHostLines.contains { $0.entries.contains { !$0.excluded } } == true
        }
    }

     
     
     
     
     
     
    static func install(_ facts: AdBlockPageFacts) -> ClashAdBlockSnapshot.Install? {
        guard facts.platform == .ios, !facts.certificateUnreadable, facts.certificate != .ready, wantsDecryption(facts) else {
            return nil
        }
        return ClashAdBlockSnapshot.Install(action: installAction(facts.certificate),
                                            effect: AdBlockCertificateCopy.profileDescription.displayText)
    }

     
     
     
    static func installAction(_ state: AdBlockCertificateState) -> ClashAdBlockSnapshot.CertificateAction {
        let shown: AdBlockCertificateState = state == .notGenerated ? .notInstalled : state
        return .init(kind: .installProfile, title: AdBlockCertificateCopy.action(shown, platform: .ios).displayText)
    }

     
     
     
     
     
     
     
     
     
    static func decryption(_ facts: AdBlockPageFacts) -> AdBlockModuleDetailBuilder.Decryption {
        guard facts.state.enabled else { return .off }
        if facts.certificateUnreadable || facts.certificate != .ready { return .notReady(.certificate) }
        if let summary = facts.summary {
            if summary.notApplied != nil { return .notReady(.unavailable) }
            for reason in summary.reasons where kind(of: reason) == .decryption {
                return reason == .portsTaken ? .notReady(.preparing) : .notReady(.unavailable)
            }
             
             
            if !summary.engineInjected { return .notReady(.preparing) }
        }
        if facts.isConnected, let report = facts.report {
            switch report.state {
            case .starting: return .notReady(.preparing)
            case .passThrough, .failed: return .notReady(.unavailable)
            case .running:
                if report.rung == .engineStopped { return .notReady(.unavailable) }
                if case .certificateUnreadable? = report.failure { return .notReady(.unavailable) }
            case .stopped:
                break  
            }
        }
        return .working
    }

     
     
    static func entry(_ facts: AdBlockPageFacts) -> ClashAdBlockEntrySnapshot {
        ClashAdBlockEntrySnapshot(decryptionOn: facts.state.enabled, certificateReady: facts.certificate == .ready,
                                  enabledModules: facts.state.modules.filter(\.enabled).count)
    }

     
     
    static func state(_ facts: AdBlockPageFacts) -> ClashAdBlockSnapshot.CertificateState {
        facts.certificateUnreadable ? .unreadable : state(facts.certificate)
    }

    static func state(_ state: AdBlockCertificateState) -> ClashAdBlockSnapshot.CertificateState {
        switch state {
        case .notGenerated: return .notGenerated
        case .notInstalled: return .notInstalled
        case .installedNotTrusted: return .installedNotTrusted
        case .ready: return .ready
        }
    }

     

     
     
     
     
     
     
     
    static func certificate(_ facts: AdBlockPageFacts) -> ClashAdBlockSnapshot.Certificate {
        certificate(facts, locale: nil)
    }

     
     
     
     
    static func certificate(_ facts: AdBlockPageFacts, locale: Locale?) -> ClashAdBlockSnapshot.Certificate {
        let state = facts.certificate
        let platform = certificatePlatform(facts.platform)
        var note: AuthoredText?
        var action: ClashAdBlockSnapshot.CertificateAction?
        func act(_ kind: ClashAdBlockSnapshot.CertificateActionKind, _ title: AuthoredText) {
            action = ClashAdBlockSnapshot.CertificateAction(kind: kind, title: title.displayText)
        }
         
         
        var stepsFor = state
        switch (state, platform) {
        case (.ready, _):
            act(.makeNew, AdBlockCertificateCopy.action(state, platform: platform))
        case (.notGenerated, .mac):
            act(.create, AdBlockCertificateCopy.action(state, platform: platform))
        case (.notGenerated, .ios), (.notInstalled, .ios), (.installedNotTrusted, .ios):
            action = installAction(state)
            if state == .notGenerated { stepsFor = .notInstalled }
        case (.notInstalled, .mac), (.installedNotTrusted, .mac):
             
             
             
            if facts.keychainFallback != nil {
                act(.openInKeychainAccess, AdBlockCertificateCopy.openInKeychainAccess)
            } else {
                act(.installAndTrust, AdBlockCertificateCopy.action(state, platform: platform))
            }
        }
        if facts.certificateUnreadable {
             
             
             
             
            note = Copy.certificateUnreadable
            act(.makeNew, AdBlockCertificateCopy.action(.ready, platform: platform))
        }
        if note == nil, !facts.isBusy, let old = facts.oldCertificateLeft {
             
             
             
             
            note = AdBlockCertificateCopy.deleteOldCertificate(old)
        }
        if let failure = facts.certificateFailure { note = failure }
        let stepped = action.map(\.kind).map(namedByStepOne) == true
        let name = facts.certificateName, fallback = facts.keychainFallback
        return ClashAdBlockSnapshot.Certificate(
            state: Self.state(facts),
            steps: !stepped ? [] : locale.map {
                AdBlockCertificateCopy.steps(stepsFor, platform: platform, certificate: name, fallback: fallback, resolvedIn: $0)
            } ?? steps(stepsFor, platform: platform, certificate: name, fallback: fallback),
            note: note?.displayText,
            action: action,
            renewWarning: AdBlockCertificateCopy.regenerateWarning(platform: platform).displayText)
    }

     
     
     
     
     
    static func steps(_ state: AdBlockCertificateState, platform: AdBlockCertificatePlatform, certificate name: String? = nil,
                      fallback: AdBlockKeychainFallback? = nil) -> [ClashDisplayText] {
        AdBlockCertificateCopy.steps(state, platform: platform, certificate: name, fallback: fallback)
    }

     
     
     
    static func certificatePlatform(_ platform: AdBlockPlatform) -> AdBlockCertificatePlatform {
        switch platform {
        case .mac: return .mac
        case .ios, .tvos: return .ios
        }
    }

     
     
     
    static func namedByStepOne(_ kind: ClashAdBlockSnapshot.CertificateActionKind) -> Bool {
        switch kind {
        case .installProfile, .openInKeychainAccess: return true
        case .create, .installAndTrust, .makeNew: return false
        }
    }

     

     
     
     
    enum NoticeKind: Equatable {
        case modules
        case decryption
    }

     
     
     
     
    static func kind(of reason: AdBlockDegradeReason) -> NoticeKind? {
        switch reason {
        case .certificateNotTrusted, .certificateMissing:
            return nil  
        case .certificateUnusable, .stoppedForMemory:
             
             
            return .decryption
        case .noCertificateAddress:
             
             
             
            return nil
        case .moduleRulesLeftOut, .moduleEntriesLeftOut, .moduleSettingsLeftOut, .notApplied:
            return .modules
        case .engineUnavailable, .portsTaken, .groupsNotAdjustable, .sectionNotAdjustable, .alreadyPublished, .engineNameTaken:
            return .decryption
        }
    }

     
     
     
     
     
     
     
     
    static func notices(_ facts: AdBlockPageFacts, decryptionOn: Bool, locale: Locale) -> [ClashAdBlockSnapshot.Notice] {
        var out: [ClashAdBlockSnapshot.Notice] = []
        var said: [AuthoredText: Int] = [:]
        func add(_ kind: NoticeKind, _ id: String, _ text: AuthoredText, action: ClashAdBlockSnapshot.NoticeAction? = nil) {
            guard decryptionOn || kind == .modules else { return }
            if let index = said[text] {
                 
                 
                if out[index].action == nil, let action {
                    out[index].action = action
                    out[index].actionTitle = title(for: action)
                }
                return
            }
            said[text] = out.count
            out.append(.init(id: id, text: text.displayText, action: action, actionTitle: action.map(title(for:))))
        }
         
        if let failure = facts.actionFailure { add(.modules, "action", actionNotice(failure, facts, locale: locale)) }
        if let notApplied = facts.summary?.notApplied {
            add(.modules, "not-applied", AdBlockStoredSentence.current(notApplied))
        }
         
         
        var decrypting = false
        for reason in facts.summary?.reasons ?? [] {
            guard let about = kind(of: reason) else { continue }
            if about == .decryption {
                guard !decrypting else { continue }
                decrypting = true
            }
            add(about, "reason-" + reason.spelling, reason.authoredText, action: tryAgain(reason) ? .retryAfterMemoryStop : nil)
        }
         
         
         
        let insight = AdBlockEngineInsight.read(facts.isConnected ? facts.report : nil, platform: certificatePlatform(facts.platform))
        for (index, notice) in insight.notices.enumerated() {
            if tryAgain(notice, rung: insight.rung) {
                add(.decryption, "memory", notice, action: .retryAfterMemoryStop)
            } else {
                add(.decryption, "report-\(index)", notice)
            }
        }
         
        return out
    }

     
     
     
     
     
    static func tryAgain(_ reason: AdBlockDegradeReason) -> Bool {
        switch reason {
        case .stoppedForMemory, .engineUnavailable, .certificateUnusable:
            return true
        case .certificateNotTrusted, .certificateMissing, .portsTaken, .noCertificateAddress, .groupsNotAdjustable,
             .sectionNotAdjustable, .alreadyPublished, .moduleRulesLeftOut, .moduleEntriesLeftOut, .moduleSettingsLeftOut,
             .engineNameTaken, .notApplied:
            return false
        }
    }

     
     
     
     
    static func tryAgain(_ notice: AuthoredText, rung: AdBlockEngineReport.Rung) -> Bool {
        if rung == .engineStopped, notice == memoryStopNotice || notice == AdBlockDegradeReason.stoppedForMemory.authoredText {
            return true
        }
        return notice == AdBlockDegradeReason.certificateUnusable.authoredText
            || notice == AdBlockDegradeReason.engineUnavailable.authoredText
    }

     
     
     
    static func actionNotice(_ failure: AuthoredText, _ facts: AdBlockPageFacts, locale: Locale) -> AuthoredText {
        let failure = AdBlockStoredSentence.current(failure)
        if failure == AdBlockModuleStoreError.editSuperseded.authoredText,
           let record = facts.state.modules.first(where: { $0.id == facts.actionModuleID }) {
            return Copy.changedElsewhere(row(record, ir: nil, locale: locale).name)
        }
        return failure
    }

     
     
     
     
    static var memoryStopNotice: AuthoredText { AdBlockDegradeReason.stoppedForMemory.authoredText }

     
    static func title(for action: ClashAdBlockSnapshot.NoticeAction) -> ClashDisplayText {
        switch action {
        case .retryAfterMemoryStop: return "Try Again"
        case .runScriptAgain: return "Run Again"
        }
    }

     

     
     
     
     
     
     
     
     
     
     
     
    static func row(_ record: AdBlockModuleRecord, ir: AdBlockModuleIR?, locale: Locale,
                    decryption: AdBlockModuleDetailBuilder.Decryption = .working,
                    written: [Substring]? = nil) -> ClashAdBlockSnapshot.ModuleRow {
        let source: ClashAdBlockModuleSource
        var link: String?
        switch record.origin {
        case .url(let added):
            source = .link(URL(string: added)?.host ?? added)
             
            link = added
        case .local: source = .local
         
        case .unknown: source = .unknown
        }
        let name = record.name.isEmpty ? ClashCopy.string(for: Copy.untitledModule.displayText, locale: locale) : record.name
         
        let failed = record.lastFailure != nil || record.failureFromALaterBuild
        let failure: ClashDisplayText? = failed && source != .local ? "Update failed" : nil
        return ClashAdBlockSnapshot.ModuleRow(
            id: record.id, name: name, source: source, updatedAt: record.lastUpdatedAt,
            effectiveCount: ir.map {
                AdBlockModuleDetailBuilder.counts($0, decryption: decryption, written: written).shown(enabled: record.enabled)
            } ?? 0,
            ignoredCount: ir?.ignoredCount ?? 0, enabled: record.enabled,
            failure: failure, link: link)
    }

     

     
     
     
     
    enum Copy {
         
        static let untitledModule: AuthoredText = .app("Untitled Module")
         
         
        static let certificatePageUnavailable: AuthoredText = .app("The certificate page can't open right now; try again later.")
         
         
         
        static let certificateUnreadable: AuthoredText =
            .app("The certificate couldn't be read. Make a new one, then install and trust it again.")
         
         
        static func changedElsewhere(_ name: String) -> AuthoredText {
            .app("“%@” was just changed elsewhere; open it again.", arguments: [name])
        }
        static var every: [AuthoredText] {
            [untitledModule, certificatePageUnavailable, certificateUnreadable, changedElsewhere("Zhihu")]
        }
    }
}
#endif
