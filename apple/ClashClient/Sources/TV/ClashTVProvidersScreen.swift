import SwiftUI
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVProvidersScreen: View {
    @Binding var state: ClashTVProductState

    @State private var explainedID: String?


    var body: some View {
        let rows = Self.rows(state.providers, tunnel: state.providerRefresh, running: state.isConnected,
                             compileFailures: state.pendingCompileFailures)
        HStack(alignment: .top, spacing: 56) {
            List {
                if let vacancy = Self.vacancy(state.providers) {
                    Text(vacancy).foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.entry.id) { row in
                    Button {} label: {
                         
                         
                         
                         
                        HStack(spacing: 20) {
                            Text(Self.kindWord(for: row.entry))
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .frame(minWidth: 90, alignment: .leading)
                            Text(row.entry.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 20)
                            Text(row.line.label)
                                .foregroundStyle(Self.style(row.line.tone))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .onClashTVFocus { explainedID = row.entry.id }
                    .accessibilityIdentifier("tvos.providers.\(row.entry.id)")
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                if let row = rows.first(where: { $0.entry.id == explainedID }) ?? rows.first {
                    Text(Self.kindWord(for: row.entry))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(row.entry.name)
                        .font(.title2)
                    Text(row.line.text)
                        .font(.title3)
                        .foregroundStyle(Self.style(row.line.tone))
                    if let time = row.time {
                        Text(time)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: explainedID)
        }
         
    }

     
     
     
    static func style(_ tone: Line.Tone) -> AnyShapeStyle {
        tone == .failure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
    }

     

     
    struct Line: Equatable {
        enum Tone: Equatable { case ready, information, failure }
         
        let text: String
        let tone: Tone
         
         
        var label: String

        init(text: String, tone: Tone, label: String? = nil) {
            self.text = text
            self.tone = tone
            self.label = label ?? text
        }
    }

    struct Row: Equatable {
        let entry: ClashTVProviderCatalog.Entry
        let line: Line
         
         
        let time: String?
    }

     
     
     
    static func rows(_ entries: [ClashTVProviderCatalog.Entry], tunnel: ProviderRefreshState?, running: Bool,
                     compileFailures: [String: String] = [:], now: Date = Date()) -> [Row] {
        entries.map { entry in
            Row(entry: entry, line: line(for: entry, tunnel: tunnel, running: running, compileFailures: compileFailures),
                time: time(for: entry, tunnel: tunnel, running: running, now: now))
        }.sorted { left, right in
            let leftBroken = left.line.tone == .failure
            let rightBroken = right.line.tone == .failure
            if leftBroken != rightBroken { return leftBroken }
            return left.entry.id < right.entry.id
        }
    }

     
     
     
    static func record(for entry: ClashTVProviderCatalog.Entry,
                       in tunnel: ProviderRefreshState?) -> ProviderRefreshState.Entry? {
        guard let tunnel else { return nil }
        let found: ProviderRefreshState.Entry?
        if let url = entry.url {
            found = tunnel.entry(kind: entry.kind, name: entry.name, url: url)
        } else {
             
            found = tunnel.requestKey(kind: entry.kind, name: entry.name)
                .flatMap { tunnel.entries[$0] }.flatMap { $0.kind == entry.kind ? $0 : nil }
        }
        guard let record = found, record.result != nil, record.result != .scheduled else { return nil }
         
         
         
        if let own = entry.updatedAt, let attempt = record.lastAttemptAt ?? record.lastCheckedAt,
           attempt < Int64(own.timeIntervalSince1970.rounded(.down)) { return nil }
        return record
    }

     
     
     
     
     
    static func line(for entry: ClashTVProviderCatalog.Entry, tunnel: ProviderRefreshState?, running: Bool,
                     compileFailures: [String: String] = [:]) -> Line {
        if entry.note == .inline {
            return Line(text: String(localized: "Ready"), tone: .ready)
        }
        if let record = record(for: entry, in: tunnel), let tunnel {
             
             
             
            let appCanFetch = record.waitReason == "routes" || record.waitReason == "recompile"
            let said = tunnel.displayLine(kind: entry.kind, name: entry.name, record, appCanFetch: appCanFetch)
            switch record.result {
            case .failed?:
                return Line(text: Self.updateFailed(record.error).text, tone: .failure, label: String(localized: "Failed"))
            case .pendingApp?:
                 
                 
                 
                if let failure = compileFailures[ProviderRefreshState.key(kind: entry.kind, name: entry.name)] {
                    return Line(text: Self.updateFailed(failure.isEmpty ? nil : failure).text, tone: .failure,
                                label: String(localized: "Failed"))
                }
                if let said {
                    let sentence = AuthoredText.app(said.key, arguments: said.arguments).text
                     
                     
                    let label = switch tunnel.pendingTaker(kind: entry.kind, name: entry.name, reason: record.waitReason,
                                                           appCanFetch: appCanFetch) {
                     
                    case .tunnelRetries where record.countBefore == 0: String(localized: "Not loaded yet")
                    case .tunnelRetries, .tunnelKeepsOld: String(localized: "Using the saved copy")
                    case .appWhenOpen, .appWhenAsked: sentence
                    }
                    return Line(text: sentence, tone: .information, label: label)
                }
                 
                 
                 
                 
                 
                 
                return Line(text: String(localized: "Updating…"), tone: .information)
            case .updated? where record.countAfter == 0 && (record.countBefore ?? 0) > 0:
                if let said {
                    return Line(text: AuthoredText.app(said.key, arguments: said.arguments).text, tone: .information,
                                label: String(localized: "Now empty"))
                }
            default: break
            }
            return Line(text: String(localized: "Ready"), tone: .ready)
        }
        guard let note = entry.note else { return Line(text: String(localized: "Ready"), tone: .ready) }
        switch note {
        case .downloadFailed, .unreadable:
            return Line(text: note.text, tone: .failure, label: String(localized: "Failed"))
        case .tunnelFetches, .fetchedByCore:
             
            return Line(text: running ? String(localized: "Not downloaded yet") : note.text, tone: .information)
        case .inline:
            return Line(text: note.text, tone: .ready)
        }
    }

     
     
    static func resultLine(_ name: String, _ sentence: String) -> String {
        AuthoredText.app("%1$@: %2$@", arguments: [name, sentence]).text
    }

    enum Failure { case update, download }

     
     
     
    static func failedLine(_ name: String, _ failure: Failure, reason: String?) -> String {
        switch (failure, reason) {
        case (.update, let reason?): AuthoredText.app("%1$@ update failed: %2$@", arguments: [name, reason]).text
        case (.update, nil): AuthoredText.app("%@ update failed", arguments: [name]).text
        case (.download, let reason?): AuthoredText.app("%1$@ download failed: %2$@", arguments: [name, reason]).text
        case (.download, nil): AuthoredText.app("%@ download failed", arguments: [name]).text
        }
    }

     
     
    static func updateFailed(_ reason: String?) -> AuthoredText {
        reason.map { .app("Update failed: %@", arguments: [$0]) } ?? .app("Update failed")
    }

     
     
     
     
    static func time(for entry: ClashTVProviderCatalog.Entry, tunnel: ProviderRefreshState?, running: Bool,
                     now: Date = Date()) -> String? {
        if entry.note == .inline { return nil }
        if case .unreadable? = entry.note, entry.url == nil { return nil }
        if let checked = record(for: entry, in: tunnel)?.checkedAt ?? entry.updatedAt {
            return ClashTVSubscriptionUpdatedWords.text(updatedAt: checked, now: now)
        }
        guard entry.note?.isFailure == true else { return nil }
        return running ? String(localized: "Not yet updated") : String(localized: "Retries when you connect")
    }

     
     
    static func kindWord(for entry: ClashTVProviderCatalog.Entry) -> String {
        entry.kind
    }

     
     
    static func readyCount(_ entries: [ClashTVProviderCatalog.Entry], tunnel: ProviderRefreshState?, running: Bool,
                           compileFailures: [String: String] = [:]) -> Int {
        entries.count { line(for: $0, tunnel: tunnel, running: running, compileFailures: compileFailures).tone == .ready }
    }

    static func vacancy(_ entries: [ClashTVProviderCatalog.Entry]) -> String? {
        entries.isEmpty ? String(localized: "This profile has no providers") : nil
    }
}
