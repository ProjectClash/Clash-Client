import Foundation

 
 
 
 
 
 
 
 
 
public enum LatencyProbeNamePolicy {
     
    public static let builtinNames: Set<String> = [
        "COMPATIBLE", "DIRECT", "PASS", "PASS-RULE", "REJECT", "REJECT-DROP",
    ]

     
    public static let probeExcludedNames: Set<String> = []
}

public enum LatencyProbeFreshness: Int, Codable, Equatable, Sendable {
    case neverTested
    case failed
    case stale
    case fresh
}

public struct LatencyProbeGroup: Equatable, Sendable {
    public let name: String
    public let members: [String]
    public let selectedName: String?

    public init(name: String, members: [String], selectedName: String? = nil) {
        self.name = name
        self.members = members
        self.selectedName = selectedName
    }
}

public struct LatencyProbePlan: Equatable, Sendable {
    public let groups: [LatencyProbeGroup]
    public let visibleGroupNames: [String]
    public let freshnessByName: [String: LatencyProbeFreshness]
    public let excludedNames: Set<String>

    public init(
        groups: [LatencyProbeGroup],
        visibleGroupNames: [String] = [],
        freshnessByName: [String: LatencyProbeFreshness] = [:],
        excludedNames: Set<String> = []
    ) {
        self.groups = groups
        self.visibleGroupNames = visibleGroupNames
        self.freshnessByName = freshnessByName
        self.excludedNames = excludedNames
    }
}

public struct LatencyProbePolicy: Equatable, Sendable {
     
     
     
     
     
     
     
    public static let iPhone = LatencyProbePolicy(
        maxConcurrentProbes: 12,
        packetTunnelScaleTiers: true,
         
         
         
         
        restEveryProbes: 0,
        restNanoseconds: 0
    )
    public static let iPadOS = LatencyProbePolicy(
        maxConcurrentProbes: 12,
        packetTunnelScaleTiers: true,
         
         
         
         
        restEveryProbes: 0,
        restNanoseconds: 0
    )
     
     
     
    public static let tvOS = LatencyProbePolicy(
        maxConcurrentProbes: 12,
        packetTunnelScaleTiers: true,
        restEveryProbes: 0,
        restNanoseconds: 0
    )
    public static let macOS = LatencyProbePolicy(maxConcurrentProbes: 12)

     
     
     
    public static var currentPlatform: LatencyProbePolicy {
#if os(macOS)
        return .macOS
#elseif os(tvOS)
        return .tvOS
#else
        return .iPhone
#endif
    }

    public let maxConcurrentProbes: Int
    private let packetTunnelScaleTiers: Bool
     
     
     
     
     
     
    public var restEveryProbes: Int
    public var restNanoseconds: UInt64
     
     
    public var fixedConcurrentProbes: Int?
     
     
     
     
     
     
     
     
     
    public var deferredRetryInitialNanoseconds: UInt64 = 500_000_000
    public var deferredRetryMaxNanoseconds: UInt64 = 4_000_000_000
    public var deferredRetryWindowNanoseconds: UInt64 = 120_000_000_000

    public init(maxConcurrentProbes: Int) {
        self.maxConcurrentProbes = min(max(maxConcurrentProbes, 1), 16)
        packetTunnelScaleTiers = false
        restEveryProbes = 0
        restNanoseconds = 0
    }

    public init(
        maxConcurrentProbes: Int,
        packetTunnelScaleTiers: Bool,
        restEveryProbes: Int = 0,
        restNanoseconds: UInt64 = 0
    ) {
        self.maxConcurrentProbes = min(max(maxConcurrentProbes, 1), 16)
        self.packetTunnelScaleTiers = packetTunnelScaleTiers
        self.restEveryProbes = max(0, restEveryProbes)
        self.restNanoseconds = restNanoseconds
    }

     
     
     
     
     
     
     
    public func concurrentProbeCount(for targetCount: Int) -> Int {
        if let fixed = fixedConcurrentProbes { return min(max(fixed, 1), 16) }
        guard packetTunnelScaleTiers else { return maxConcurrentProbes }
        switch max(0, targetCount) {
        case ...160:
            return maxConcurrentProbes
        case ...512:
            return min(maxConcurrentProbes, 8)
        default:
             
             
             
             
             
             
             
             
             
             
             
             
             
            return min(maxConcurrentProbes, 8)
        }
    }

     
     
     
     
     
     
     
     
     
     
    public var probeFailureFloorNanoseconds: UInt64 {
        packetTunnelScaleTiers ? 100_000_000 : 0
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func usesBulkProviderHealth(
        for targetCount: Int,
        catalogCount: Int
    ) -> Bool {
        guard packetTunnelScaleTiers else { return true }
        return false
    }
}

public enum LatencyProbeOutcome: Equatable, Sendable {
    case success(milliseconds: Int)
    case failure
     
     
     
     
    case deferred
}

public enum LatencyProbeCancellationReason: Equatable, Sendable {
    case superseded
    case memoryPressure
    case backgrounded
    case disconnected
    case requested
    case taskCancelled
}

public actor LatencyProbeCancellation {
    private var storedReason: LatencyProbeCancellationReason?
     
     
     
     
     
     
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func cancel(reason: LatencyProbeCancellationReason) {
        if storedReason == nil {
            storedReason = reason
        }
         
        releaseWaiters()
    }

    public func reason() -> LatencyProbeCancellationReason? {
        storedReason
    }

    public func pause() {
        paused = true
    }

    public func resume() {
        paused = false
        releaseWaiters()
    }

    public var isPaused: Bool { paused }

     
     
    public func rest(nanoseconds: UInt64) {
        guard nanoseconds > 0, !paused else { return }
        paused = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await self?.resume()
        }
    }

     
    public func waitWhilePaused() async {
        while paused, storedReason == nil {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private func releaseWaiters() {
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

public struct LatencyProbeStarted: Equatable, Sendable {
    public let runID: UInt64
    public let name: String
    public let completedCount: Int
    public let totalCount: Int

    public init(runID: UInt64, name: String, completedCount: Int, totalCount: Int) {
        self.runID = runID
        self.name = name
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

public struct LatencyProbeResult: Equatable, Sendable {
    public let runID: UInt64
    public let name: String
    public let outcome: LatencyProbeOutcome
    public let completedCount: Int
    public let totalCount: Int

    public init(
        runID: UInt64, name: String, outcome: LatencyProbeOutcome,
        completedCount: Int, totalCount: Int
    ) {
        self.runID = runID
        self.name = name
        self.outcome = outcome
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

public struct LatencyProbeCancelled: Equatable, Sendable {
    public let runID: UInt64
    public let name: String
    public let reason: LatencyProbeCancellationReason
}

public struct LatencyProbeSummary: Equatable, Sendable {
    public let runID: UInt64
    public let completedCount: Int
    public let totalCount: Int
    public let cancellationReason: LatencyProbeCancellationReason?

    public init(
        runID: UInt64, completedCount: Int, totalCount: Int,
        cancellationReason: LatencyProbeCancellationReason?
    ) {
        self.runID = runID
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.cancellationReason = cancellationReason
    }
}

public enum LatencyProbeEvent: Equatable, Sendable {
    case started(LatencyProbeStarted)
    case result(LatencyProbeResult)
    case cancelled(LatencyProbeCancelled)
    case finished(LatencyProbeSummary)
}

public enum LatencyProbeScheduler {
     
     
    public static func orderedNames(for plan: LatencyProbePlan) -> [String] {
        let groups = plan.groups
        let available = Set(groups.flatMap(\.members)).subtracting(plan.excludedNames)
        var emitted = Set<String>()
        var result: [String] = []

        func append(_ name: String) {
            guard !name.isEmpty, available.contains(name), emitted.insert(name).inserted else {
                return
            }
            result.append(name)
        }

        for group in groups {
            if let selectedName = group.selectedName {
                append(selectedName)
            }
        }

        var groupsByName: [String: LatencyProbeGroup] = [:]
        for group in groups where groupsByName[group.name] == nil {
            groupsByName[group.name] = group
        }
         
         
         
         
         
         
        func visibleTier(_ isEligible: (String) -> Bool) {
            for groupName in plan.visibleGroupNames {
                guard let group = groupsByName[groupName] else { continue }
                for member in group.members where isEligible(member) {
                    append(member)
                }
            }
        }
        visibleTier { name in
            (plan.freshnessByName[name] ?? .neverTested) == .neverTested
        }
        visibleTier { name in
            switch plan.freshnessByName[name] ?? .neverTested {
            case .failed, .stale: return true
            case .neverTested, .fresh: return false
            }
        }
        visibleTier { _ in true }

        func appendRoundRobin(where isEligible: (String) -> Bool) {
            var indices = Array(repeating: 0, count: groups.count)
            var madeProgress = true
            while madeProgress {
                madeProgress = false
                for groupIndex in groups.indices {
                    let members = groups[groupIndex].members
                    while indices[groupIndex] < members.count {
                        let member = members[indices[groupIndex]]
                        indices[groupIndex] += 1
                        guard available.contains(member),
                              !emitted.contains(member),
                              isEligible(member) else { continue }
                        append(member)
                        madeProgress = true
                        break
                    }
                }
            }
        }

        appendRoundRobin { name in
            switch plan.freshnessByName[name] ?? .neverTested {
            case .neverTested, .failed, .stale:
                return true
            case .fresh:
                return false
            }
        }
        appendRoundRobin { _ in true }
        return result
    }

     
     
     
    public static func run(
        runID: UInt64,
        plan: LatencyProbePlan,
        policy: LatencyProbePolicy,
        cancellation: LatencyProbeCancellation = LatencyProbeCancellation(),
        onEvent: @escaping @Sendable (LatencyProbeEvent) async -> Void,
        probe: @escaping @Sendable (String) async -> LatencyProbeOutcome
    ) async -> LatencyProbeSummary {
        let names = orderedNames(for: plan)
        let queue = LatencyProbeWorkQueue(names: names)
        let workerCount = min(
            policy.concurrentProbeCount(for: names.count),
            names.count
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask {
                    worker: while !Task.isCancelled,
                          await cancellation.reason() == nil {
                        await cancellation.waitWhilePaused()
                        guard await cancellation.reason() == nil else { break }
                        let item: LatencyProbeWorkQueue.Item
                        switch await queue.next(now: DispatchTime.now().uptimeNanoseconds) {
                        case .done:
                            break worker
                        case .wait(let nanoseconds):
                             
                             
                             
                             
                            try? await Task.sleep(nanoseconds: min(nanoseconds, 250_000_000))
                            continue worker
                        case .item(let next):
                            item = next
                        }
                        await onEvent(.started(.init(
                            runID: runID,
                            name: item.name,
                            completedCount: item.completedCount,
                            totalCount: names.count
                        )))

                        let probeStart = DispatchTime.now()
                        let outcome = await probe(item.name)
                        if case .deferred = outcome,
                           await queue.deferForRetry(
                               item.name,
                               now: DispatchTime.now().uptimeNanoseconds,
                               policy: policy
                           ) {
                             
                             
                             
                            continue
                        }
                        if case .failure = outcome {
                            let floor = policy.probeFailureFloorNanoseconds
                            let elapsed = DispatchTime.now().uptimeNanoseconds
                                &- probeStart.uptimeNanoseconds
                            if elapsed < floor {
                                try? await Task.sleep(nanoseconds: floor - elapsed)
                            }
                        }
                        let cancellationReason = await cancellation.reason()
                            ?? (Task.isCancelled ? .taskCancelled : nil)
                        if let cancellationReason {
                            await onEvent(.cancelled(.init(
                                runID: runID,
                                name: item.name,
                                reason: cancellationReason
                            )))
                            break
                        }

                        let completedCount = await queue.complete()
                        if policy.restEveryProbes > 0,
                           completedCount % policy.restEveryProbes == 0 {
                            await cancellation.rest(nanoseconds: policy.restNanoseconds)
                        }
                        await onEvent(.result(.init(
                            runID: runID,
                            name: item.name,
                            outcome: outcome,
                            completedCount: completedCount,
                            totalCount: names.count
                        )))
                    }
                }
            }
            await group.waitForAll()
        }

        let completedCount = await queue.completedCount
        let cancellationReason = await cancellation.reason()
            ?? (Task.isCancelled ? .taskCancelled : nil)
        let summary = LatencyProbeSummary(
            runID: runID,
            completedCount: completedCount,
            totalCount: names.count,
            cancellationReason: cancellationReason
        )
        await onEvent(.finished(summary))
        return summary
    }
}

private actor LatencyProbeWorkQueue {
    struct Item: Sendable {
        let name: String
        let completedCount: Int
    }

    enum Next: Sendable {
        case item(Item)
         
        case wait(nanoseconds: UInt64)
        case done
    }

    private struct Retry {
        let name: String
        let readyAt: UInt64
    }

    private let names: [String]
    private var nextIndex = 0
    private(set) var completedCount = 0
     
    private var retries: [Retry] = []
     
    private var deferrals: [String: (first: UInt64, count: Int)] = [:]

    init(names: [String]) {
        self.names = names
    }

     
     
     
    func next(now: UInt64) -> Next {
        if nextIndex < names.count {
            defer { nextIndex += 1 }
            return .item(Item(name: names[nextIndex], completedCount: completedCount))
        }
        guard let soonest = retries.indices.min(by: { retries[$0].readyAt < retries[$1].readyAt }) else {
            return .done
        }
        let retry = retries[soonest]
        guard retry.readyAt <= now else { return .wait(nanoseconds: retry.readyAt - now) }
        retries.remove(at: soonest)
        return .item(Item(name: retry.name, completedCount: completedCount))
    }

     
    func deferForRetry(_ name: String, now: UInt64, policy: LatencyProbePolicy) -> Bool {
        let record = deferrals[name] ?? (first: now, count: 0)
        guard now &- record.first < policy.deferredRetryWindowNanoseconds else { return false }
        let doubled = policy.deferredRetryInitialNanoseconds
            .multipliedReportingOverflow(by: UInt64(1) << UInt64(min(record.count, 32)))
        let backoff = doubled.overflow
            ? policy.deferredRetryMaxNanoseconds
            : min(doubled.partialValue, policy.deferredRetryMaxNanoseconds)
        deferrals[name] = (first: record.first, count: record.count + 1)
        retries.append(Retry(name: name, readyAt: now &+ backoff))
        return true
    }

    func complete() -> Int {
        completedCount += 1
        return completedCount
    }
}
