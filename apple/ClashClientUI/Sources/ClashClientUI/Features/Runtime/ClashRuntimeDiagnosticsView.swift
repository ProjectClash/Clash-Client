import Foundation
import SwiftUI

 
 
 
 
 
public struct ClashRuleEntryCounter: Sendable {
    public enum Kind: Sendable, Hashable {
        case geoIP
        case asn
         
         
         
        case ruleSet
    }

    public struct Key: Sendable, Hashable {
        public let kind: Kind
        public let value: String

        public init(kind: Kind, value: String) {
            self.kind = kind
            self.value = value
        }
    }

     
     
     
    public let count: @Sendable (Key) async -> Int?

    public init(count: @escaping @Sendable (Key) async -> Int?) {
        self.count = count
    }
}

public struct ClashRuntimeRule:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let type: String
    public let payload: String
    public let target: String
    public let size: Int?
     
     
     
    public let hitCount: UInt64?

    public init(
        type: String,
        payload: String,
        target: String,
        size: Int? = nil,
        hitCount: UInt64? = nil
    ) {
        self.type = type
        self.payload = payload
        self.target = target
        self.size = size
        self.hitCount = hitCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        payload = try container.decode(String.self, forKey: .payload)
        target = try container.decode(String.self, forKey: .target)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        hitCount = try container.decodeIfPresent(Extra.self, forKey: .extra)?.hitCount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(hitCount.map { Extra(hitCount: $0) }, forKey: .extra)
    }

    private struct Extra: Codable {
        let hitCount: UInt64?
    }

     
     
     
     
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && lhs.payload == rhs.payload && lhs.target == rhs.target
            && lhs.size == rhs.size && lhs.hitCount == rhs.hitCount
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var id: String {
        "\(type)|\(payload)|\(target)|\(size.map(String.init) ?? "")"
    }

    public var sizeText: String? {
        guard let size, size >= 0 else { return nil }
         
         
         
         
         
        if size == 0, ["geoip", "srcgeoip"].contains(type.lowercased()) { return nil }
        return "\(size)"
    }

     
     
     
     
     
    public var countedEntryKey: ClashRuleEntryCounter.Key? {
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        switch type.lowercased() {
        case "geoip", "srcgeoip":
            guard (size ?? 0) <= 0 else { return nil }
            return .init(kind: .geoIP, value: value)
        case "ipasn", "srcipasn":
            return .init(kind: .asn, value: value)
        case "ruleset":
            guard (size ?? 0) <= 0 else { return nil }
            return .init(kind: .ruleSet, value: payload.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

     
    public func entryText(counted: [ClashRuleEntryCounter.Key: Int]) -> String? {
        if let sizeText { return sizeText }
        guard let key = countedEntryKey, let count = counted[key] else { return nil }
        return "\(count)"
    }

    public var hitText: String? {
        hitCount.map { "\($0)" }
    }

    public func matches(_ query: String) -> Bool {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return true }
        return type.lowercased().contains(needle)
            || payload.lowercased().contains(needle)
            || target.lowercased().contains(needle)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
        case target = "proxy"
        case size
        case extra
    }
}

public enum ClashRuntimeRulesPayload {
    public static let maximumDocumentBytes = 4 * 1_024 * 1_024
    public static let maximumRuleCount = 4_096

    public static func decode(_ data: Data?) -> [ClashRuntimeRule] {
        guard let data,
              !data.isEmpty,
              data.count <= maximumDocumentBytes,
              let payload = try? JSONDecoder().decode(
                Payload.self,
                from: data
              )
        else {
            return []
        }
        return Array(payload.rules.prefix(maximumRuleCount))
    }

    private struct Payload: Decodable {
        let rules: [ClashRuntimeRule]
    }
}

public struct ClashActiveRulesView: View {
    private let rules: [ClashRuntimeRule]
     
     
    private let totalCount: Int?
     
     
    private let hits: [ClashRuntimeRule]
    private let isConnected: Bool
    private let isRefreshing: Bool
    private let refresh: @MainActor () async -> Void
    private let entryCounter: ClashRuleEntryCounter?
     
     
     
    private let ruleSetGeneration: Int

    @State private var query = ""
     
    @State private var counted: [ClashRuleEntryCounter.Key: Int] = [:]
     
    @State private var asked: Set<ClashRuleEntryCounter.Key> = []
     
     
    @State private var ruleSetPass = 0
    @Environment(\.locale) private var locale

    public init(
        rules: [ClashRuntimeRule],
        totalCount: Int? = nil,
        hits: [ClashRuntimeRule] = [],
        isConnected: Bool,
        isRefreshing: Bool = false,
        entryCounter: ClashRuleEntryCounter? = nil,
        ruleSetGeneration: Int = 0,
        refresh: @escaping @MainActor () async -> Void
    ) {
        let listed = Array(rules.prefix(ClashRuntimeRulesPayload.maximumRuleCount))
        self.rules = listed
        self.totalCount = totalCount.flatMap { $0 > listed.count ? $0 : nil }
        self.hits = Array(hits.prefix(ClashRuntimeRulesPayload.maximumRuleCount))
        self.isConnected = isConnected
        self.isRefreshing = isRefreshing
        self.entryCounter = entryCounter
        self.ruleSetGeneration = ruleSetGeneration
        self.refresh = refresh
    }

     
     
     
     
    private func countEntries() async {
        guard let entryCounter else { return }
        var pending: [ClashRuleEntryCounter.Key] = []
        var seen = asked
        for key in (rules + hits).lazy.compactMap(\.countedEntryKey) where seen.insert(key).inserted {
            pending.append(key)
        }
        for key in pending {
            guard !Task.isCancelled else { return }
             
             
             
             
             
            if key.kind != .ruleSet { asked.insert(key) }
            let pass = ruleSetPass
            let count = await entryCounter.count(key)
            if key.kind == .ruleSet {
                guard pass == ruleSetPass, !Task.isCancelled else { return }
                asked.insert(key)
            }
            if let count {
                counted[key] = count
            } else if key.kind == .ruleSet {
                 
                 
                counted[key] = nil
            }
        }
    }

     
     
     
    private func forgetRuleSetKeys() {
        ruleSetPass &+= 1
        asked = asked.filter { $0.kind != .ruleSet }
    }

    public var body: some View {
        List {
            if rules.isEmpty {
                Section {
                    HStack(spacing: ClashTheme.Spacing.row) {
                        Image(
                            systemName: ClashSymbol
                                .exclamationmarkTriangleFill
                                .rawValue
                        )
                        .foregroundStyle(.secondary)

                        Text(clash: .copy(Self.emptyMessage(isConnected: isConnected)))
                            .foregroundStyle(.secondary)

                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Text("Rules")
                        Spacer()
                        Text("\(filteredRules.count) / \(rules.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } footer: {
                     
                     
                    if let totalCount {
                        Text(clash: .format("The first %@ of %@ rules.", [
                            ClashCopy.count(rules.count, locale: locale),
                            ClashCopy.count(totalCount, locale: locale),
                        ]))
                    }
                }

                Section {
                    ForEach(
                        Array(filteredRules.enumerated()),
                        id: \.offset
                    ) { _, rule in
                        ruleRow(rule)
                    }
                }

                if totalCount != nil {
                    Section {
                        if filteredHits.isEmpty {
                            Group {
                                if hits.isEmpty {
                                    Text("Rules appear here once they match traffic.")
                                } else {
                                    Text("No matching rules")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(filteredHits.enumerated()), id: \.offset) { _, rule in
                                ruleRow(rule)
                            }
                        }
                    } header: {
                        Text("Matched So Far")
                    }
                    .accessibilityIdentifier("runtime.active-rules.hits")
                }
            }
        }
        .searchable(text: $query, prompt: "Search active rules")
        .clashBottomSearchClearance()
        .clashPageTitle("Active Rules")
        .task {
            await refresh()
        }
         
         
         
         
         
        .task(id: rules + hits) {
            await countEntries()
        }
         
         
        .task(id: ruleSetGeneration) {
            guard ruleSetGeneration > 0 else { return }
            forgetRuleSetKeys()
            await countEntries()
        }
        .refreshable {
            await refreshAgain()
        }
#if os(macOS)
         
         
         
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refreshAgain() } } label: { Text("Refresh") }
                    .disabled(isRefreshing)
                    .accessibilityIdentifier("runtime.active-rules.refresh")
            }
        }
#endif
        .accessibilityIdentifier("runtime.active-rules.list")
    }

     
     
     
     
    private func refreshAgain() async {
        await refresh()
        ruleSetPass &+= 1
        asked = Set(counted.keys.filter { $0.kind != .ruleSet })
        await countEntries()
    }

    private var filteredRules: [ClashRuntimeRule] {
        rules.filter { $0.matches(query) }
    }

    private var filteredHits: [ClashRuntimeRule] {
        hits.filter { $0.matches(query) }
    }

    private func ruleRow(_ rule: ClashRuntimeRule) -> some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            HStack {
                Text(rule.type)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(rule.target)
                    .font(.caption.weight(.semibold))
            }

            Text(rule.payload.isEmpty ? "—" : rule.payload)
                .font(.callout)
                .clashTextSelectionEnabled()

             
             
             
            let entryText = rule.entryText(counted: counted)
            if entryText != nil || rule.hitText != nil {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    if let entryText {
                        Text("Entries: \(entryText)")
                    }
                    if let hitText = rule.hitText {
                        Text("Hits: \(hitText)")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
    }

     
     
    public static func emptyMessage(isConnected: Bool) -> String {
#if os(macOS)
        isConnected ? "Couldn't read the rules in use. Click Refresh to try again."
            : "Not connected, so the rules in use can't be read. Connect, then click Refresh."
#else
        isConnected ? "No active rules were returned. Pull to refresh." : "Connect Clash, then pull to refresh."
#endif
    }
}

public struct ClashDNSQueryAnswer:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let name: String?
    public let type: Int?
    public let ttl: Int?
    public let data: String?

    public init(
        name: String?,
        type: Int?,
        ttl: Int?,
        data: String?
    ) {
        self.name = name
        self.type = type
        self.ttl = ttl
        self.data = data
    }

    public var id: String {
        "\(name ?? "")|\(type ?? 0)|\(data ?? "")|\(ttl ?? 0)"
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case ttl = "TTL"
        case data
    }
}

public struct ClashDNSQueryResult: Equatable, Sendable {
    public static let maximumRawResponseBytes = 128 * 1_024
    public static let maximumAnswerCount = 128

    public let answers: [ClashDNSQueryAnswer]
    public let rawResponse: String?
    public let errorMessage: String?

    public init(
        rawResponse: String?,
        errorMessage: String?
    ) {
        let boundedRawResponse = rawResponse.flatMap { value in
            value.utf8.count <= Self.maximumRawResponseBytes
                ? value
                : nil
        }
        self.rawResponse = boundedRawResponse
        self.errorMessage =
            errorMessage
            ?? (
                rawResponse != nil && boundedRawResponse == nil
                    ? "The DNS response exceeded the safe display limit."
                    : nil
            )
        self.answers = Self.decodeAnswers(boundedRawResponse)
    }

    public init(
        answers: [ClashDNSQueryAnswer],
        rawResponse: String? = nil,
        errorMessage: String? = nil
    ) {
        self.answers = Array(answers.prefix(Self.maximumAnswerCount))
        self.rawResponse = rawResponse
        self.errorMessage = errorMessage
    }

    private static func decodeAnswers(
        _ rawResponse: String?
    ) -> [ClashDNSQueryAnswer] {
        guard let rawResponse,
              let data = rawResponse.data(using: .utf8),
              data.count <= maximumRawResponseBytes,
              let response = try? JSONDecoder().decode(
                Response.self,
                from: data
              )
        else {
            return []
        }
        return Array(
            (response.answer ?? []).prefix(maximumAnswerCount)
        )
    }

    private struct Response: Decodable {
        let answer: [ClashDNSQueryAnswer]?

        private enum CodingKeys: String, CodingKey {
            case answer = "Answer"
        }
    }
}

public enum ClashDNSCacheMaintenanceAction:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case dns
    case fakeIP

    public var id: Self { self }

    public var buttonTitle: String {
        switch self {
        case .dns:
            "Flush DNS Cache"
        case .fakeIP:
            "Flush Fake-IP Cache"
        }
    }

    public var confirmationTitle: String {
        switch self {
        case .dns:
            "Clear the DNS cache?"
        case .fakeIP:
            "Clear the Fake-IP cache?"
        }
    }

    public var successMessage: String {
        switch self {
        case .dns:
            "DNS cache cleared."
        case .fakeIP:
            "Fake-IP cache cleared."
        }
    }
}

 
 
 
 
 
 
 
public struct ClashDNSResolution: Equatable, Sendable {
     
     
     
     
     
     
     
     
    public enum AnswerSource: Equatable, Sendable {
         
         
         
        case systemResolver
         
        case core
    }

    public let result: ClashDNSQueryResult
    public let answerSource: AnswerSource
     
    public let explain: ClashDNSExplain?

    public init(
        result: ClashDNSQueryResult,
        answerSource: AnswerSource,
        explain: ClashDNSExplain? = nil
    ) {
        self.result = result
        self.answerSource = answerSource
        self.explain = explain
    }
}

public struct ClashDNSQueryCapabilities {
    public typealias Query = @MainActor (
        String,
        String
    ) async -> ClashDNSResolution
    public typealias Maintain = @MainActor (
        ClashDNSCacheMaintenanceAction
    ) async -> String?

    public static let recordTypes = [
        "A",
        "AAAA",
        "CNAME",
        "TXT",
        "MX",
        "NS",
        "SRV",
        "PTR",
    ]

     
     
     
     
     
     
     
     
     
     
    public typealias Explain = @MainActor (
        String,
        String
    ) async -> ClashDNSExplain?

    public let query: Query
    public let explain: Explain?
    public let maintain: Maintain

    public init(
        query: @escaping Query,
        explain: Explain? = nil,
        maintain: @escaping Maintain
    ) {
        self.query = query
        self.explain = explain
        self.maintain = maintain
    }
}

public struct ClashDNSQueryView: View {
    private let isConnected: Bool
    private let capabilities: ClashDNSQueryCapabilities

    @State private var name = ""
    @State private var type = "A"
    @State private var result: ClashDNSQueryResult?
    @State private var explain: ClashDNSExplain?
    @State private var answerSource: ClashDNSResolution.AnswerSource?
    @State private var isQuerying = false
    @State private var pendingMaintenance:
        ClashDNSCacheMaintenanceAction?
    @State private var isMaintainingCache = false
    @State private var maintenanceResult: String?

    public init(
        isConnected: Bool,
        capabilities: ClashDNSQueryCapabilities
    ) {
        self.isConnected = isConnected
        self.capabilities = capabilities
    }

    public var body: some View {
        List {
            Section {
                 
                 
                 
                 
                TextField(
                    "",
                    text: $name,
                    prompt: Text(verbatim: "example.com")
                )
                    .labelsHidden()
                    .clashDNSNameEntryBehavior()
                    .accessibilityIdentifier(
                        "runtime.dns-query.name"
                    )

                Picker("Type", selection: $type) {
                    ForEach(
                        ClashDNSQueryCapabilities.recordTypes,
                        id: \.self
                    ) {
                        Text($0).tag($0)
                    }
                }
                    .accessibilityIdentifier("diagnostics.runtime.type")

                Button {
                    Task {
                        await runQuery()
                    }
                } label: {
                    HStack {
                        Label(
                            "Query",
                            systemImage: ClashSymbol
                                .globeAsiaAustralia
                                .rawValue
                        )
                        if isQuerying {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(
                    !isConnected
                        || normalizedName.isEmpty
                        || isQuerying
                )
                .accessibilityIdentifier(
                    "runtime.dns-query.run"
                )
            } footer: {
                Text(
                    "A and AAAA take the same path your traffic takes, so Local Mappings and Fake-IP appear here as they do in use. Other record types are asked of the core's resolvers, honoring nameserver-policy. Read-only."
                )
            }

             
             
             
             
             
            if let explain {
                explainSection(explain, answerSource: answerSource)
            }

            if let result {
                resultSections(result)
            }

            Section {
                ForEach(
                    ClashDNSCacheMaintenanceAction.allCases
                ) { action in
                    Button(role: .destructive) {
                        pendingMaintenance = action
                    } label: {
                        Label {
                            Text(clash: .copy(action.buttonTitle))
                        } icon: {
                            Image(systemName: ClashSymbol.trash.rawValue)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.red)
                    }
                    .disabled(
                        !isConnected || isMaintainingCache
                    )
                    .accessibilityIdentifier(
                        action == .dns
                            ? "dns-query.cache.flush-dns"
                            : "dns-query.cache.flush-fakeip"
                    )
                }

                if isMaintainingCache {
                    HStack {
                        ProgressView()
                        Text("Clearing cache…")
                            .foregroundStyle(.secondary)
                    }
                } else if let maintenanceResult {
                    Text(clash: .copy(maintenanceResult))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "dns-query.cache.result"
                        )
                }
            } header: {
                Text("DNS Cache Maintenance")
            } footer: {
                Text(
                    "Clear these caches only after DNS changes or when a stale answer persists. The tunnel stays connected."
                )
            }
        }
        .clashRuntimeGroupedFormStyle()
        .clashPageTitle("DNS Query")
        .confirmationDialog(
            pendingMaintenance?.confirmationTitle
                ?? "Clear DNS cache?",
            isPresented: Binding(
                get: { pendingMaintenance != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingMaintenance = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingMaintenance {
                Button(role: .destructive) {
                    let action = pendingMaintenance
                    self.pendingMaintenance = nil
                    Task {
                        await performMaintenance(action)
                    }
                } label: {
                    Text(clash: .copy(pendingMaintenance.buttonTitle))
                }
                .accessibilityIdentifier(
                    "dns-query.cache.confirm"
                )
            }

            Button("Cancel", role: .cancel) {
                pendingMaintenance = nil
            }
            .accessibilityIdentifier(
                "dns-query.cache.cancel"
            )
        } message: {
            Text(
                "This removes cached answers from the running core. It does not disconnect the tunnel or change the profile."
            )
        }
        .accessibilityIdentifier("runtime.dns-query.form")
    }

    @ViewBuilder
    private func explainSection(
        _ explain: ClashDNSExplain,
        answerSource: ClashDNSResolution.AnswerSource?
    ) -> some View {
        Section {
            explainRow(
                "Rule",
                explain.reason,
                identifier: "runtime.dns-query.explain.reason"
            )

            if !explain.candidates.isEmpty {
                explainRow(
                    "Resolvers",
                     
                     
                    .verbatim(explain.candidates.joined(separator: "\n")),
                    monospaced: true,
                    identifier: "runtime.dns-query.explain.candidates"
                )
            }

            if let cache = explain.cacheSentence(durationText: Self.duration) {
                explainRow(
                    "Cache",
                    cache,
                    identifier: "runtime.dns-query.explain.cache"
                )
            }
        } header: {
            Text(clash: "Route")
        } footer: {
             
             
             
             
            if answerSource == .systemResolver {
                Text(
                    clash:
                        "A and AAAA are answered by the system resolver, so no single upstream can be credited for the address below."
                )
            }
        }
    }

     
     
     
     
     
     
    private func explainRow(
        _ title: ClashDisplayText,
        _ value: ClashDisplayText,
        monospaced: Bool = false,
        identifier: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            Text(clash: title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(clash: value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

     
     
     
     
     
     
     
     
     
     
     
    static func readableFailure(_ raw: String) -> ClashDisplayText {
        let lowered = raw.lowercased()
        if lowered.contains("deadline exceeded")
            || lowered.contains("timeout")
            || lowered.contains("timed out")
        {
            return .copy(
                "No resolver answered in time. The record type may not exist for this name, or the resolvers are unreachable right now."
            )
        }
        if lowered.contains("invalid query type") {
            return .copy("This core does not recognise that record type.")
        }
        if lowered.contains("dns is not running") {
            return .copy(
                "DNS is switched off in this configuration, so there is nothing to ask."
            )
        }
        if lowered.contains("no address was returned") {
            return .verbatim(raw)
        }
        return .copy("The query did not complete.")
    }

     
     
     
     
    static func duration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 60 ? [.minute] : [.second]
        formatter.maximumUnitCount = 1
        return formatter.string(from: TimeInterval(max(seconds, 1)))
            ?? "\(seconds)"
    }

    @ViewBuilder
    private func resultSections(
        _ result: ClashDNSQueryResult
    ) -> some View {
        if let errorMessage = result.errorMessage,
           !errorMessage.isEmpty
        {
            Section("Query Error") {
                Text(clash: Self.readableFailure(errorMessage))
                    .foregroundStyle(.secondary)
                 
                 
                 
                Text(clash: .verbatim(errorMessage))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .clashTextSelectionEnabled()
            }
        } else if !result.answers.isEmpty {
            Section("Answers") {
                ForEach(result.answers) { answer in
                    VStack(
                        alignment: .leading,
                        spacing: ClashTheme.Spacing.tight
                    ) {
                        Text(answer.data ?? "—")
                            .font(.callout.monospaced())
                            .clashTextSelectionEnabled()
                        if let ttl = answer.ttl {
                            Text("TTL \(ttl)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                 
                 
                 
                if let attribution = explain?.attributionSentence {
                    Text(clash: attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "runtime.dns-query.answered-by"
                        )
                }
            }
        } else if let rawResponse = result.rawResponse {
            Section("Raw Response") {
                Text(rawResponse)
                    .font(.caption.monospaced())
                    .clashTextSelectionEnabled()
            }
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func runQuery() async {
        guard !normalizedName.isEmpty else { return }
        isQuerying = true
         
         
         
         
         
         
         
         
         
         
         
        defer { isQuerying = false }
         
         
        result = nil
        explain = nil
        answerSource = nil

         
         
         
         
         
        if let explainer = capabilities.explain {
            explain = await explainer(normalizedName, type)
        }

        let answer = await capabilities.query(normalizedName, type)
        result = answer.result
        answerSource = answer.answerSource

         
         
         
         
         
        if let produced = answer.explain {
            explain = produced
        }
    }

    private func performMaintenance(
        _ action: ClashDNSCacheMaintenanceAction
    ) async {
        isMaintainingCache = true
        maintenanceResult = nil
        let error = await capabilities.maintain(action)
        maintenanceResult = error.map {
            "Couldn’t clear the cache: \($0)"
        } ?? action.successMessage
        isMaintainingCache = false
    }
}

private extension View {
    @ViewBuilder
    func clashDNSNameEntryBehavior() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func clashRuntimeGroupedFormStyle() -> some View {
        if #available(iOS 16.0, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }
}
