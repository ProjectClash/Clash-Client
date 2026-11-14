import Combine
import Foundation
import Darwin
import ClashClientUI
import ClashClientKit
import os
import Clash
import NetworkExtension

 
 
 
 
 
 
 
private final class CoreCallRace<Value>: @unchecked Sendable {
    enum Outcome {
        case result(Result<Value, Error>)
        case deadline
        case cancelled
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var pending: Outcome?
    private var resolved = false

    func wait() async -> Outcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let pending {
                self.pending = nil
                lock.unlock()
                continuation.resume(returning: pending)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    @discardableResult
    func resolve(_ outcome: Outcome) -> Bool {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return false
        }
        resolved = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: outcome)
        } else {
            pending = outcome
            lock.unlock()
        }
        return true
    }
}

struct ClashTrafficSnapshot: Equatable {
    var upload: Int64 = 0
    var download: Int64 = 0
    var uploadTotal: Int64 = 0
    var downloadTotal: Int64 = 0
     
     
     
     
     
    var uploadHistory: [Int64] = Array(repeating: 0, count: 30)
    var downloadHistory: [Int64] = Array(repeating: 0, count: 30)
}

struct ClashTrafficReducer {
    private(set) var snapshot = ClashTrafficSnapshot()

    mutating func consume(up: Int64, down: Int64, upTotal: Int64, downTotal: Int64) -> ClashTrafficSnapshot {
         
         
         
        let upload = max(up, 0)
        let download = max(down, 0)

        func appending(_ value: Int64, to samples: [Int64]) -> [Int64] {
            var next = samples
            next.append(value)
            if next.count > 30 { next.removeFirst(next.count - 30) }
            return next
        }
        snapshot = ClashTrafficSnapshot(
            upload: upload,
            download: download,
            uploadTotal: upTotal,
            downloadTotal: downTotal,
            uploadHistory: appending(upload, to: snapshot.uploadHistory),
            downloadHistory: appending(download, to: snapshot.downloadHistory)
        )
        return snapshot
    }
}

struct ClashURLTestOutcome: Sendable {
    let delay: Int
    let failureCategory: String

    var succeeded: Bool { delay > 0 }
}

struct OOMEvidenceConsumeTracker {
    private(set) var lastProviderKey: String?

    mutating func beginAttempt(processIdentifier: Int32, startTimeUnix: Int64) -> Bool {
        guard processIdentifier > 0, startTimeUnix > 0 else { return false }
        let key = "\(processIdentifier):\(startTimeUnix)"
        guard key != lastProviderKey else { return false }
        lastProviderKey = key
        return true
    }
}

struct RuntimeRouteContext: Equatable, Sendable {
    let profileID: String
    let profileRevision: String
    let coreProcessIdentifier: Int32
    let coreStartTimeUnix: Int64
    let mode: String

    var generationKey: String {
        [
            profileID,
            profileRevision,
            String(coreProcessIdentifier),
            String(coreStartTimeUnix),
        ].joined(separator: "\u{001F}")
    }
}

 
 
enum ControlConnectFailureLogGate {
    static let repeatInterval: TimeInterval = 60
    static func shouldLog(_ message: String, after last: (message: String, at: Date)?, now: Date) -> Bool {
        guard let last else { return true }
        if last.message != message { return true }
        return now.timeIntervalSince(last.at) >= repeatInterval
    }
}

struct RuntimeRouteEvidence: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case runtimeControlConnected = "runtime-control-connected"
        case runtimeCoreConfirmed = "runtime-core-confirmed"
        case runtimeControlDisconnected = "runtime-control-disconnected"
        case modeRequested = "mode-requested"
        case modeConfirmed = "mode-confirmed"
        case modeRejected = "mode-rejected"
        case selectionRequested = "selection-requested"
        case selectionConfirmed = "selection-confirmed"
        case selectionRejected = "selection-rejected"
        case trafficRouteObserved = "traffic-route-observed"
        case observationsPaused = "observations-paused"
        case observationsResumed = "observations-resumed"
    }

    let schemaVersion: Int
    let kind: Kind
    let timestamp: Date
     
     
     
    let profilePointerID: String
    let profilePointerRevision: String
    let coreProcessIdentifier: Int32
    let coreStartTimeUnix: Int64
    let mode: String
    let connectionID: String
    let chains: [String]
    let rule: String
    let network: String
    let selectionGroup: String?
    let requestedMember: String?
    let confirmedMember: String?
    let resolvedMember: String?
    let failureCategory: String?
    let observationPauseID: String?
    let observationPauseStartedAt: Date?
    let observationPauseReason: ConnectionObservationPauseReason?

    init(
        kind: Kind,
        timestamp: Date = Date(),
        profilePointerID: String,
        profilePointerRevision: String,
        coreProcessIdentifier: Int32,
        coreStartTimeUnix: Int64,
        mode: String,
        connectionID: String = "",
        chains: [String] = [],
        rule: String = "",
        network: String = "",
        selectionGroup: String? = nil,
        requestedMember: String? = nil,
        confirmedMember: String? = nil,
        resolvedMember: String? = nil,
        failureCategory: String? = nil,
        observationPauseID: String? = nil,
        observationPauseStartedAt: Date? = nil,
        observationPauseReason: ConnectionObservationPauseReason? = nil
    ) {
        schemaVersion = 1
        self.kind = kind
        self.timestamp = timestamp
        self.profilePointerID = profilePointerID
        self.profilePointerRevision = profilePointerRevision
        self.coreProcessIdentifier = coreProcessIdentifier
        self.coreStartTimeUnix = coreStartTimeUnix
        self.mode = mode
        self.connectionID = connectionID
        self.chains = chains
        self.rule = rule
        self.network = network
        self.selectionGroup = selectionGroup
        self.requestedMember = requestedMember
        self.confirmedMember = confirmedMember
        self.resolvedMember = resolvedMember
        self.failureCategory = failureCategory
        self.observationPauseID = observationPauseID
        self.observationPauseStartedAt = observationPauseStartedAt
        self.observationPauseReason = observationPauseReason
    }

    func jsonLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(
            decoding: try encoder.encode(self),
            as: UTF8.self
        )
    }

    func logLine() throws -> String {
        "ROUTE_EVIDENCE \(try jsonLine())"
    }
}

final class RuntimeRouteEvidenceProjector {
    private static let maximumObservedRoutes = 2_048

    private var runtimeGenerationKey = ""
    private var observedRouteKeys: Set<String> = []
    private var observedRouteOrder: [String] = []

    func project(
        connections: [ClashConnection],
        context: RuntimeRouteContext,
        observedAt: Date = Date()
    ) -> [RuntimeRouteEvidence] {
        if runtimeGenerationKey != context.generationKey {
            runtimeGenerationKey = context.generationKey
            observedRouteKeys.removeAll(keepingCapacity: true)
            observedRouteOrder.removeAll(keepingCapacity: true)
        }

        var evidence: [RuntimeRouteEvidence] = []
        for connection in connections {
            let chains = connection.chains
                .map(Self.sanitize)
                .filter { !$0.isEmpty }
            guard !chains.isEmpty else { continue }
            let connectionID = Self.sanitize(connection.id)
            let rule = Self.sanitize(connection.rule)
            let network = Self.sanitize(connection.network)
            let routeKey = [
                connectionID,
                chains.joined(separator: "\u{001F}"),
                rule,
                network,
            ].joined(separator: "\u{001E}")
            guard observedRouteKeys.insert(routeKey).inserted else { continue }
            observedRouteOrder.append(routeKey)
            evidence.append(
                RuntimeRouteEvidence(
                    kind: .trafficRouteObserved,
                    timestamp: observedAt,
                    profilePointerID: Self.sanitize(context.profileID),
                    profilePointerRevision:
                        Self.sanitize(context.profileRevision),
                    coreProcessIdentifier: context.coreProcessIdentifier,
                    coreStartTimeUnix: context.coreStartTimeUnix,
                    mode: Self.sanitize(context.mode),
                    connectionID: connectionID,
                    chains: chains,
                    rule: rule,
                    network: network
                )
            )
        }

        if observedRouteOrder.count > Self.maximumObservedRoutes {
            let overflow =
                observedRouteOrder.count - Self.maximumObservedRoutes
            for key in observedRouteOrder.prefix(overflow) {
                observedRouteKeys.remove(key)
            }
            observedRouteOrder.removeFirst(overflow)
        }
        return evidence
    }

    private static func sanitize(_ value: String) -> String {
        let flattened = value.components(
            separatedBy: .controlCharacters
        ).joined(separator: " ")
        return String(flattened.prefix(256))
    }
}

actor RuntimeRouteEvidenceJournal {
    private let fileURL: URL?
    private let maximumBytes: Int

    init(fileURL: URL?, maximumBytes: Int = 2_000_000) {
        self.fileURL = fileURL
        self.maximumBytes = max(1_024, maximumBytes)
    }

    static func defaultFileURL() -> URL? {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "ClashRouteEvidence.jsonl",
            isDirectory: false
        )
    }

    func append(_ events: [RuntimeRouteEvidence]) throws {
        guard let fileURL, !events.isEmpty else { return }
        let lines = try events.map { try $0.jsonLine() }
        let payload = Data(
            (lines.joined(separator: "\n") + "\n").utf8
        )
        guard payload.count <= maximumBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let currentSize = (
            try? fileURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize
        ) ?? 0
        if currentSize + payload.count > maximumBytes {
            let rotatedURL = rotatedFileURL(for: fileURL)
            if FileManager.default.fileExists(atPath: rotatedURL.path) {
                try FileManager.default.removeItem(at: rotatedURL)
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.moveItem(
                    at: fileURL,
                    to: rotatedURL
                )
            }
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }
    }

    func recentLines(limit: Int) throws -> [String] {
        guard let fileURL, limit > 0 else { return [] }
        let urls = [rotatedFileURL(for: fileURL), fileURL]
        let lines = try urls.flatMap { url -> [String] in
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }
            let text = String(
                decoding: try Data(contentsOf: url),
                as: UTF8.self
            )
            return text.split(
                separator: "\n",
                omittingEmptySubsequences: true
            ).map(String.init)
        }
        return Array(lines.suffix(limit))
    }

    func clear() throws {
        guard let fileURL else { return }
        for url in [fileURL, rotatedFileURL(for: fileURL)]
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func rotatedFileURL(for url: URL) -> URL {
        url.appendingPathExtension("1")
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
@propertyWrapper
struct ClashMeteredValue<Value> {
    private let subject: CurrentValueSubject<Value, Never>
    private let publisher: AnyPublisher<Value, Never>
    private let isUnchanged: ((Value, Value) -> Bool)?

    init(wrappedValue: Value) {
        subject = CurrentValueSubject(wrappedValue)
        publisher = subject.eraseToAnyPublisher()
        isUnchanged = nil
    }

    init(wrappedValue: Value) where Value: Equatable {
        subject = CurrentValueSubject(wrappedValue)
        publisher = subject.eraseToAnyPublisher()
        isUnchanged = { $0 == $1 }
    }

     
     
     
     
     
     
     
    var wrappedValue: Value {
        get { subject.value }
        nonmutating set {
            if let isUnchanged, isUnchanged(subject.value, newValue) { return }
            subject.send(newValue)
        }
    }

    var projectedValue: AnyPublisher<Value, Never> { publisher }
}

extension ClashCommandClient {
     
     
     
     
    func clearLastError() {
        if !lastError.isEmpty { lastError = "" }
    }
}

extension ClashCommandClient {
     
     
     
    var logCountPublisher: AnyPublisher<Int, Never> { logCountStream }
}

@MainActor
final class ClashCommandClient: ObservableObject, ProxyShareCommanding {
    @Published private(set) var isConnected = false
     
     
     
     
     
    @Published private(set) var tunnelIsUp = false
     
     
     
     
    @Published private(set) var channelAttachFailed = false
    @Published private(set) var lastError = ""
     
     
    @ClashMeteredValue private(set) var traffic = ClashTrafficSnapshot() {
        didSet { if traffic != oldValue { ClashPerf.count("pub.cmd.traffic") } }
    }
     
     
     
     
     
     
     
     
     
     
     
     
    private(set) var trafficSampleCount = 0
    private(set) var uploadNonZeroSampleCount = 0
    private(set) var downloadNonZeroSampleCount = 0
    private(set) var peakUploadBytesPerSecond: Int64 = 0
    private(set) var peakDownloadBytesPerSecond: Int64 = 0
    private(set) var streamDisconnectCount = 0
     
     
     
    private var memoryState = MemoryState(inuse: 0, footprint: nil)
    private var isPublishingMemory = false
    private var lastMemorySequence: UInt64 = 0
    var memoryFootprintBytes: Int64 {
        guard let sample = memoryState.footprint,
              sample.generation == generation else { return 0 }
        let now = memoryNow()
        guard now >= sample.receivedAt,
              now - sample.receivedAt < 3_000_000_000 else { return 0 }
        return sample.bytes
    }
     
    @ClashMeteredValue private(set) var memoryBytes: Int64 = 0 {
        didSet { if memoryBytes != oldValue { ClashPerf.count("pub.cmd.memory") } }
    }
    @Published private(set) var mode = "—"
     
     
     
    @Published private(set) var runningListenerPorts: RunningListenerPorts?
    var runningListenerPortsChanges: AnyPublisher<RunningListenerPorts?, Never> {
        $runningListenerPorts.eraseToAnyPublisher()
    }
     
     
     
    private var configsRequests: UInt64 = 0
    private var listenersAdoptedFrom: UInt64 = 0

     
     
    func refreshRunningListenerPorts() async {
        guard let client else { return }
        let token = generation
        configsRequests &+= 1
        let request = configsRequests
        let modeWritesAtRequest = localModeWrites
        guard let configsJSON = try? await Task.detached(operation: { try Self.getConfigs(client) }).value,
              token == generation, self.client === client, isConnected else { return }
        applyConfigs(configsJSON, source: "configs-listeners", modeWritesAtRequest: modeWritesAtRequest,
                     request: request)
    }
    @Published private(set) var peerSchemaVersion: Int32 = 0
    @Published private(set) var peerCoreVersion = "—"
    @Published private(set) var peerCapabilities: [String] = []
    @Published private(set) var runtimeDiagnostics: ClashRuntimeDiagnostics?
     
    @Published private(set) var previousGoCrashReport: String?
    @Published private(set) var previousOOMEvidence: ClashOOMEvidence?
    @Published private(set) var proxiesData: Data?
     
     
     
     
    @Published private(set) var rules: [ClashRule] = []


     
     
    @Published private(set) var rulesTotal: Int?
     
     
    @Published private(set) var ruleHits: [ClashRule] = []
     
     
     
    @ClashMeteredValue private(set) var logs: [String] = []
     
    fileprivate lazy var logCountStream: AnyPublisher<Int, Never> = $logs
        .map(\.count)
        .removeDuplicates()
        .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
        .eraseToAnyPublisher()
    @Published private(set) var isCollectingMemory = false
    @Published private(set) var memoryActionMessage = ""

    private static let logMaxLines = 1_000
    private static let logBatchNanoseconds: UInt64 = 100_000_000

    private var client: ClashAPIClient?
     
     
     
    @Published private(set) var nodeSummary: NodeSummary?
     
     
    private var boundSession: NETunnelProviderSession?
     
     
     
     
     
    private var sessionProvider: (() -> NETunnelProviderSession?)?
    private var providerSession: NETunnelProviderSession? { sessionProvider?() ?? boundSession }
     
     
    private var lastConnectFailureLog: (message: String, at: Date)?
    private var clientHandler: HandlerProxy?
    private var connectTask: Task<Void, Never>?
    private var nativeConnectTask: Task<Void, Never>?
    private var nativeCleanup: Task<Void, Never>?
    private var connectionDiagnosticsLease: ConnectionDiagnosticLease?
    private enum DiagnosticScene { case active, inactive, background }
    private var diagnosticScene: DiagnosticScene = .background
    private let sceneManagedDiagnostics: Bool
     
     
     
     
     
     
     
     
     
     
     
     
     
    private let diagnosticsFollowLogRecording: Bool
     
     
    var connectionActivityDemanded = false {
        didSet {
            guard oldValue != connectionActivityDemanded else { return }
            reconcileConnectionDiagnostics()
        }
    }
    private var logRecordingObserver: NSObjectProtocol?
     
     
     
     
     
     
    private let separatesStatusStream: Bool
    private let statusClientFactory: StatusStreamClientFactory
    private var statusDemand = true
    private var statusClient: StatusStreamClient?
    private var statusEpoch: UInt64 = 0
     
     
    private var statusChain: Task<Void, Never>?
    private var statusGraceTask: Task<Void, Never>?
    private var statusRetryTask: Task<Void, Never>?
     
     
    private var statusBackoff = ClashReconnectBackoff()
     
     
    var statusCloseGraceNanoseconds: UInt64 = 3_000_000_000
    private var controlSocketPath: String?
    private let runtimeDiagnosticsReader: (() async throws -> ClashRuntimeDiagnostics)?
    private var observationEpoch: UInt64 = 0
    private var confirmedObservationEpoch: UInt64?
    private var runtimeDiagnosticsRequest: UInt64 = 0
    private var diagnosticsRequestInFlight = false
    private var scheduledDiagnosticsTask: Task<Void, Never>?
     
    private var diagnosticsBackoff = ClashReconnectBackoff()
    private var diagnosticPublication: ClashRuntimeDiagnostics?
    private var publishingDiagnostics = false
    private var logBatchTask: Task<Void, Never>?
     
     
     
     
     
     
     
    private var logDisplayLevel = ClashLogSettings.liveStreamLevel(
        from: GlobalConfig.appGroupDefaults
    )
     
     
     
     
     
     
    private var subscribedLogLevel: String? = "info"
    private var activeProfileLogLevelObserver: NSObjectProtocol?
    private var pendingLogs = ClashLogBuffer(maximumBytes: 256 * 1024, maximumCount: 1000)
    private var trafficReducer = ClashTrafficReducer()
    private let connectionRuntimeFeed: ConnectionRuntimeFeed
    private var routeEvidenceJournal: RuntimeRouteEvidenceJournal { connectionRuntimeFeed.routeJournal }
    private var lastConfirmedRuntimeEvidenceKey = ""
    private var runtimeConfirmedAt: UInt64 = 0
    private var generation: UInt64 = 0
     
    var pendingCompileFollowUp: Task<Void, Never>?
     
    private var pendingCompileAgain = false
     
     
    private var pendingCompileRun: UInt64 = 0
     
     
     
    private var pendingCompilesHandedOn: Set<String> = []
     
     
    var takesWhatTheCompileCouldNotTake: (@MainActor ([PendingProviderCompile.Held]) -> Void)?
    private var wantsConnection = false
    private var reconnectBackoff = ClashReconnectBackoff()
    private var isConnecting = false
    private var oomEvidenceConsumeTracker = OOMEvidenceConsumeTracker()
    private var uiTestProxyShareStatus = ProxyShareStatus.disabled



    deinit {
        if let activeProfileLogLevelObserver {
            NotificationCenter.default.removeObserver(activeProfileLogLevelObserver)
        }
        if let logRecordingObserver {
            NotificationCenter.default.removeObserver(logRecordingObserver)
        }
        connectTask?.cancel()
        logBatchTask?.cancel()
        scheduledDiagnosticsTask?.cancel()
        let oldClient = client
        let connecting = nativeConnectTask
        let previous = nativeCleanup
        Task.detached {
            await previous?.value
            oldClient?.close()
            await connecting?.value
            oldClient?.close()
        }
    }

     
     
    private var servesProxyShareFixture: Bool {


        return false
    }

    var proxyShareAPIReady: Bool {
        servesProxyShareFixture ? isConnected : isConnected && client != nil
    }

     
     
     
     
     
     
    var proxyShareAPIClientReady: Bool {
        servesProxyShareFixture ? true : client != nil
    }

    private let logRecordingEnabled: @Sendable () -> Bool
    private let memoryNow: @Sendable () -> UInt64
    private let enqueueMemory: ClashMemoryDelivery
     
     
     
     
    private let logLevelDefaults: UserDefaults

    init(
        connectionRuntimeFeed: ConnectionRuntimeFeed? = nil,
        sceneManagedDiagnostics: Bool? = nil,
        diagnosticsFollowLogRecording: Bool? = nil,
        separatesStatusStream: Bool? = nil,
        statusClientFactory: StatusStreamClientFactory? = nil,
        runtimeDiagnosticsReader: (() async throws -> ClashRuntimeDiagnostics)? = nil,
        logRecordingEnabled: @escaping @Sendable () -> Bool = {
            ClashLogStore.defaultSettings().map { ClashLogSettings.isRecording(from: $0) } ?? false
        },
        memoryNow: @escaping @Sendable () -> UInt64 = ClashMemoryClock.now,
        enqueueMemory: @escaping ClashMemoryDelivery = { action in
            Task { @MainActor in action() }
        },
        logLevelDefaults: UserDefaults = GlobalConfig.appGroupDefaults
    ) {
        self.connectionRuntimeFeed = connectionRuntimeFeed ?? .shared
        self.logLevelDefaults = logLevelDefaults
        logDisplayLevel = ClashLogSettings.liveStreamLevel(from: logLevelDefaults)
#if os(iOS)
        self.sceneManagedDiagnostics = sceneManagedDiagnostics ?? true
#else
        self.sceneManagedDiagnostics = sceneManagedDiagnostics ?? false
#endif
#if os(macOS)
        self.diagnosticsFollowLogRecording = diagnosticsFollowLogRecording ?? true
        self.separatesStatusStream = separatesStatusStream ?? true
#else
        self.diagnosticsFollowLogRecording = diagnosticsFollowLogRecording ?? false
        self.separatesStatusStream = separatesStatusStream ?? false
#endif
        self.statusClientFactory = statusClientFactory ?? Self.nativeStatusClient
        self.runtimeDiagnosticsReader = runtimeDiagnosticsReader
        self.logRecordingEnabled = logRecordingEnabled
        self.memoryNow = memoryNow
        self.enqueueMemory = enqueueMemory
         
         
         
        activeProfileLogLevelObserver = NotificationCenter.default.addObserver(
            forName: ClashLogSettings.activeProfileLogLevelDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLogDisplayLevel() }
        }
        if self.diagnosticsFollowLogRecording {
            logRecordingObserver = NotificationCenter.default.addObserver(
                forName: ClashLogSettings.recordingDidChange,
                object: nil,
                queue: nil
            ) { _ in
                Task { @MainActor [weak self] in self?.reconcileConnectionDiagnostics() }
            }
        }
return 

    }

    private func startUITestLogStreamIfRequested() {}




    func bind(session: NETunnelProviderSession?) {
        boundSession = session
        if wantsConnection { connectIfNeeded() }
    }

     
     
     
     
    func bind(sessionProvider: @escaping () -> NETunnelProviderSession?) {
        self.sessionProvider = sessionProvider
        if wantsConnection { connectIfNeeded() }
    }

    func sync(vpnStatus: String) {
        let normalized = vpnStatus.lowercased()
        let shouldConnect = normalized == "connected" || normalized == "reasserting"
         
        if tunnelIsUp != shouldConnect { tunnelIsUp = shouldConnect }
        if shouldConnect {
            wantsConnection = true
            connectIfNeeded()
            return
        }

         
         
         
         
        guard wantsConnection || client != nil || isConnecting || isConnected else { return }
        disconnect()
    }

     
     
     
     
     
     
     
     
     
     
     
     
    @Published private(set) var isReopeningControlSession = false

    func reconnectIfNeeded() {
        guard wantsConnection else { return }
         
        reconnectBackoff.reset()
        isReopeningControlSession = true
        disconnect(preserveIntent: true)
        connectIfNeeded()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func applyTrafficStatisticsPreference() {
        let enabled = TrafficStatisticsSettings.countsOnlyProxy()
         
        let live: StatusStreamClient? = separatesStatusStream ? statusClient : self.client
        guard let client = live else { return }
        do {
            try client.setOnlyStatisticsProxy(enabled)
        } catch {
            ClashLogStore.shared.append(
                "traffic scope re-subscribe failed, keeping the previous one: "
                    + error.localizedDescription,
                stream: .app,
                level: .warning
            )
        }
    }

    func disconnect(preserveIntent: Bool = false) {
        if !preserveIntent, channelAttachFailed { channelAttachFailed = false }
        if isConnected {
            recordRouteControl(
                kind: .runtimeControlDisconnected,
                failureCategory: preserveIntent
                    ? "client-reconnect"
                    : "vpn-disconnected"
            )
        }
        if !preserveIntent { wantsConnection = false }
        connectTask?.cancel()
        connectTask = nil
        isConnecting = false
        closeNativeControlAttempt()
        isConnected = false
        runningListenerPorts = nil
         
         
         
         
        if !preserveIntent {
             
            reconnectBackoff.reset()
            trafficReducer = ClashTrafficReducer()
            traffic = ClashTrafficSnapshot()
            publishMemory(MemoryState(inuse: 0, footprint: nil))
            peerSchemaVersion = 0
            peerCoreVersion = "—"
            peerCapabilities = []
            publishRuntimeDiagnostics(nil)
             
             
             
             
             
             
             
             
            proxiesData = nil
            nodeSummary = nil
            announcedSelection = [:]
             
             
             
             
            mode = "—"
        }
    }

     
     
    private func closeNativeControlAttempt() {
         
        generation &+= 1
        memoryState = MemoryState(inuse: memoryState.inuse, footprint: nil)
        lastMemorySequence = 0
        invalidateDiagnosticRequests()
        connectionDiagnosticsLease?.release(reason: .controlDisconnected)
        connectionDiagnosticsLease = nil
        cancelStatusTimers()
        closeStatusClient()
        let oldClient = client
        let connecting = nativeConnectTask
        let previous = nativeCleanup
        client = nil
        clientHandler = nil
        nativeConnectTask = nil
        guard oldClient != nil || connecting != nil else { return }
        nativeCleanup = Task.detached {
            await previous?.value
            oldClient?.close()
            await connecting?.value
            oldClient?.close()
        }
    }

    func clearLogs() {
        logBatchTask?.cancel()
        logBatchTask = nil
        pendingLogs.removeAll(keepingCapacity: true)
        logs.removeAll(keepingCapacity: true)
         
         
         
         
        ClashLogStore.shared.clear()


         
         
         
         
         
        ClashLogStore.shared.append("logs cleared", stream: .app)
        logs = ["INFO logs cleared"]
        let journal = routeEvidenceJournal
        Task { try? await journal.clear() }
    }

     
     
     
    func providerRuntimeCatalog() async throws -> ProviderRuntimeCatalog {
        guard let client, isConnected else {
            throw ProviderRuntimeCatalogError.unavailable
        }
         
         
         
         
         
        if pageRoutesAbsentGeneration != generation {
            do {
                let summary = try await self.summary()
                let rules = try await ruleProviderCatalog()
                return ProviderRuntimeCatalog(
                    proxyProviders: ProviderRuntimeCatalogParser.proxyProviders(summary: summary),
                    ruleProviders: rules.ruleProviders
                )
            } catch let error as ProviderRuntimeCatalogError {
                throw error
            } catch {
                if Self.nodeListFallback(after: error) == .wholeDocument,
                   (error as? PageRoutesAbsent)?.generation == generation {
                    pageRoutesAbsentGeneration = generation
                } else if error is NodePageRefusal || error is NodeListNotNow || error is CoreCallDeadline
                            || error is CancellationError || error is PageRoutesAbsent
                            || (error as? NodePageSourceError) == .unavailable {
                     
                     
                    throw ProviderRuntimeCatalogError.notNow
                } else {
                     
                     
                    throw ProviderRuntimeCatalogError.invalidResponse
                }
            }
        }
        let token = generation
        do {
            let catalog = try await boundedCoreCall("provider-catalog") {
                try NativeProviderRuntimeDispatcher.catalog(
                    proxy: { try Self.getProxyProviders(client) },
                    rule: { try Self.getRuleProviders(client) }
                )
            }
            guard token == generation,
                  self.client === client,
                  isConnected else {
                throw ProviderRuntimeCatalogError.unavailable
            }
            return catalog
        } catch let error as ProviderRuntimeCatalogError {
            throw error
        } catch {
             
             
            throw ProviderRuntimeCatalogError.unavailable
        }
    }

     
     
     
     
    func ruleProviderCatalog() async throws -> ProviderRuntimeCatalog {
        guard let client, isConnected else { throw ProviderRuntimeCatalogError.unavailable }
        let token = generation
        do {
            let catalog = try await boundedCoreCall("rule-provider-catalog") {
                try NativeProviderRuntimeDispatcher.catalog(
                    proxy: { #"{"providers":{}}"# },
                    rule: { try Self.getRuleProviders(client) }
                )
            }
            guard token == generation, self.client === client, isConnected else {
                throw ProviderRuntimeCatalogError.unavailable
            }
            return catalog
        } catch let error as ProviderRuntimeCatalogError {
            throw error
        } catch {
            throw ProviderRuntimeCatalogError.unavailable
        }
    }

     
     
     
     
    func fetchDirect(_ request: URLRequest, maxBytes: Int, timeout: TimeInterval,
                     redirectPolicy: DownloadRedirectPolicy) async throws -> DownloadResult {
        try await Self.fetchDirect(
            request, maxBytes: maxBytes, timeout: timeout, redirectPolicy: redirectPolicy,
            client: { [weak self] in
                guard let self, let client = self.client, self.isConnected else { return nil }
                return client
            },
            call: { [weak self] seconds, work in
                guard let self else { throw DirectFetchUnavailable() }
                return try await self.boundedCoreCall("direct-fetch", seconds: seconds, countsTowardWedge: false, work)
            }
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func fetchDirect(
        _ request: URLRequest, maxBytes: Int, timeout: TimeInterval,
        redirectPolicy: DownloadRedirectPolicy,
        client: () -> ClashAPIClient?,
        call: (_ seconds: UInt64, _ work: @escaping @Sendable () throws -> String) async throws -> String
    ) async throws -> DownloadResult {
        guard request.url != nil else { throw DirectFetchUnavailable() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direct-fetch", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sweepDirectFetchLeftovers(in: folder)
        for attempt in 0..<2 {
            try Task.checkCancellation()
             
            guard let seconds = directFetchSeconds(timeout, deadline: DirectFetchFallback.deadline) else {
                throw DirectFetchUnavailable()
            }
            let json = try directFetchRequestJSON(request, maxBytes: maxBytes, seconds: seconds,
                                                  redirectPolicy: redirectPolicy)
            guard let client = client() else { throw DirectFetchUnavailable() }
             
             
            let destination = folder.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: destination) }
            let path = destination.path
            do {
                 
                 
                let answer = try await call(UInt64(seconds) + 10) {
                    var error: NSError?
                    let answer = client.fetchDirect(json, destinationPath: path, error: &error)
                    if let error { throw error }
                    return answer
                }
                 
                 
                let result = try await Task.detached { try Self.directFetchResult(answer, file: destination) }.value
                try Task.checkCancellation()
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                 
                 
                if directFetchSays(ClashDirectFetchUnavailablePrefix, error) { throw DirectFetchUnavailable() }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                guard attempt == 0, directFetchSays(ClashDirectFetchInterruptedPrefix, error),
                      let left = directFetchSeconds(timeout, deadline: DirectFetchFallback.deadline),
                      left >= min(directFetchRetryFloor, timeout) else { throw error }
            }
        }
        throw DirectFetchUnavailable()
    }

     
     
    nonisolated static let directFetchRetryFloor: TimeInterval = 10

     
     
    nonisolated static let directFetchCoreAnswerGrace: TimeInterval = 5

     
     
     
     
    nonisolated static func directFetchSeconds(_ timeout: TimeInterval, deadline: Date?,
                                               now: Date = Date()) -> TimeInterval? {
        var seconds = min(max(timeout, 1), 300)
        if let deadline {
            let left = deadline.timeIntervalSince(now) - directFetchCoreAnswerGrace - 1
            guard left >= 1 else { return nil }
            seconds = min(seconds, left)
        }
        return seconds
    }

     
    nonisolated static func directFetchSays(_ prefix: String, _ error: Error) -> Bool {
        (error as NSError).localizedDescription.hasPrefix(prefix)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func directFetchRequestJSON(_ request: URLRequest, maxBytes: Int, seconds: TimeInterval,
                                                   redirectPolicy: DownloadRedirectPolicy) throws -> String {
        guard let url = request.url else { throw DirectFetchUnavailable() }
        var headers: [String: [String]] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:]
        where !["accept-encoding", "range"].contains(name.lowercased()) {
            headers[name, default: []].append(value)
        }
        var body: [String: Any] = [
            "url": url.absoluteString,
            "headers": headers,
            "timeoutMilliseconds": Int(seconds * 1000),
            "maximumBytes": min(max(maxBytes, 1), 268_435_456),
        ]
        switch redirectPolicy {
         
         
        case .sameOrigin, .followWithinAModulesReach:
            body["redirectPolicy"] = "sameOrigin"
        case .followAcrossOrigins(let maxHops):
            body["redirectPolicy"] = "followAcrossOrigins"
             
            body["maximumRedirects"] = min(max(maxHops, 0), 20)
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes]),
                      as: UTF8.self)
    }

     
     
    nonisolated static func sweepDirectFetchLeftovers(in folder: URL, now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, now.timeIntervalSince(date) > 600 { try? FileManager.default.removeItem(at: file) }
        }
    }

     
     
    nonisolated static func directFetchResult(_ answer: String, file: URL) throws -> DownloadResult {
        guard let object = try JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any],
              let status = object["status"] as? Int else { throw DownloadError.badStatus(-1) }
        let fields = (object["headers"] as? [String: [String]]) ?? [:]
        func header(_ name: String) -> String? {
            fields.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.first
        }
        if status == 304 {
            return DownloadResult(data: Data(), etag: header("Etag"), lastModified: header("Last-Modified"),
                                  subscriptionUserInfo: nil, contentDisposition: nil, notModified: true)
        }
        guard (200..<300).contains(status) else { throw DownloadError.badStatus(status) }
        return DownloadResult(data: try Data(contentsOf: file), etag: header("Etag"),
                              lastModified: header("Last-Modified"),
                              subscriptionUserInfo: header("subscription-userinfo"),
                              contentDisposition: header("Content-Disposition"), notModified: false)
    }

     
     
     
     
     
     
     
     
     
     
    func updateProviderInTunnel(kind: String, name: String, url: String,
                                stillInUse: @MainActor () -> Bool = { true }) async -> ProviderTunnelCheck {
        guard let client, isConnected else { return .noSession }
         
         
        guard stillInUse(), self.client === client, isConnected else { return .switched }
         
         
         
        if Task.isCancelled { return .cancelled }
        let text: String
        do {
            text = try await boundedCoreCall("provider-update", seconds: Self.providerUpdateSeconds + 5,
                                             countsTowardWedge: false) {
                var error: NSError?
                let answer = client.updateProvider(kind, name: name,
                                                   timeoutMilliseconds: Int32(Self.providerUpdateSeconds * 1000),
                                                   error: &error)
                if let error { throw error }
                return answer
            }
        } catch {
            return Self.providerTunnelCheck(refusal: error)
        }
        let check = Self.providerTunnelCheck(answer: text)
        if case .answered(let answer) = check, answer.result == .updated { Self.announceCoreFetched() }
        return check
    }

     
     
    nonisolated static func providerTunnelCheck(refusal error: Error) -> ProviderTunnelCheck {
        let words = (error as NSError).localizedDescription
        switch ProviderUpdateRefusal(words + " " + String(describing: error)) {
        case .unavailable?: return .unavailable
        case .busy?: return .busy
        case .stillRunning?: return .stillRunning
        case nil:
             
             
            return error is CoreCallDeadline ? .stillRunning : .failed(words)
        }
    }

     
     
    nonisolated static func providerTunnelCheck(answer text: String) -> ProviderTunnelCheck {
        guard let answer = ProviderUpdateAnswer.decode(text) else { return .failed(text) }
        return .answered(answer)
    }

     
     
    nonisolated static let providerUpdateSeconds: UInt64 = 60

     
     
    private static func announceCoreFetched() {
        NotificationCenter.default.post(name: .clashProviderContentChanged, object: nil)
    }

     
     
     
    func healthCheckProxyProvider(named name: String) async throws -> ProxyProviderRuntime {
        guard let client, isConnected else {
            throw ProviderRuntimeCatalogError.unavailable
        }
        let token = generation
        do {
             
             
             
             
             
             
            let provider = try await boundedCoreCall("provider-health", seconds: 20, countsTowardWedge: false) {
                try NativeProviderRuntimeDispatcher.healthCheck(
                    name: name,
                    health: { providerName in
                        _ = try client.healthCheckProxyProvider(providerName)
                    },
                    detail: { providerName in
                        try Self.getProxyProvider(client, name: providerName)
                    }
                )
            }
            guard token == generation,
                  self.client === client,
                  isConnected else {
                throw ProviderRuntimeCatalogError.unavailable
            }
            return provider
        } catch let error as ProviderRuntimeCatalogError {
            throw error
        } catch {
            throw ProviderRuntimeCatalogError.unavailable
        }
    }

    func fetchProxyShareStatus() async throws -> ProxyShareStatus {
        if servesProxyShareFixture { return uiTestProxyShareStatus }
        guard let client, isConnected else { throw ProxyShareError.apiUnavailable }
        let token = generation
        do {
            let status = try await Task.detached {
                try ProxyShareStatusParser.parse(Self.getProxyShareStatus(client))
            }.value
            guard token == generation,
                  self.client === client,
                  isConnected else {
                throw ProxyShareError.apiUnavailable
            }
            return status
        } catch {
            throw ProxyShareFailureClassifier.classify(error)
        }
    }

    func startProxyShare(
        _ configuration: ProxyShareConfiguration
    ) async throws -> ProxyShareStatus {
        if servesProxyShareFixture {
            uiTestProxyShareStatus = ProxyShareStatus(
                enabled: true,
                port: configuration.port,
                protocols: [.http, .socks5],
                authenticationRequired: true
            )
            return uiTestProxyShareStatus
        }
        guard let client, isConnected else { throw ProxyShareError.apiUnavailable }
        let token = generation
        do {
            let status = try await Task.detached {
                _ = try client.startProxyShare(
                    configuration.port,
                    username: configuration.username,
                    password: configuration.password
                )
                return try ProxyShareStatusParser.parse(
                    Self.getProxyShareStatus(client)
                )
            }.value
            guard token == generation,
                  self.client === client,
                  isConnected else {
                throw ProxyShareError.apiUnavailable
            }
            return status
        } catch {
            throw ProxyShareFailureClassifier.classify(error)
        }
    }

    func stopProxyShare() async throws -> ProxyShareStatus {
        if servesProxyShareFixture {
            uiTestProxyShareStatus = .disabled
            return .disabled
        }
        guard let client, isConnected else { throw ProxyShareError.apiUnavailable }
        let token = generation
        do {
            let status = try await Task.detached {
                _ = try client.stopProxyShare()
                return try ProxyShareStatusParser.parse(
                    Self.getProxyShareStatus(client)
                )
            }.value
            guard token == generation,
                  self.client === client,
                  isConnected else {
                throw ProxyShareError.apiUnavailable
            }
            return status
        } catch {
            throw ProxyShareFailureClassifier.classify(error)
        }
    }

     
     
    func generateDiagnosticLogs(count: Int) {
        guard count > 0 else { return }
        let generated = (0..<count).map {
            "DEBUG [developer:\($0)] local diagnostic log payload \(String(repeating: "x", count: 48))"
        }
        logs = Array((logs + generated).suffix(Self.logMaxLines))
    }

    func refreshMetadata() async {
        _ = await refreshMetadataReadingProxies()
    }

     
     
    func refreshMetadataReadingProxies() async -> Bool {
        guard let client else { return false }
        let token = generation
        let modeWritesAtRequest = localModeWrites
        configsRequests &+= 1
        let request = configsRequests
        do {
            async let configs = Task.detached { try Self.getConfigs(client) }.value
            let proxies: Data?
            var listNotNow = false
            do {
                proxies = try await nodeListDocument(client)
            } catch is NodeListNotNow {
                proxies = nil
                listNotNow = true
            }
            let configsJSON = try await configs
            guard token == generation, self.client === client, isConnected else { return false }
            applyConfigs(
                configsJSON,
                source: "configs-poll",
                modeWritesAtRequest: modeWritesAtRequest,
                request: request
            )
             
            if listNotNow { return false }
            proxiesData = proxies
            clearLastError()
            return true
        } catch {
             
             
             
            guard token == generation, self.client === client, isConnected else { return false }
            if error.localizedDescription.localizedCaseInsensitiveContains("EOF") { return false }
            lastError = error.localizedDescription
            return false
        }
    }

     
     
     
     
    func proxyDelays() async -> Data? {
        guard let client else { return nil }
        let token = generation
        guard let json = try? await Task.detached(operation: { try Self.getProxyDelays(client) }).value,
              token == generation, self.client === client, isConnected
        else { return nil }
        return json.data(using: .utf8)
    }

     
     
     
     
     
    private func nodeListDocument(_ client: ClashAPIClient) async throws -> Data? {
        if pageRoutesAbsentGeneration != generation {
            do {
                let built = try await CompactProxiesDocument.build(from: self)
                nodeSummary = built.summary
                return built.data
            } catch NodePageSourceError.unavailable {
                throw NodePageSourceError.unavailable
            } catch {
                switch Self.nodeListFallback(after: error) {
                case .wholeDocument where (error as? PageRoutesAbsent)?.generation == generation:
                    pageRoutesAbsentGeneration = generation
                default:
                     
                     
                     
                     
                     
                     
                    throw NodeListNotNow(reason: (error as NSError).localizedDescription)
                }
            }
        }
        nodeSummary = nil
        return try await Task.detached { try Self.getProxies(client) }.value.data(using: .utf8)
    }

     
     
     
    private var pageRoutesAbsentGeneration: UInt64?

     
    struct NodeListNotNow: Error {
        let reason: String
    }

    enum NodeListFallback: Equatable {
         
        case wholeDocument
         
        case notNow
    }

     
     
     
     
     
    nonisolated static func nodeListFallback(after error: Error) -> NodeListFallback {
        error is PageRoutesAbsent ? .wholeDocument : .notNow
    }

     
     
    struct PageRoutesAbsent: Error {
        let generation: UInt64
    }

     
     
    nonisolated static func isRouteAbsent(_ error: Error) -> Bool {
        (error as NSError).localizedDescription.contains(": HTTP 404:")
    }

     
    nonisolated static let summaryPageLabel = "proxies-summary"

     
     
     
     
    nonisolated static func classifyPageFailure(_ error: Error, label: String, generation: UInt64) -> Error {
        let text = (error as NSError).localizedDescription
        if text.contains(": HTTP 503:") { return NodePageRefusal(message: text) }
        if isRouteAbsent(error) {
            return label == summaryPageLabel ? PageRoutesAbsent(generation: generation) : NodePageRefusal(message: text)
        }
        return error
    }

     
     
     
     
    func proxyDelaysPage(since: Int64, after: String, limit: Int) async -> Data? {
        guard let data = try? await nodePage("proxy-delays-page", {
            try Self.getProxyDelaysPage($0, since, after, Int32(clamping: limit))
        }), NodePageRefusal.of(data) == nil
        else { return nil }
        return data
    }

     
     
     
     
     
    func proxyDelaysPageRead(since: Int64, after: String, limit: Int) async -> DelayPageRead {
        do {
            let data = try await nodePage("proxy-delays-page") {
                try Self.getProxyDelaysPage($0, since, after, Int32(clamping: limit))
            }
            return NodePageRefusal.of(data) == nil ? .page(data) : .notNow
        } catch {
            return Self.delayPageRead(after: error)
        }
    }

     
    nonisolated static func delayPageRead(after error: Error) -> DelayPageRead {
        if let refusal = error as? NodePageRefusal, refusal.message.contains(": HTTP 404:") { return .unsupported }
        if error is PageRoutesAbsent { return .unsupported }
        return .notNow
    }

     
     
     
    func healthCheckProxyProviderOnly(named name: String) async -> Bool {
        guard let client, isConnected else { return false }
        let token = generation
        let ran = (try? await boundedCoreCall("provider-health", seconds: 20, countsTowardWedge: false) {
            _ = try client.healthCheckProxyProvider(name)
        }) != nil
        return ran && token == generation && self.client === client && isConnected
    }

     
     
    func providerReadings(named name: String, since: Int64) async -> [String: Int]? {
        var readings: [String: Int] = [:]
        var after = ""
        for _ in 0..<1_000 {
            guard let data = await proxyDelaysPage(since: since, after: after, limit: 5_000) else { return nil }
            readings.merge(NodeInventory.providerReadings(named: name, in: data)) { _, newer in newer }
            guard let next = NodeInventory.delayPageCursor(data)?.next else { break }
            after = next
        }
        return readings
    }

     
     
    private func nodePage(_ label: String, _ read: @escaping @Sendable (ClashAPIClient) throws -> String) async throws -> Data {
        guard let client, isConnected else { throw NodePageSourceError.unavailable }
        let token = generation
        let json: String
        do {
            json = try await boundedCoreCall(label) { try read(client) }
        } catch {
             
             
             
             
            throw Self.classifyPageFailure(error, label: label, generation: token)
        }
        guard token == generation, self.client === client, isConnected else { throw NodePageSourceError.unavailable }
        return Data(json.utf8)
    }

     
     
    func flushDNSCache() async {
        await runCacheFlush { try Self.flushDNSCache($0) }
    }

     
    func flushFakeIPCache() async {
        await runCacheFlush { try Self.flushFakeIPCache($0) }
    }

    private func runCacheFlush(
        _ flush: @escaping @Sendable (ClashAPIClient) throws -> Void
    ) async {
        guard let client else { return }
        let token = generation
        do {
            try await Task.detached { try flush(client) }.value
            guard token == generation, self.client === client, isConnected else { return }
            clearLastError()
        } catch {
            guard token == generation, self.client === client, isConnected else { return }
            lastError = error.localizedDescription
        }
    }

     
     
     
     
     
     
     
    func fetchRules() async {
        guard let client else { return }
        let token = generation
        do {
            let fetched = try await Task.detached { try Self.diagnosticRules(client) }.value
            guard token == generation, self.client === client, isConnected else { return }
            rules = fetched.first
            rulesTotal = fetched.total > fetched.first.count ? fetched.total : nil
            ruleHits = fetched.hits
            clearLastError()
        } catch {
            guard token == generation, self.client === client, isConnected else { return }
            if error.localizedDescription.localizedCaseInsensitiveContains("EOF") { return }
            lastError = error.localizedDescription
        }
    }

     
     
     
    func applyRules(_ json: String) {
        rules = ClashRulesPayload.decode(json.data(using: .utf8))
    }

     
     
     
    func runDNSQuery(name: String, type: String) async -> String? {
        guard let client else { return nil }
        do {
            return try await Task.detached { try Self.queryDNS(client, name: name, type: type) }.value
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func readStartupExplanation() -> ClashStartupExplanation? {
        let raw = ClashExplainLastStartup()
        guard let decoded = ClashStartupExplanation.decode(raw) else {
             
             
             
             
             
             
             
             
            ClashLogStore.shared.append(
                "startup-explanation nil rawBytes=\(raw.utf8.count)",
                stream: .app, level: .info)
            return nil
        }
        let account = Self.explanationWithMeasuredStage(
            decoded, phaseLogLines: Self.phaseLogLines()
        )
         
         
         
        guard let pressure = CoreMemoryPressure.observed() else { return account }
        return account.corrected(
            footprintBytes: pressure.footprintBytes,
            budgetBytes: pressure.limitBytes
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func explanationWithMeasuredStage(
        _ account: ClashStartupExplanation,
        phaseLogLines: [String]
    ) -> ClashStartupExplanation {
        guard let measured = ClashMemoryLedger.lastRun(
            from: phaseLogLines
        ).rows.last?.name, !measured.isEmpty else { return account }
         
         
         
        return ClashStartupExplanation(
            resource: account.resource,
            footprintBytes: account.footprintBytes,
            budgetBytes: account.budgetBytes,
            stage: measured,
            failureReason: account.failureReason,
            sawCriticalPressure: account.sawCriticalPressure
        )
    }

    private static func phaseLogLines() -> [String] {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let text = try? String(
                  contentsOf: container.appendingPathComponent(
                      MemorySampleLog.startupPhaseFileName
                  ),
                  encoding: .utf8
              )
        else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

     
     
     
    func clearStartupExplanation() {
        ClashClearLastStartupExplanation()
    }

     
     
     
     
     
     
    func explainDNS(
        name: String,
        type: String,
        probe: Bool
    ) async -> String? {
        guard let client else { return nil }
        do {
            return try await boundedCoreCall("dns-explain") {
                try Self.explainDNS(
                    client,
                    name: name,
                    type: type,
                    probe: probe
                )
            }
        } catch {
             
             
             
             
             
             
             
             
             
            ClashLogStore.shared.append(
                "dns explain unavailable: " + error.localizedDescription,
                stream: .app,
                level: .warning
            )
            return nil
        }
    }

     
     
     
     
     
     
     
     
    func configDeviations() async -> ConfigDeviationReport? {
        guard let client else { return nil }
        do {
            let json = try await boundedCoreCall("config-deviations") {
                try Self.configDeviations(client)
            }
            return try ConfigDeviationReport.decode(json)
        } catch {
             
             
             
             
             
            ClashLogStore.shared.append(
                "config deviations unavailable: " + error.localizedDescription,
                stream: .app,
                level: .warning
            )
            return nil
        }
    }

    private struct DiagnosticRequest {
        let control: UInt64
        let epoch: UInt64
        let sequence: UInt64
        let read: () async throws -> ClashRuntimeDiagnostics
    }

    private func invalidateDiagnosticRequests() {
        observationEpoch &+= 1
        confirmedObservationEpoch = nil
        diagnosticsRequestInFlight = false
        scheduledDiagnosticsTask?.cancel(); scheduledDiagnosticsTask = nil
    }

     
    func syncConnectionObservationScene(isActive: Bool, isBackground: Bool) {
        guard sceneManagedDiagnostics else { return }
        let next: DiagnosticScene = isActive ? .active : (isBackground ? .background : .inactive)
        guard next != diagnosticScene else { return }
        diagnosticScene = next
         
        invalidateDiagnosticRequests()
        if next == .background {
            connectionDiagnosticsLease?.release(reason: .noForegroundScene)
            connectionDiagnosticsLease = nil
        }
        reconcileConnectionDiagnostics()
    }

    private func reconcileConnectionDiagnostics() {
        guard isConnected else { return }
        if diagnosticsFollowLogRecording, !logRecordingEnabled(), !connectionActivityDemanded {
             
            connectionDiagnosticsLease?.release(reason: .controlDisconnected)
            connectionDiagnosticsLease = nil
            return
        }
        if sceneManagedDiagnostics {
            guard diagnosticScene == .active else { return }
            guard connectionDiagnosticsLease == nil else { return }
            guard confirmedObservationEpoch == observationEpoch else {
                if !diagnosticsRequestInFlight { scheduleRuntimeDiagnosticsRefresh() }
                return
            }
            let route = currentRouteContext()
            guard runtimeDiagnostics?.running == true, route.coreProcessIdentifier > 0, route.coreStartTimeUnix > 0,
                  route.profileID != "unavailable", !route.profileID.isEmpty,
                  route.profileRevision != "unavailable", !route.profileRevision.isEmpty else { return }
        }
        guard connectionDiagnosticsLease == nil else { return }
        connectionDiagnosticsLease = connectionRuntimeFeed.acquireDiagnostics(sceneManaged: sceneManagedDiagnostics,
            context: { [weak self] in
                guard let self, self.isConnected, self.runtimeDiagnostics != nil else { return nil }
                if self.sceneManagedDiagnostics, self.runtimeDiagnostics?.running != true { return nil }
                return ConnectionDiagnosticContext(route: self.currentRouteContext(), confirmedAt: self.runtimeConfirmedAt)
            },
            projects: { [weak self] in
                guard let self else { return false }
                return !self.diagnosticsFollowLogRecording || self.logRecordingEnabled()
            },
            receive: { [weak self] lines in self?.enqueueLogLines(lines) })
    }

    private func beginDiagnosticRequest() -> DiagnosticRequest? {
        let read: () async throws -> ClashRuntimeDiagnostics
        if let runtimeDiagnosticsReader { read = runtimeDiagnosticsReader }
        else if let providerSession { read = { try await ClashClient(session: providerSession).runtimeDiagnostics() } }
        else { return nil }
        scheduledDiagnosticsTask?.cancel(); scheduledDiagnosticsTask = nil
        runtimeDiagnosticsRequest &+= 1
        diagnosticsRequestInFlight = true
        if sceneManagedDiagnostics, diagnosticScene == .active, connectionDiagnosticsLease == nil {
            runtimeIdentityCache.invalidate()
        }
        return DiagnosticRequest(control: generation, epoch: observationEpoch, sequence: runtimeDiagnosticsRequest, read: read)
    }

    private func isCurrent(_ request: DiagnosticRequest) -> Bool {
        request.control == generation && request.epoch == observationEpoch && request.sequence == runtimeDiagnosticsRequest
    }

    private func publishRuntimeDiagnostics(_ value: ClashRuntimeDiagnostics?) {
        diagnosticPublication = value
        guard !publishingDiagnostics else { return }
        publishingDiagnostics = true
        defer { publishingDiagnostics = false }
        repeat {
            let current = diagnosticPublication
            runtimeDiagnostics = current
        } while runtimeDiagnostics != diagnosticPublication
    }

    private func finishDiagnosticRequest(_ result: Result<ClashRuntimeDiagnostics, Error>, request: DiagnosticRequest) {
        guard isCurrent(request) else { return }
        diagnosticsRequestInFlight = false
        scheduledDiagnosticsTask = nil
        switch result {
        case let .success(diagnostics):
            let previous = diagnosticPublication
            publishRuntimeDiagnostics(diagnostics)
            guard isCurrent(request) else {
                 
                if diagnosticPublication == diagnostics { publishRuntimeDiagnostics(previous) }
                return
            }
            runtimeConfirmedAt = DispatchTime.now().uptimeNanoseconds
            confirmedObservationEpoch = observationEpoch
            if sceneManagedDiagnostics, diagnosticScene == .active, connectionDiagnosticsLease == nil {
                runtimeIdentityCache.invalidate()
            }
            let context = currentRouteContext()
            if context.generationKey != lastConfirmedRuntimeEvidenceKey {
                lastConfirmedRuntimeEvidenceKey = context.generationKey
                recordRouteControl(kind: .runtimeCoreConfirmed)
            }
            diagnosticsBackoff.reset()
            reconcileConnectionDiagnostics()
        case let .failure(error):
            lastError = error.localizedDescription
            scheduleRuntimeDiagnosticsRetry(after: request)
        }
    }

     
     
     
     
    private func scheduleRuntimeDiagnosticsRetry(after request: DiagnosticRequest) {
        let delay = diagnosticsBackoff.nextDelay()
        scheduledDiagnosticsTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, self.isCurrent(request), self.isConnected,
                  !self.diagnosticsRequestInFlight else { return }
            if self.sceneManagedDiagnostics, self.diagnosticScene != .active { return }
            self.scheduleRuntimeDiagnosticsRefresh()
        }
    }

    private func scheduleRuntimeDiagnosticsRefresh() {
        guard let request = beginDiagnosticRequest() else { return }
         
        scheduledDiagnosticsTask = Task { [weak self] in
            let result: Result<ClashRuntimeDiagnostics, Error>
            do { result = .success(try await request.read()) }
            catch { result = .failure(error) }
            self?.finishDiagnosticRequest(result, request: request)
        }
    }

    func refreshRuntimeDiagnostics() async {
        guard let request = beginDiagnosticRequest() else { return }
        let result: Result<ClashRuntimeDiagnostics, Error>
        do { result = .success(try await request.read()) }
        catch { result = .failure(error) }
        finishDiagnosticRequest(result, request: request)
    }

    func requestGarbageCollection() async {
        guard !isCollectingMemory else { return }
        guard let providerSession else {
            lastError = "VPN Provider API is not connected."
            return
        }
        guard peerCapabilities.contains(ClashCommandCapability.forceGCV1) else {
            lastError = "The installed VPN Extension does not support memory release. Reinstall or update Clash."
            return
        }
        isCollectingMemory = true
        defer { isCollectingMemory = false }
        do {
            try await ClashClient(session: providerSession).forceGarbageCollection()
            memoryActionMessage = "Memory released"
            clearLastError()
            await refreshRuntimeDiagnostics()
        } catch {
            memoryActionMessage = ""
            lastError = error.localizedDescription
        }
    }

    private func consumeStartupOOMEvidence() async {
        guard let providerSession else { return }
        let providerClient = ClashClient(session: providerSession)
        guard let diagnostics = try? await providerClient.runtimeDiagnostics() else { return }
        guard oomEvidenceConsumeTracker.beginAttempt(
            processIdentifier: diagnostics.processIdentifier,
            startTimeUnix: diagnostics.startTimeUnix
        ) else { return }
         
         
         
         
        previousOOMEvidence = try? await providerClient.consumeOOMEvidence()
        if let evidence = previousOOMEvidence {
             
             
             
             
            ClashLogStore.shared.append(evidence.logLine, stream: .app, level: .warning)
        }
         
         
         
         
        if let report = await providerClient.consumeGoCrashReport() {
            previousGoCrashReport = report
        }
    }

     
     
     
     
     
     
     
    private var localModeWrites: UInt64 = 0

     
     
     
     
     
     
    private var modeSendChain: Task<Bool, Never>?

     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func setMode(_ newMode: String, closesConnections: Bool = true) async -> Bool {
        let previous = modeSendChain
        let link = Task { [weak self] in
            _ = await previous?.value
            return await self?.sendModeNow(newMode, closesConnections: closesConnections) ?? false
        }
        modeSendChain = link
        return await link.value
    }

    private func sendModeNow(_ newMode: String, closesConnections: Bool) async -> Bool {
        recordRouteControl(
            kind: .modeRequested,
            requestedMember: newMode
        )
        guard let client else {
            recordRouteControl(
                kind: .modeRejected,
                requestedMember: newMode,
                failureCategory: "control-unavailable"
            )
            return false
        }
        do {
             
             
             
             
            let closes = closesConnections && NodeSwitchSettings.autoCloseOnSwitch()
            let before = try await Task.detached { () -> String? in
                let running = closes ? Self.runningMode(client) : nil
                try client.setMode(newMode)
                return running
            }.value
            mode = newMode
            localModeWrites &+= 1
            clearLastError()
            recordRouteControl(
                kind: .modeConfirmed,
                confirmedMember: newMode
            )
             
             
             
             
             
             
             
            if ClashConnectionsOnSwitch.closesAfterModeSwitch(from: before, to: newMode, settingIsOn: closes) {
                await closeConnectionsAfterProxySelection()
            }
            return true
        } catch {
            lastError = error.localizedDescription
            recordRouteControl(
                kind: .modeRejected,
                requestedMember: newMode,
                failureCategory: "core-rejected"
            )
            return false
        }
    }

     
     
     
     
     
     
     
     
     
    var lastCommandError: String { lastError }

     
    private(set) var lastSelectionFailure: SelectionFailure = .notAnswered

     
     
     
     
     
    nonisolated static func selectionFailure(from error: Error) -> SelectionFailure {
        let text = (error as NSError).localizedDescription
        guard let range = text.range(of: #"HTTP (\d{3})"#, options: .regularExpression) else { return .notAnswered }
        return text[range].hasSuffix("400") ? .notListed : .notAnswered
    }

     
     
     
     
     
     
     
    nonisolated static func failureOfAPickNotHeld(inTheSameSession sameSession: Bool, readBack: ProxyGroup?) -> SelectionFailure {
        guard sameSession, let readBack, ProxyGroupControlKind(rawType: readBack.type).canBeUnpinned else {
            return .notAnswered
        }
        return .notHeld
    }

     
     
     
     
     
     
    nonisolated static func failureOfAnAnsweredPick(
        inTheSameSession sameSession: Bool, readFresh: Bool, readBack: ProxyGroup?, name: String
    ) -> SelectionFailure? {
        guard sameSession, readFresh else { return .notAnswered }
        if readBack?.holdsSelection(name) == true { return nil }
        return failureOfAPickNotHeld(inTheSameSession: true, readBack: readBack)
    }

    func unfix(group: String) async -> Bool {
        guard let client, isConnected else {
            lastError = "Proxy control is not connected."
            return false
        }
        do {
            try await Task.detached { try client.unfixProxy(group) }.value
             
             
            await refreshMetadata()
            clearLastError()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func select(group: String, name: String) async -> Bool {
        recordRouteControl(
            kind: .selectionRequested,
            selectionGroup: group,
            requestedMember: name
        )
        guard let client, isConnected else {
            lastError = "Proxy control is not connected."
            lastSelectionFailure = .notAnswered
            recordRouteControl(
                kind: .selectionRejected,
                selectionGroup: group,
                requestedMember: name,
                failureCategory: "control-unavailable"
            )
            return false
        }
        let token = generation
        do {
            try await Task.detached { try client.selectProxy(group, name: name) }.value
            let readFresh = await refreshMetadataReadingProxies()
            let sameSession = token == generation && self.client === client && isConnected
             
            let confirmedGroup = readFresh
                ? NodeInventory.parse(proxiesData).0.first(where: { $0.name == group })
                : nil
             
             
             
             
             
             
            if let failure = Self.failureOfAnAnsweredPick(
                inTheSameSession: sameSession, readFresh: readFresh, readBack: confirmedGroup, name: name
            ) {
                lastError =
                    "The running proxy group did not confirm the selected route."
                lastSelectionFailure = failure
                recordRouteControl(
                    kind: .selectionRejected,
                    selectionGroup: group,
                    requestedMember: name,
                    confirmedMember: confirmedGroup?.now,
                    resolvedMember: confirmedGroup?.resolvedNow,
                    failureCategory: "catalog-unconfirmed"
                )
                return false
            }
            clearLastError()
            recordRouteControl(
                kind: .selectionConfirmed,
                selectionGroup: group,
                requestedMember: name,
                confirmedMember: confirmedGroup?.now,
                resolvedMember: confirmedGroup?.resolvedNow
            )
            return true
        } catch {
            guard token == generation,
                  self.client === client else {
                lastSelectionFailure = .notAnswered
                return false
            }
            lastError = error.localizedDescription
            lastSelectionFailure = Self.selectionFailure(from: error)
            recordRouteControl(
                kind: .selectionRejected,
                selectionGroup: group,
                requestedMember: name,
                failureCategory: lastSelectionFailure == .notListed ? "core-refused-member" : "core-rejected"
            )
            return false
        }
    }

     
     
     
     
     
     
     
     
    func closeConnectionsAfterProxySelection() async {
        await closeOnTheCoreChannel { try $0.closeConnections() }
    }

     
     
     
     
     
     
     
     
     
     
    func closeConnectionsMoved(by picks: [ProxyGroupPick]) async {
        await closeOnTheCoreChannel { client in
            var error: NSError?
            let table = client.getConnections(&error)
            guard error == nil,
                  let ids = ProxySelectionConnections.ids(in: Data(table.utf8), movedBy: picks) else {
                try client.closeConnections()
                return
            }
            let refusals = ProxySelectionConnections.Refusals()
            DispatchQueue.concurrentPerform(iterations: ids.count) { index in
                do { try client.closeConnection(ids[index]) } catch { refusals.note(error) }
            }
            if !ids.isEmpty, let last = refusals.all(of: ids.count) { throw last }
        }
    }

     
     
    private func closeOnTheCoreChannel(_ work: @escaping @Sendable (ClashAPIClient) throws -> Void) async {
        guard let client, isConnected else {
            lastError = "Proxy control is not connected."
            return
        }
        let token = generation
        do {
            try await Task.detached {
                try work(client)
            }.value
            guard token == generation,
                  self.client === client,
                  isConnected else {
                return
            }
            clearLastError()
        } catch {
            guard token == generation,
                  self.client === client,
                  isConnected else {
                return
            }
            lastError = error.localizedDescription
        }
    }

    func urlTest(name: String, url: String = "") async -> Int {
        let outcome = await probeOutcome(name: name, url: url)
        if outcome.succeeded {
            clearLastError()
        } else {
            lastError = Self.urlTestFailureMessage(category: outcome.failureCategory)
        }
        return outcome.delay
    }

    func urlTestQuietly(name: String, url: String = "") async -> ClashURLTestOutcome {
        await probeOutcome(name: name, url: url)
    }

    func startSTUNTest(
        server: String,
        outbound: String,
        handler: ClashSTUNTestHandlerProtocol
    ) async throws -> ClashSTUNTestSession {
        guard let client else {
            throw NSError(
                domain: "ClashClient.STUN",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "VPN Provider API is not connected."]
            )
        }
        guard peerCapabilities.contains(ClashCommandCapability.stunV1) else {
            throw NSError(
                domain: "ClashClient.STUN",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The installed VPN Extension does not support STUN diagnostics. Reinstall or update Clash."]
            )
        }
        return try await Task.detached {
            try client.startSTUNTest(
                server,
                outbound: outbound,
                handler: handler
            )
        }.value
    }

     
     
     
     
     
     
    private func probeOutcome(name: String, url: String) async -> ClashURLTestOutcome {
        guard let client, isConnected else {
             
             
             
             
            ClashLogStore.shared.append(
                "urltest blocked  name=\(name)  control-session "
                    + (client == nil ? "absent" : "reconnecting"),
                stream: .app, level: .warning)
            return ClashURLTestOutcome(delay: -1, failureCategory: "api-unavailable")
        }
        do {
             
             
             
             
             
             
             
             
             
             
             
            let payload = try await boundedCoreCall(
                "urltest", countsTowardWedge: false
            ) {
                 
                 
                 
                var failure: NSError?
                let body = client.urlTestOutcome(
                    name, testURL: url, error: &failure)
                if let failure { throw failure }
                return body
            }
            let outcome = Self.parseURLTestOutcome(payload)
            if outcome.succeeded {
                ClashLogStore.shared.append(
                    "urltest ok  name=\(name)  delay=\(outcome.delay)ms",
                    stream: .app, level: .info)
                return outcome
            }
            let reason = "urltest failed  name=\(name)  "
                + "category=\(outcome.failureCategory)  payload=\(payload)"
            ClashLogStore.shared.append(reason, stream: .app, level: .warning)
            Self.urlTestLog.warning("\(reason, privacy: .public)")
            return outcome
        } catch {
             
             
             
            let category = Self.urlTestFailureCategory(error.localizedDescription)
             
             
             
             
             
             
            let reason = "urltest failed  name=\(name)  category=\(category)  error=\(error.localizedDescription)"
            ClashLogStore.shared.append(reason, stream: .app, level: .warning)
            Self.urlTestLog.warning("\(reason, privacy: .public)")
            return ClashURLTestOutcome(delay: -1, failureCategory: category)
        }
    }


     
     
    private var coreCallBreachStreak = 0

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func boundedCoreCall<T: Sendable>(
        _ label: String,
        seconds: UInt64 = 8,
        countsTowardWedge: Bool = true,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        switch await Self.raceCoreCall(seconds: seconds, work) {
        case .deadline:
            if countsTowardWedge { coreCallBreachStreak += 1 }
            ClashLogStore.shared.append(
                "core-call deadline  call=\(label)  streak=\(coreCallBreachStreak)",
                stream: .app, level: .warning)
            if countsTowardWedge, coreCallBreachStreak >= 3 {
                coreCallBreachStreak = 0
                let move = "reopening"
                ClashLogStore.shared.append(
                    "core-call self-heal  \(move) the control session",
                    stream: .app, level: .warning)
                reconnectIfNeeded()
            }
            throw CoreCallDeadline(label: label, seconds: seconds)
        case .cancelled:
            throw CancellationError()
        case .result(let result):
            coreCallBreachStreak = 0
            return try result.get()
        }
    }

     
    private nonisolated static func raceCoreCall<T: Sendable>(
        seconds: UInt64,
        _ work: @escaping @Sendable () throws -> T
    ) async -> CoreCallRace<T>.Outcome {
        let race = CoreCallRace<T>()
        return await withTaskCancellationHandler {
             
             
             
            let timeout = Task.detached {
                do {
                    try await Task.sleep(
                        nanoseconds: seconds * 1_000_000_000
                    )
                    race.resolve(.deadline)
                } catch {
                     
                }
            }
            Task.detached {
                let result = await Self.onDedicatedThread {
                    Result { try work() }
                }
                if race.resolve(.result(result)) {
                    timeout.cancel()
                }
            }
            let outcome = await race.wait()
            timeout.cancel()
            return outcome
        } onCancel: {
            race.resolve(.cancelled)
        }
    }

     
     
     
    nonisolated static func boundedSessionlessCoreCall<T: Sendable>(
        _ label: String,
        seconds: UInt64,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        switch await raceCoreCall(seconds: seconds, work) {
        case .deadline:
            ClashLogStore.shared.append("core-call deadline  call=\(label)  sessionless", stream: .app, level: .warning)
            throw CoreCallDeadline(label: label, seconds: seconds)
        case .cancelled:
            throw CancellationError()
        case .result(let result):
            return try result.get()
        }
    }

     
     
    private nonisolated static func onDedicatedThread<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: work())
            }
        }
    }

     
    struct CoreCallDeadline: Error, LocalizedError {
        let label: String
         
        var seconds: UInt64 = 8
        var errorDescription: String? {
            "core call \(label) exceeded its \(seconds)s client deadline (timeout)"
        }
    }

    private static let urlTestLog = Logger(
        subsystem: "org.example.clash", category: "urltest")

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func parseURLTestOutcome(_ payload: String) -> ClashURLTestOutcome {
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any]
        else {
             
             
             
             
             
             
             
             
             
             
             
            let note = "urltest payload-unparsed  fallback=prose  payload=\(payload)"
            ClashLogStore.shared.append(note, stream: .app, level: .warning)
            urlTestLog.warning("\(note, privacy: .public)")
            return ClashURLTestOutcome(
                delay: -1,
                failureCategory: urlTestFailureCategory(payload)
            )
        }
        if let delay = root["delay"] as? Int, delay > 0 {
            return ClashURLTestOutcome(delay: delay, failureCategory: "")
        }
        if root["deferred"] as? Bool == true {
            return ClashURLTestOutcome(
                delay: -1, failureCategory: "admission-deferred")
        }
        let failure = root["failure"] as? [String: Any] ?? [:]
        let errno = (failure["errno"] as? String ?? "").uppercased()
        let kind = (failure["kind"] as? String ?? "").lowercased()
        let inner = failure["message"] as? String
            ?? root["message"] as? String
            ?? payload
        return ClashURLTestOutcome(
            delay: -1,
            failureCategory: urlTestCategory(
                errno: errno, kind: kind, message: inner)
        )
    }

     
     
    nonisolated static func urlTestCategory(
        errno: String,
        kind: String,
        message: String
    ) -> String {
        switch errno {
        case "ECONNREFUSED": return "connection-refused"
         
         
         
        case "EADDRNOTAVAIL": return "address-unavailable"
        case "EHOSTUNREACH", "ENETUNREACH": return "unreachable"
        case "ETIMEDOUT": return "timeout"
        case "ECONNRESET": return "connection-reset"
        case "EPIPE": return "connection-closed"
        default: break
        }
        switch kind {
        case "timeout": return "timeout"
        case "canceled": return "canceled"
        case "status": return "unexpected-status"
        case "write": return "write-failed"
        case "read": return "read-failed"
        case "dial": return "dial-failed"
        default: break
        }
         
         
         
        return urlTestFailureCategory(message)
    }

    nonisolated static func urlTestFailureCategory(_ description: String) -> String {
        let value = description.lowercased()
         
         
         
        if value.contains("url test deferred: memory admission") {
            return "admission-deferred"
        }
        if value.contains("timeout") || value.contains("deadline exceeded") || value.contains("http 504") {
            return "timeout"
        }
        if value.contains("dns") || value.contains("no such host") || value.contains("couldn't find ip") {
            return "dns"
        }
        if value.contains("tls") || value.contains("certificate") || value.contains("x509") {
            return "tls"
        }
        if value.contains("auth") || value.contains("unauthorized") || value.contains("forbidden") {
            return "authentication"
        }
        if value.contains("503 service unavailable") {
            return "proxy-service-unavailable"
        }
        if value.contains("502 bad gateway") {
            return "proxy-bad-gateway"
        }
        if value.contains("connect method not allowed") {
            return "proxy-connect-unsupported"
        }
        if value.contains("can not connect remote err code") {
            return "proxy-connect-rejected"
        }
        if value.contains("connection refused") {
            return "connection-refused"
        }
        if value.contains("unexpected http status") {
            return "unexpected-status"
        }
        if value.contains("network is unreachable") || value.contains("no route to host") {
            return "network-unreachable"
        }
        if value.contains("eof") || value.contains("connection reset") || value.contains("broken pipe") {
            return "connection-closed"
        }
        if value.contains("http 503") {
            return "delay-test-failed"
        }
        return "other"
    }

    static func urlTestFailureMessage(category: String) -> String {
        switch category {
        case "timeout": return "URL test timed out after 5 seconds."
        case "dns": return "URL test failed because the node hostname could not be resolved."
        case "tls": return "URL test failed during TLS or certificate verification."
        case "authentication": return "URL test failed authentication. Check the node credentials."
        case "proxy-service-unavailable": return "The HTTP proxy returned 503 Service Unavailable for the test target."
        case "proxy-bad-gateway": return "The HTTP proxy returned 502 Bad Gateway for the test target."
        case "proxy-connect-unsupported": return "The configured HTTP proxy does not allow CONNECT requests."
        case "proxy-connect-rejected": return "The HTTP proxy rejected the CONNECT target."
        case "connection-refused": return "The node server refused the connection."
        case "unexpected-status": return "The URL test target returned an unexpected HTTP status through this node."
        case "network-unreachable": return "The node server is unreachable on the current network."
        case "connection-closed": return "The node connection closed during the URL test."
        case "api-unavailable": return "VPN Provider API is not connected."
        default: return "URL test failed for the selected node. Check reachability, TLS/authentication, and protocol settings."
        }
    }

    private func connectIfNeeded() {
        guard client == nil, !isConnecting else { return }
         
         
         
         
         
         
         
         
         
         
         
         
        guard let providerSession else {
            noteConnectFailure("no-tunnel-session-yet;retrying")
            scheduleReconnect(token: generation)
            return
        }
        guard let container = ClashAppIdentifiers.appGroupContainer
        else {
            lastError = "App Group container unavailable"
            return
        }

        generation &+= 1
        memoryState = MemoryState(inuse: memoryState.inuse, footprint: nil)
        lastMemorySequence = 0
         
         
        runtimeIdentityCache.invalidate()
        let token = generation
        isConnecting = true
        armAttemptWatchdog(token: token)
        connectTask = Task { [weak self] in
            do {
                let hello = try await ClashClient(session: providerSession).hello()
                 
                 
                 
                 
                 
                await Self.awaitBounded(self?.nativeCleanup, seconds: 5)
                guard !Task.isCancelled else { return }
                self?.openNativeClient(
                    socketPath: container.appendingPathComponent("clash.sock").path,
                    hello: hello,
                    token: token
                )
            } catch {
                self?.connectFailed(error, token: token)
            }
        }
    }

    private func makeCommandHandler() -> HandlerProxy {
        HandlerProxy(owner: self, token: generation, now: memoryNow, enqueueMemory: enqueueMemory, recordLogs: logRecordingEnabled)
    }

     
    func memoryHandlerForTesting() -> ClashAPIClientHandlerProtocol {
        makeCommandHandler()
    }

    func logHandlerForTesting() -> (ClashAPIClientHandlerProtocol, ClashLogBudget) {
        let handler = makeCommandHandler()
        return (handler, handler.logDeliveryBudget)
    }

    private func openNativeClient(socketPath: String, hello: ClashCommandHello, token: UInt64) {
        guard token == generation, wantsConnection else { return }
        connectTask = nil
        let handler = makeCommandHandler()
        let logLevel = wantedLogSubscription
        let options = Self.makeOptions(
            onlyStatisticsProxy: TrafficStatisticsSettings.countsOnlyProxy(),
            logLevel: logLevel,
            includesStatus: !separatesStatusStream
        )
        controlSocketPath = socketPath
        subscribedLogLevel = logLevel
        var error: NSError?
        guard let newClient = ClashNewAPIClientWithOptions(
            socketPath,
            handler,
            options,
            &error
        ) else {
            connectFailed(
                error ?? NSError(
                    domain: "ClashClient.CommandClient",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create Clash API client"]
                ),
                token: token
            )
            return
        }

        peerSchemaVersion = hello.schemaVersion
        peerCoreVersion = hello.coreVersion
        peerCapabilities = hello.capabilities
        clientHandler = handler
        client = newClient
        nativeConnectTask = Task.detached { [weak self] in
            do {
                try newClient.connect()
                await self?.reconcileTrafficScopeAfterConnect(
                    newClient, token: token
                )
            } catch {
                await self?.connectFailed(error, token: token)
            }
        }
    }

     
     
     
     
    private func reconcileTrafficScopeAfterConnect(
        _ connectedClient: ClashAPIClient, token: UInt64
    ) {
        guard token == generation, wantsConnection, client === connectedClient else { return }
        applyTrafficStatisticsPreference()
    }

     
    static func makeOptions(
        onlyStatisticsProxy: Bool,
        logLevel: String? = "info",
        includesStatus: Bool = true
    ) -> ClashAPIClientOptions {
        let options = ClashAPIClientOptions()
         
         
         
         
         
         
         
         
        options.statusInterval = 1000
         
        if includesStatus { options.addCommand(ClashCommandStatus) }
        if let logLevel {
            options.addCommand(ClashCommandLog)
            options.logLevel = logLevel
        }
         
         
         
         
        options.addCommand(ClashCommandMode)
        options.onlyStatisticsProxy = onlyStatisticsProxy
        return options
    }

     
    private nonisolated static func runningMode(_ client: ClashAPIClient) -> String? {
        guard let json = try? getConfigs(client),
              let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        return object["mode"] as? String
    }

    private nonisolated static func getConfigs(_ client: ClashAPIClient) throws -> String {
        var error: NSError?
        let result = client.getConfigs(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func flushDNSCache(_ client: ClashAPIClient) throws {
        try client.flushDNSCache()
    }

    private nonisolated static func flushFakeIPCache(_ client: ClashAPIClient) throws {
        try client.flushFakeIPCache()
    }

    private nonisolated static func getProxies(_ client: ClashAPIClient) throws -> String {
        var error: NSError?
        let result = client.getProxies(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProxyDelays(_ client: ClashAPIClient) throws -> String {
        var error: NSError?
        let result = client.getProxyDelays(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func compilePendingProviders(_ client: ClashAPIClient, _ configuration: String,
                                                            _ targetProfile: String) throws -> String {
        var error: NSError?
        let result = client.compilePendingProviders(configuration, targetProfile: targetProfile, error: &error)
        if let error { throw error }
        return result
    }

     
     
    private nonisolated static func getProxiesSummary(_ client: ClashAPIClient) throws -> String {
        var error: NSError?
        let result = client.getProxiesSummary(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getGroupMembers(_ client: ClashAPIClient, _ group: String, _ offset: Int32, _ limit: Int32) throws -> String {
        var error: NSError?
        let result = client.getGroupMembers(group, offset: offset, limit: limit, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProviderNodes(_ client: ClashAPIClient, _ provider: String, _ offset: Int32, _ limit: Int32) throws -> String {
        var error: NSError?
        let result = client.getProviderNodes(provider, offset: offset, limit: limit, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProxiesPage(_ client: ClashAPIClient, _ after: String, _ limit: Int32) throws -> String {
        var error: NSError?
        let result = client.getProxiesPage(after, limit: limit, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProxyDelaysPage(_ client: ClashAPIClient, _ since: Int64, _ after: String, _ limit: Int32) throws -> String {
        var error: NSError?
        let result = client.getProxyDelaysPage(since, after: after, limit: limit, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func searchGroupMembers(_ client: ClashAPIClient, _ group: String, _ query: String, _ offset: Int32, _ limit: Int32) throws -> String {
        var error: NSError?
        let result = client.searchGroupMembers(group, query: query, offset: offset, limit: limit, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func lookupProxy(_ client: ClashAPIClient, _ name: String) throws -> String {
        var error: NSError?
        let result = client.lookupProxy(name, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func searchProxies(_ client: ClashAPIClient, _ query: String, _ offset: Int32, _ limit: Int32) throws -> String {
        var error: NSError?
        let result = client.searchProxies(query, offset: offset, limit: limit, error: &error)
        if let error { throw error }
        return result
    }

     
     
    private struct RulesPage: Decodable {
        let total: Int
        let noted: Int?
        let rules: [ClashRule]
    }

     
    struct DiagnosticRules: Equatable {
         
         
        var first: [ClashRule]
         
        var total: Int
         
         
        var hits: [ClashRule]
    }

     
     
    nonisolated static func diagnosticRules(
        _ client: ClashAPIClient, pageSize: Int32 = 500,
        most: Int = ClashRuntimeRulesPayload.maximumRuleCount
    ) throws -> DiagnosticRules {
        func read(_ call: (Int32, NSErrorPointer) -> String, _ offset: Int) throws -> String {
            var error: NSError?
            let json = call(Int32(clamping: offset), &error)
            if let error { throw error }
            return json
        }
        return try diagnosticRules(
            rulesPage: { try read({ client.getRulesPage($0, limit: pageSize, typesJSON: "", error: $1) }, $0) },
            ruleHits: { try read({ client.getRuleHits($0, limit: pageSize, error: $1) }, $0) },
            most: most)
    }

     
     
    nonisolated static func diagnosticRules(
        rulesPage: (_ offset: Int) throws -> String, ruleHits: (_ offset: Int) throws -> String,
        most: Int = ClashRuntimeRulesPayload.maximumRuleCount
    ) throws -> DiagnosticRules {
        func page(_ json: String) throws -> RulesPage {
            try JSONDecoder().decode(RulesPage.self, from: Data(json.utf8))
        }
        let opening = try page(rulesPage(0))
        var first = opening.rules
        while first.count < min(opening.total, most) {
            let next = try page(rulesPage(first.count))
            guard !next.rules.isEmpty else { break }
            first += next.rules
        }
        first = Array(first.prefix(most))
        guard opening.total > most else { return DiagnosticRules(first: first, total: opening.total, hits: []) }
        var hits: [ClashRule] = []
        while hits.count < most {
            let next = try page(ruleHits(hits.count))
            hits += next.rules
            guard !next.rules.isEmpty, hits.count < (next.noted ?? 0) else { break }
        }
        return DiagnosticRules(first: first, total: opening.total, hits: Array(hits.prefix(most)))
    }

    private nonisolated static func queryDNS(
        _ client: ClashAPIClient, name: String, type: String
    ) throws -> String {
        var error: NSError?
        let result = client.queryDNS(name, qType: type, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func explainDNS(
        _ client: ClashAPIClient,
        name: String,
        type: String,
        probe: Bool
    ) throws -> String {
        var error: NSError?
        let result = client.explainDNS(
            name,
            qType: type,
            probe: probe,
            error: &error
        )
        if let error { throw error }
        return result
    }

    private nonisolated static func configDeviations(
        _ client: ClashAPIClient
    ) throws -> String {
        var error: NSError?
        let result = client.getConfigDeviations(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProxyShareStatus(
        _ client: ClashAPIClient
    ) throws -> String {
        var error: NSError?
        let result = client.getProxyShareStatus(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProxyProviders(
        _ client: ClashAPIClient
    ) throws -> String {
        var error: NSError?
        let result = client.getProxyProviders(&error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getProxyProvider(
        _ client: ClashAPIClient,
        name: String
    ) throws -> String {
        var error: NSError?
        let result = client.getProxyProvider(name, error: &error)
        if let error { throw error }
        return result
    }

    private nonisolated static func getRuleProviders(
        _ client: ClashAPIClient
    ) throws -> String {
        var error: NSError?
        let result = client.getRuleProviders(&error)
        if let error { throw error }
        return result
    }

    private func connectFailed(_ error: Error, token: UInt64) {
        guard token == generation else { return }
         
         
         
         
         
        if reconnectBackoff.failures > 0, !channelAttachFailed { channelAttachFailed = true }
        isConnecting = false
        connectTask = nil
        closeNativeControlAttempt()
        isConnected = false
        runningListenerPorts = nil
        lastError = error.localizedDescription
        noteConnectFailure("connect-failed:" + error.localizedDescription)
         
         
        isReopeningControlSession = false
        scheduleReconnect(token: generation)
    }

    private func handleConnected(token: UInt64) {
        guard token == generation else { return }
        if channelAttachFailed { channelAttachFailed = false }
        isConnecting = false
        connectTask = nil
        isConnected = true
        reconnectBackoff.reset()
        reconcileConnectionDiagnostics()
        reconcileStatusStream()
         
         
         
        isReopeningControlSession = false
        clearLastError()
        trafficReducer = ClashTrafficReducer()
        traffic = ClashTrafficSnapshot()
        recordRouteControl(kind: .runtimeControlConnected)
        Task { await refreshMetadata() }
        diagnosticsBackoff.reset()
        if !sceneManagedDiagnostics || diagnosticScene != .active {
            scheduleRuntimeDiagnosticsRefresh()
        }
        Task { await consumeStartupOOMEvidence() }
    }

    private func handleDisconnected(_ message: String, token: UInt64) {
        guard token == generation else { return }
        recordRouteControl(
            kind: .runtimeControlDisconnected,
            failureCategory: "stream-disconnected"
        )
        streamDisconnectCount += 1
        isConnecting = false
        connectTask = nil
         
         
        modeStreamSettler.cancel()
        closeNativeControlAttempt()
        isConnected = false
        runningListenerPorts = nil
        trafficReducer = ClashTrafficReducer()
        traffic = ClashTrafficSnapshot()
        publishMemory(MemoryState(inuse: 0, footprint: nil))
        peerSchemaVersion = 0
        peerCoreVersion = "—"
        peerCapabilities = []
        publishRuntimeDiagnostics(nil)
        if !message.isEmpty { lastError = message }
        noteConnectFailure("stream-disconnected:" + (message.isEmpty ? "(no-reason-given)" : message))
        scheduleReconnect(token: generation)
    }

     
     
     
     
    private func noteConnectFailure(_ message: String, now: Date = Date()) {
        guard ControlConnectFailureLogGate.shouldLog(message, after: lastConnectFailureLog, now: now) else { return }
        lastConnectFailureLog = (message, now)
        ClashLogStore.shared.append("control-session/" + message, stream: .app, level: .warning)
    }

     
     
     
     
    static let attemptWedgeSeconds: TimeInterval = 45

    private func armAttemptWatchdog(token: UInt64) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.attemptWedgeSeconds * 1_000_000_000))
            guard let self, token == self.generation, self.isConnecting, self.wantsConnection else { return }
            self.noteConnectFailure("attempt-wedged:\(Int(Self.attemptWedgeSeconds))s;reopening")
            self.reconnectIfNeeded()
        }
    }

     
     
    private nonisolated static func awaitBounded(_ task: Task<Void, Never>?, seconds: Double) async {
        guard let task else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func scheduleReconnect(token: UInt64) {
        guard wantsConnection, token == generation else { return }
        connectTask?.cancel()
        let delay = reconnectBackoff.nextDelay()
        connectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, token == self.generation, self.wantsConnection else { return }
            self.connectTask = nil
            self.connectIfNeeded()
        }
    }

     
     
     
    func setStatusDemand(_ wanted: Bool) {
        guard statusDemand != wanted else { return }
        statusDemand = wanted
        statusGraceTask?.cancel()
        statusGraceTask = nil
        if wanted {
            reconcileStatusStream()
            return
        }
        guard statusClient != nil else { return }
        let grace = statusCloseGraceNanoseconds
        statusGraceTask = Task { [weak self] in
            if grace > 0 { try? await Task.sleep(nanoseconds: grace) }
            guard !Task.isCancelled, let self else { return }
            self.statusGraceTask = nil
            self.reconcileStatusStream()
        }
    }

    var isStatusStreamOpen: Bool { statusClient != nil }

     
     
    var statusFiguresArePaused: Bool {
        separatesStatusStream && isConnected && statusClient == nil
    }

    private func reconcileStatusStream() {
        guard separatesStatusStream, !false else { return }
        let wanted = statusDemand && isConnected
        if !wanted {
            statusRetryTask?.cancel()
            statusRetryTask = nil
            closeStatusClient()
            return
        }
        guard statusClient == nil else { return }
        statusRetryTask?.cancel()
        statusRetryTask = nil
        statusEpoch &+= 1
        let epoch = statusEpoch
        let handler = makeCommandHandler()
        handler.statusEpoch = epoch
         
         
        lastMemorySequence = 0
        let options = ClashAPIClientOptions()
        options.addCommand(ClashCommandStatus)
        options.onlyStatisticsProxy = TrafficStatisticsSettings.countsOnlyProxy()
        guard let opened = statusClientFactory(controlSocketPath, handler, options) else {
            statusFailed(epoch: epoch, opened: false)
            return
        }
        statusClient = opened
        let previous = statusChain
        statusChain = Task.detached { [weak self] in
             
             
            await Self.awaitBounded(previous, seconds: 5)
            do {
                try opened.connect()
            } catch {
                await self?.statusFailed(epoch: epoch, opened: true)
                return
            }
            await self?.statusConnected(epoch: epoch)
             
             
             
             
             
             
            if let memory = try? opened.memorySnapshot() { handler.writeMemory(memory) }
        }
    }

    private func statusConnected(epoch: UInt64) {
        guard epoch == statusEpoch, statusClient != nil else { return }
        statusBackoff.reset()
         
         
        applyTrafficStatisticsPreference()
    }

     
     
     
    private func statusFailed(epoch: UInt64, opened: Bool) {
        guard epoch == statusEpoch else { return }
        if opened {
            guard statusClient != nil else { return }
            closeStatusClient()
        }
        let delay = statusBackoff.nextDelay()
        ClashLogStore.shared.append(
            "traffic stream unavailable; retrying in \(Int(delay)) s",
            stream: .app,
            level: .warning
        )
        statusRetryTask?.cancel()
        statusRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.statusRetryTask = nil
            self.reconcileStatusStream()
        }
    }

     
     
     
    private func closeStatusClient() {
        guard let old = statusClient else { return }
        statusClient = nil
        statusEpoch &+= 1
        trafficReducer = ClashTrafficReducer()
        traffic = ClashTrafficSnapshot()
        let opening = statusChain
        statusChain = Task.detached {
            await Self.awaitBounded(opening, seconds: 5)
            old.close()
             
             
            await opening?.value
            old.close()
        }
    }

    private func cancelStatusTimers() {
        statusGraceTask?.cancel()
        statusGraceTask = nil
        statusRetryTask?.cancel()
        statusRetryTask = nil
        statusBackoff.reset()
    }

     
     
     
    func sweepFootprintBytes() async -> Int64 {
        let cached = memoryFootprintBytes
        guard cached <= 0, separatesStatusStream, statusClient == nil,
              let client, isConnected else { return cached }
        let payload = await Task.detached { () -> String? in
            try? client.memorySnapshot()
        }.value
        guard let data = payload?.data(using: .utf8),
              let memory = try? JSONDecoder().decode(MemoryPayload.self, from: data)
        else { return 0 }
        return max(0, memory.footprint ?? 0)
    }

    fileprivate func acceptsStatusFrame(epoch: UInt64?) -> Bool {
        guard let epoch else { return true }
        return epoch == statusEpoch && statusClient != nil
    }

    private func handleTraffic(_ payload: TrafficPayload, token: UInt64) {
        guard token == generation else { return }
        traffic = trafficReducer.consume(
            up: payload.up,
            down: payload.down,
            upTotal: payload.upTotal,
            downTotal: payload.downTotal
        )
        trafficSampleCount += 1
        if traffic.upload > 0 { uploadNonZeroSampleCount += 1 }
        if traffic.download > 0 { downloadNonZeroSampleCount += 1 }
        peakUploadBytesPerSecond = max(peakUploadBytesPerSecond, traffic.upload)
        peakDownloadBytesPerSecond = max(peakDownloadBytesPerSecond, traffic.download)
    }

    private func handleMemory(
        _ payload: MemoryPayload, receipt: MemoryReceipt, token: UInt64
    ) {
         
         
        guard token == generation, receipt.sequence > lastMemorySequence else { return }
        lastMemorySequence = receipt.sequence
        let footprint: MemoryFootprintSample? = payload.footprint.flatMap { bytes in
            guard bytes > 0 else { return nil }
            return MemoryFootprintSample(
                bytes: bytes, receivedAt: receipt.receivedAt, generation: token
            )
        }
        publishMemory(MemoryState(inuse: max(0, payload.inuse), footprint: footprint))
    }

    private func publishMemory(_ state: MemoryState) {
         
         
         
        memoryState = state
        guard !isPublishingMemory else { return }
        isPublishingMemory = true
        defer { isPublishingMemory = false }
        repeat {
            memoryBytes = memoryState.inuse
             
             
             
        } while memoryBytes != memoryState.inuse
    }

     
     
     
    static func logSubscriptionLevel(forDisplay level: String) -> String {
        level.lowercased() == "debug" ? "debug" : "info"
    }

     
     
     
     
     
     
    private var wantedLogSubscription: String? {
        Self.logSubscription(recording: logRecordingEnabled(), displayLevel: logDisplayLevel)
    }

    static func logSubscription(recording: Bool, displayLevel: String) -> String? {
        recording ? logSubscriptionLevel(forDisplay: displayLevel) : nil
    }

    func setLogDisplayLevel(_ level: String) {
        logDisplayLevel = level.lowercased()
         
         
         
         
         
        guard wantedLogSubscription != subscribedLogLevel,
              client != nil || isConnecting else { return }
        reconnectIfNeeded()
    }

     
     
    func refreshLogDisplayLevel(from defaults: UserDefaults? = nil) {
        setLogDisplayLevel(ClashLogSettings.liveStreamLevel(from: defaults ?? logLevelDefaults))
    }

    var logDisplayLevelForTesting: String { logDisplayLevel }

    private func handleLog(_ payload: LogPayload, token: UInt64) {
        guard token == generation, logDisplayLevel != "silent" else { return }
        let levels = ["debug": 0, "info": 1, "warning": 2, "error": 3, "silent": 4]
        guard (levels[payload.type.lowercased()] ?? 3) >= (levels[logDisplayLevel] ?? 1) else { return }
         
        enqueueLogLines([
            "\(payload.type.uppercased()) \(payload.payload)",
        ])
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private let modeStreamSettler = TrailingEdgeSettler(
        windowNanoseconds: TrailingEdgeSettler.modeStreamWindowNanoseconds
    )

    private func handleMode(_ json: String, token: UInt64) {
        guard token == generation else { return }
        modeStreamSettler.submit { [weak self] in
            guard let self, token == self.generation else { return }
            self.applyConfigs(json, source: "mode-stream")
            self.adoptStreamSelection(json)
        }
    }

     
     
     
    private var announcedSelection: [String: String] = [:]

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func adoptStreamSelection(_ json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any],
              let selected = object["selected"] as? [String: String]
        else { return }
        guard selected != announcedSelection else { return }
        let wasFirstMessage = announcedSelection.isEmpty
        announcedSelection = selected
        guard !wasFirstMessage else { return }
        selectionAnnouncements &+= 1
    }

     
     
     
     
     
     
     
     
    @Published private(set) var selectionAnnouncements = 0

    private func enqueueLogLines(_ lines: [String]) {
        guard logRecordingEnabled(), !lines.isEmpty else { return }
        pendingLogs.append(contentsOf: lines)
        guard logBatchTask == nil else { return }
        if logs.isEmpty {
            flushLogs()
            return
        }
        logBatchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.logBatchNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushLogs()
        }
    }

    private func flushLogs() {
        logBatchTask = nil
        guard logRecordingEnabled() else { pendingLogs.removeAll(); return }
        guard !pendingLogs.isEmpty || pendingLogs.dropped > 0 else { return }
        var buffer = ClashLogBuffer(maximumBytes: 1024 * 1024, maximumCount: Self.logMaxLines)
        buffer.append(contentsOf: logs)
        buffer.append(contentsOf: pendingLogs.lines)
        if pendingLogs.dropped > 0 {
            buffer.append(contentsOf: ["WARNING Log display busy; dropped \(pendingLogs.dropped) lines."])
        }
        pendingLogs.removeAll(keepingCapacity: true)
        logs = buffer.lines
    }

     
     
     
     
    private var runtimeIdentityCache: RuntimeIdentityCache { connectionRuntimeFeed.runtimeIdentityCache }

    private func currentRouteContext() -> RuntimeRouteContext {
        let identity = runtimeIdentityCache.current()
        return RuntimeRouteContext(
            profileID: identity?.profileID ?? "unavailable",
            profileRevision: identity?.revision ?? "unavailable",
            coreProcessIdentifier:
                runtimeDiagnostics?.processIdentifier ?? 0,
            coreStartTimeUnix:
                runtimeDiagnostics?.startTimeUnix ?? 0,
            mode: mode
        )
    }

    private func recordRouteControl(
        kind: RuntimeRouteEvidence.Kind,
        selectionGroup: String? = nil,
        requestedMember: String? = nil,
        confirmedMember: String? = nil,
        resolvedMember: String? = nil,
        failureCategory: String? = nil
    ) {
        let context = currentRouteContext()
        recordRouteEvidence([
            RuntimeRouteEvidence(
                kind: kind,
                profilePointerID: context.profileID,
                profilePointerRevision: context.profileRevision,
                coreProcessIdentifier:
                    context.coreProcessIdentifier,
                coreStartTimeUnix: context.coreStartTimeUnix,
                mode: context.mode,
                selectionGroup: selectionGroup,
                requestedMember: requestedMember,
                confirmedMember: confirmedMember,
                resolvedMember: resolvedMember,
                failureCategory: failureCategory
            ),
        ])
    }

    private func recordRouteEvidence(
        _ evidence: [RuntimeRouteEvidence]
    ) {
        guard !false, !evidence.isEmpty else {
            return
        }
        enqueueLogLines(evidence.compactMap { try? $0.logLine() })
        let journal = routeEvidenceJournal
        Task { try? await journal.append(evidence) }
    }

     
     
     
    func applyConfigs(
        _ json: String,
        source: String = "?",
        modeWritesAtRequest: UInt64? = nil,
        request: UInt64? = nil
    ) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let currentMode = object["mode"] as? String
        else { return }
         
         
         
         
        if let ports = RunningListenerPorts.read(configs: object), request.map({ $0 >= listenersAdoptedFrom }) ?? true {
            if let request { listenersAdoptedFrom = request }
            if ports != runningListenerPorts { runningListenerPorts = ports }
        }
         
         
         
         
         
         
         
        if let writes = modeWritesAtRequest, writes != localModeWrites {
            return
        }
         
         
         
         
        guard mode != currentMode else { return }
         
         
         
         
         
         
         
        {
            let was = mode
             
             
             
             
             
            ClashLogStore.shared.append(
                "outbound mode  \(was) -> \(currentMode)  from=\(source)",
                stream: .app, level: .warning)
        }()
        mode = currentMode
         
         
         
         
        localModeWrites &+= 1
    }

    private func updateSeedSelection(group: String, name: String) {
        guard let proxiesData,
              var root = try? JSONSerialization.jsonObject(with: proxiesData) as? [String: Any],
              var proxies = root["proxies"] as? [String: Any],
              var selected = proxies[group] as? [String: Any]
        else { return }
        selected["now"] = name
         
         
         
         
         
        if ["urltest", "url-test", "fallback"].contains(
            ((selected["type"] as? String) ?? "").lowercased()
        ) {
            selected["fixed"] = name
        }
        proxies[group] = selected
        root["proxies"] = proxies
        self.proxiesData = try? JSONSerialization.data(withJSONObject: root)
    }
}

private extension ClashCommandClient {
    struct TrafficPayload: Decodable {
        let up: Int64
        let down: Int64
        let upTotal: Int64
        let downTotal: Int64
    }

    struct MemoryState {
        let inuse: Int64
        let footprint: MemoryFootprintSample?
    }

    struct MemoryFootprintSample {
        let bytes: Int64
        let receivedAt: UInt64
        let generation: UInt64
    }

    struct MemoryReceipt {
        let receivedAt: UInt64
        let sequence: UInt64
    }

    struct MemoryPayload: Decodable {
        let inuse: Int64
        let footprint: Int64?
        private enum CodingKeys: String, CodingKey { case inuse, footprint }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
             
             
            inuse = (try? values.decode(Int64.self, forKey: .inuse)) ?? 0
            footprint = try? values.decode(Int64.self, forKey: .footprint)
        }

        private init() { inuse = 0; footprint = nil }
        static let unknown = MemoryPayload()
    }

    struct LogPayload: Decodable {
        let type: String
        let payload: String
    }

    final class HandlerProxy: NSObject, ClashAPIClientHandlerProtocol {
        weak var owner: ClashCommandClient?
        let token: UInt64

        let now: @Sendable () -> UInt64
        let enqueueMemory: ClashMemoryDelivery
        let recordLogs: @Sendable () -> Bool
        let logDeliveryBudget = ClashLogBudget(maximumBytes: 256 * 1024, maximumCount: 256)
        private let memoryReceiptLock = NSLock()
        private var memorySequence: UInt64 = 0

        private func nextMemoryReceipt() -> MemoryReceipt {
            memoryReceiptLock.lock()
            defer { memoryReceiptLock.unlock() }
            memorySequence &+= 1
            return MemoryReceipt(receivedAt: now(), sequence: memorySequence)
        }

        init(owner: ClashCommandClient, token: UInt64,
             now: @escaping @Sendable () -> UInt64,
             enqueueMemory: @escaping ClashMemoryDelivery,
             recordLogs: @escaping @Sendable () -> Bool) {
            self.owner = owner
            self.token = token
            self.now = now
            self.enqueueMemory = enqueueMemory
            self.recordLogs = recordLogs
        }

         
         
         
        var statusEpoch: UInt64?

        func connected() {
            if statusEpoch != nil { return }
            Task { @MainActor [weak owner] in owner?.handleConnected(token: token) }
        }

        func disconnected(_ message: String?) {
            if let statusEpoch {
                Task { @MainActor [weak owner] in owner?.statusFailed(epoch: statusEpoch, opened: true) }
                return
            }
            Task { @MainActor [weak owner] in owner?.handleDisconnected(message ?? "", token: token) }
        }

        func writeTraffic(_ message: String?) {
            guard let data = message?.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(TrafficPayload.self, from: data)
            else { return }
            let statusEpoch = statusEpoch
            Task { @MainActor [weak owner] in
                guard let owner, owner.acceptsStatusFrame(epoch: statusEpoch) else { return }
                owner.handleTraffic(payload, token: token)
            }
        }

        func writeMemory(_ message: String?) {
             
             
            let receipt = nextMemoryReceipt()
            let payload = message?.data(using: .utf8).flatMap {
                try? JSONDecoder().decode(MemoryPayload.self, from: $0)
            } ?? .unknown
            enqueueMemory { [weak owner, token, statusEpoch] in
                guard let owner, owner.acceptsStatusFrame(epoch: statusEpoch) else { return }
                owner.handleMemory(payload, receipt: receipt, token: token)
            }
        }

        func writeLogs(_ message: String?) {
            guard recordLogs(), let message else { return }
            let size = message.utf8.count
            let budget = logDeliveryBudget
            guard budget.reserve(size) else { return }
            guard let data = message.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(LogPayload.self, from: data) else {
                budget.release(size)
                return
            }
            Task { @MainActor [weak owner, token] in
                owner?.handleLog(payload, token: token)
                let lost = budget.release(size)
                if lost > 0 {
                    owner?.handleLog(LogPayload(type: "warning",
                        payload: "Log delivery busy; dropped \(lost) lines."), token: token)
                }
            }
        }

        func writeConnections(_: String?) {}

        func writeMode(_ message: String?) {
            guard let message else { return }
            Task { @MainActor [weak owner] in owner?.handleMode(message, token: token) }
        }
    }
}


 
 
protocol StatusStreamClient: AnyObject {
    func connect() throws
    func close()
    func setOnlyStatisticsProxy(_ enabled: Bool) throws
    func memorySnapshot() throws -> String
}

typealias StatusStreamClientFactory = @MainActor (
    _ socketPath: String?,
    _ handler: ClashAPIClientHandlerProtocol,
    _ options: ClashAPIClientOptions
) -> StatusStreamClient?

extension ClashAPIClient: StatusStreamClient {
    func memorySnapshot() throws -> String {
        var error: NSError?
        let value = getMemory(&error)
        if let error { throw error }
        return value
    }
}

extension ClashCommandClient {
    static let nativeStatusClient: StatusStreamClientFactory = { socketPath, handler, options in
        guard let socketPath else { return nil }
        var error: NSError?
        let client = ClashNewAPIClientWithOptions(socketPath, handler, options, &error)
        if let error {
            ClashLogStore.shared.append(
                "traffic stream client unavailable: \(error.localizedDescription)",
                stream: .app,
                level: .warning
            )
        }
        return client
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum AppGroupDirectFetch {
     
    static weak var session: ClashCommandClient?

     
     
    static var socketPath: () -> String? = {
        ClashAppIdentifiers.appGroupContainer?.appendingPathComponent("clash.sock").path
    }

     
     
    static var tunnelIsRunning: () async -> Bool = { await systemSaysTheTunnelRuns() } {
        didSet { lastReading = nil }
    }

     
     
     
     
     
    static let readingLifetime: TimeInterval = 5
    private static var lastReading: (at: Date, running: Bool)?

     
     
     
    private static func tunnelRuns(fresh: Bool = false) async -> Bool {
        if !fresh, let last = lastReading, Date().timeIntervalSince(last.at) < readingLifetime {
            return last.running
        }
        let running = await tunnelIsRunning()
        lastReading = (Date(), running)
        return running
    }

     
    static func isUsable(fresh: Bool = false) async -> Bool {
        if let session, session.isConnected { return true }
        guard let path = socketPath(), FileManager.default.fileExists(atPath: path) else { return false }
        return await tunnelRuns(fresh: fresh)
    }

    static func perform(_ request: URLRequest, maxBytes: Int, timeout: TimeInterval,
                        redirectPolicy: DownloadRedirectPolicy) async throws -> DownloadResult {
        do {
            return try await fetch(request, maxBytes: maxBytes, timeout: timeout, redirectPolicy: redirectPolicy)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DownloadError {
             
            throw error
        } catch is DirectFetchUnavailable {
            throw DirectFetchUnavailable()
        } catch {
             
             
             
             
             
            if !(await isUsable(fresh: true)) {
                ClashLogStore.shared.append(
                    "direct fetch: the tunnel went during the call (\(error.localizedDescription))",
                    stream: .app, level: .info)
                throw DirectFetchUnavailable()
            }
            throw error
        }
    }

    private static func fetch(_ request: URLRequest, maxBytes: Int, timeout: TimeInterval,
                              redirectPolicy: DownloadRedirectPolicy) async throws -> DownloadResult {
        if let session, session.isConnected {
            return try await session.fetchDirect(request, maxBytes: maxBytes, timeout: timeout,
                                                 redirectPolicy: redirectPolicy)
        }
        guard let path = socketPath(), FileManager.default.fileExists(atPath: path),
              await tunnelRuns() else { throw DirectFetchUnavailable() }
        var error: NSError?
        guard let client = ClashNewAPIClientWithOptions(path, SessionlessHandler(), ClashAPIClientOptions(), &error)
        else {
            ClashLogStore.shared.append(
                "direct fetch: no client for \(path): \(error?.localizedDescription ?? "unknown")",
                stream: .app, level: .warning)
            throw DirectFetchUnavailable()
        }
        defer { client.close() }
        return try await ClashCommandClient.fetchDirect(
            request, maxBytes: maxBytes, timeout: timeout, redirectPolicy: redirectPolicy,
            client: { client },
            call: { seconds, work in
                try await ClashCommandClient.boundedSessionlessCoreCall("direct-fetch", seconds: seconds, work)
            }
        )
    }

     
     
    private static func systemSaysTheTunnelRuns() async -> Bool {
#if os(macOS)
        let provider = ClashAppIdentifiers.macPacketTunnelExtensionBundleID
#else
        let provider = ClashAppIdentifiers.packetTunnelExtensionBundleID
#endif
        return (try? await VPNController.withNETimeout(seconds: 5, .nePreferencesTimeout) {
            try await NETunnelProviderManager.loadAllFromPreferences().contains { manager in
                (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == provider
                    && [.connected, .reasserting].contains(manager.connection.status)
            }
        }) ?? false
    }

     
     
    private final class SessionlessHandler: NSObject, ClashAPIClientHandlerProtocol {
        func connected() {}
        func disconnected(_ message: String?) {}
        func writeConnections(_ message: String?) {}
        func writeLogs(_ message: String?) {}
        func writeMemory(_ message: String?) {}
        func writeMode(_ message: String?) {}
        func writeTraffic(_ message: String?) {}
    }
}

 
 
typealias ClashMemoryDelivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

enum ClashMemoryClock {
    private static let scale: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t()
        mach_timebase_info(&value)
        return value
    }()

    static func now() -> UInt64 {
        let ticks = mach_continuous_time()
        let numerator = UInt64(scale.numer)
        let denominator = UInt64(scale.denom)
        return (ticks / denominator) * numerator + (ticks % denominator) * numerator / denominator
    }
}

 
 
enum ProviderTunnelCheck: Equatable {
     
     
    case answered(ProviderUpdateAnswer)
     
     
    case unavailable
     
    case busy
     
    case stillRunning
     
    case noSession
     
    case switched
    case cancelled
     
    case failed(String)
}

extension ClashCommandClient: NodePageSource {
    func summary() async throws -> NodeSummary {
        try await nodePage(Self.summaryPageLabel) { try Self.getProxiesSummary($0) }.decoded(NodeSummary.self)
    }

    func groupMembers(_ group: String, offset: Int, limit: Int) async throws -> GroupMembersPage {
        try await nodePage("group-members") {
            try Self.getGroupMembers($0, group, Int32(clamping: offset), Int32(clamping: limit))
        }.decoded(GroupMembersPage.self)
    }

    func providerNodes(_ provider: String, offset: Int, limit: Int) async throws -> ProviderNodesPage {
        try await nodePage("provider-nodes") {
            try Self.getProviderNodes($0, provider, Int32(clamping: offset), Int32(clamping: limit))
        }.decoded(ProviderNodesPage.self)
    }

    func proxiesPage(after: String, limit: Int) async throws -> ProxiesPage {
        try await nodePage("proxies-page") { try Self.getProxiesPage($0, after, Int32(clamping: limit)) }
            .decoded(ProxiesPage.self)
    }

    func search(_ query: String, offset: Int, limit: Int) async throws -> ProxySearchPage {
        try await nodePage("proxies-search") {
            try Self.searchProxies($0, query, Int32(clamping: offset), Int32(clamping: limit))
        }.decoded(ProxySearchPage.self)
    }

    func searchGroupMembers(_ group: String, query: String, offset: Int, limit: Int) async throws -> GroupMembersPage {
        try await nodePage("group-members-search") {
            try Self.searchGroupMembers($0, group, query, Int32(clamping: offset), Int32(clamping: limit))
        }.decoded(GroupMembersPage.self)
    }

    func lookup(_ name: String) async throws -> ProxyLookup {
        try await nodePage("proxy-lookup") { try Self.lookupProxy($0, name) }.decoded(ProxyLookup.self)
    }

     
     
     
     
    func nodeInformation(named name: String) async -> Data? {
        await Self.nodeInformation(named: name) { [weak self] after, limit in
            guard let self else { throw CancellationError() }
            return try await self.nodePage("proxies-page") { try Self.getProxiesPage($0, after, Int32(clamping: limit)) }
        }
    }

     
     
     
     
     
    static func nodeInformation(named name: String, page: (String, Int) async throws -> Data) async -> Data? {
        guard !name.isEmpty else { return nil }
        var after = String(String.UnicodeScalarView(name.unicodeScalars.dropLast()))
        for _ in 0..<8 {
            guard let data = try? await page(after, 64),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let proxies = object["proxies"] as? [String: Any] else { return nil }
            if let found = proxies[name] { return try? JSONSerialization.data(withJSONObject: found, options: [.sortedKeys]) }
             
            guard let next = object["next"] as? String, Array(next.utf8).lexicographicallyPrecedes(Array(name.utf8)) else {
                return nil
            }
            after = next
        }
        return nil
    }
}

 

extension ClashCommandClient {
     
     
     
     
    func compilePendingProviders(configuration: String, targetProfile: String) async throws -> [PendingProviderCompile] {
        guard let client, isConnected else { throw NodePageSourceError.unavailable }
        let token = generation
         
         
         
         
         
         
         
         
         
         
         
        guard Self.pendingCompileSlot.take() else { return [] }
        let json = try await ProfileActivationCoordinator.onCompilationQueue(
            deadline: 120, finished: { Self.pendingCompileSlot.give() }
        ) {
            try Self.compilePendingProviders(client, configuration, targetProfile)
        }
        guard let json else {
            throw CoreCallDeadline(label: "compile-pending-providers", seconds: 120)
        }
        guard token == generation, self.client === client, isConnected else { throw NodePageSourceError.unavailable }
        return try PendingProviderCompile.decode(json)
    }

     
    nonisolated static let pendingCompileSlot = PendingCompileSlot()

     
     
     
     
     
     
    func compilePendingProviders(container: URL) async -> [PendingProviderCompile] {
        let working = container.appendingPathComponent("working", isDirectory: true)
        let read = ProviderRefreshState.read(workingDirectory: working)
         
        pendingCompilesHandedOn.formIntersection(PendingProviderCompile.heldKeys(in: read))
        guard isConnected,
              let state = read,
              PendingProviderCompile.waits(in: state, excluding: pendingCompilesHandedOn),
              let sha256 = state.running?.configSHA256
        else { return [] }
         
         
         
         
        guard let configuration = await Task.detached(priority: .utility, operation: {
            Self.runningConfiguration(sha256: sha256, container: container)
        }).value else {
            handOnWhatTheCompileWouldTake(in: state, because: #"no stored configuration hashes to the running \#(sha256)"#)
            return []
        }
        do {
            let compiled = try await compilePendingProviders(configuration: configuration,
                                                             targetProfile: clashAppleRuntimeProfileName)
            for item in compiled {
                ClashLogStore.shared.append(
                    "pending compile  \(item.kind):\(item.name)  result=\(item.result?.rawValue ?? "-")"
                        + (item.error.map { "  error=\($0)" } ?? ""),
                    stream: .app)
            }
             
             
             
            let handedOn = PendingProviderCompile.couldNotTake(compiled, in: state)
            if !handedOn.isEmpty, let takes = takesWhatTheCompileCouldNotTake {
                pendingCompilesHandedOn.formUnion(handedOn.map(\.key))
                takes(handedOn)
            }
            return compiled
        } catch {
            let message = (error as NSError).localizedDescription
            if !message.contains(ClashSideUpdateStalePrefix) {
                ClashLogStore.shared.append("pending compile not run  reason=\(message)", stream: .app, level: .warning)
            }
             
             
             
             
             
            if !message.contains(ClashSideUpdateStalePrefix), !Task.isCancelled, !(error is CancellationError),
               !(error is NodePageSourceError), !(error is CoreCallDeadline) {
                handOnWhatTheCompileWouldTake(in: state, because: message)
            }
            return []
        }
    }

     
     
     
     
    nonisolated static func runningConfiguration(sha256: String, container: URL) -> String? {
        NodeLibraries.storedConfiguration(sha256: sha256, container: container,
                                          runsAs: ClashTunnelOutboundMode.firstTextWithAModeWrittenIn)
    }

     
     
     
     
    private func handOnWhatTheCompileWouldTake(in state: ProviderRefreshState, because reason: String) {
        let handedOn = PendingProviderCompile.compileTakes(in: state, excluding: pendingCompilesHandedOn)
        guard !handedOn.isEmpty, let takes = takesWhatTheCompileCouldNotTake else { return }
        ClashLogStore.shared.append(
            #"pending compile handed to a publication  sets=\#(handedOn.map(\.name).joined(separator: ","))  reason=\#(reason)"#,
            stream: .app, level: .warning)
        pendingCompilesHandedOn.formUnion(handedOn.map(\.key))
        takes(handedOn)
    }

     
     
     
     
     
     
     
    func startPendingCompiles(container: URL, interval: TimeInterval = 10) {
         
         
         
         
        if pendingCompileFollowUp != nil {
            pendingCompileAgain = true
            return
        }
        pendingCompileRun &+= 1
        let run = pendingCompileRun
        pendingCompileFollowUp = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.isConnected {
                self.pendingCompileAgain = false
                _ = await self.compilePendingProviders(container: container)
                if self.pendingCompileAgain { continue }
                let working = container.appendingPathComponent("working", isDirectory: true)
                guard PendingProviderCompile.waits(in: ProviderRefreshState.read(workingDirectory: working),
                                                   excluding: self.pendingCompilesHandedOn) else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            if let self, self.pendingCompileRun == run { self.pendingCompileFollowUp = nil }
        }
    }

    func stopPendingCompiles() {
        pendingCompileFollowUp?.cancel()
        pendingCompileFollowUp = nil
        pendingCompileAgain = false
        pendingCompileRun &+= 1
    }
}

 
final class PendingCompileSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
     
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
    func give() {
        lock.lock()
        taken = false
        lock.unlock()
    }
}

 
struct ProxyGroupPick: Equatable, Sendable {
    let group: String
    let member: String
}

 
 
 
 
 
 
 
 
 
 
enum ProxySelectionConnections {
     
     
     
    static func ids(in table: Data, movedBy picks: [ProxyGroupPick]) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: table) as? [String: Any] else { return nil }
        let connections: [[String: Any]]
        switch root["connections"] {
        case let rows as [[String: Any]]: connections = rows
        case is NSNull: connections = []
        default: return nil
        }
        guard !picks.isEmpty else { return [] }
        var seen = Set<String>()
        return connections.compactMap { connection in
            guard let id = connection["id"] as? String, !id.isEmpty, !seen.contains(id),
                  let chains = connection["chains"] as? [String],
                  picks.contains(where: { moved(chains, by: $0) }) else { return nil }
            seen.insert(id)
            return id
        }
    }

    private static func moved(_ chains: [String], by pick: ProxyGroupPick) -> Bool {
        guard let at = chains.firstIndex(of: pick.group) else { return false }
        return at == 0 || chains[at - 1] != pick.member
    }

     
    final class Refusals: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var last: Error?

        func note(_ error: Error) {
            lock.lock(); defer { lock.unlock() }
            count += 1
            last = error
        }

         
        func all(of attempts: Int) -> Error? {
            lock.lock(); defer { lock.unlock() }
            return count == attempts ? last : nil
        }
    }
}
