import BackgroundTasks
import Foundation

 
 
 
 
 
 
 
enum ClashTVAutoUpdate {
    static let taskIdentifier = ClashAppIdentifiers.backgroundRefreshTask
    static let foregroundScanInterval: TimeInterval = 20 * 60
    static let foregroundScanKey = "clash.tv.autoUpdate.lastForegroundScan"
     
     
    static let minimumLead: TimeInterval = 3600

     
     
     
    static func isDue(_ row: ClashTVSubscription, now: Date) -> Bool {
        guard let hours = row.updateIntervalHours, hours > 0, row.hasFetchableAddress else { return false }
        guard let last = row.updatedAt else { return true }
        if last > now { return false }
        return last.addingTimeInterval(TimeInterval(hours) * 3600).timeIntervalSince(now) <= 0
    }

     
     
     
    static func nextEligibility(rows: [ClashTVSubscription], now: Date) -> Date? {
        let dates = rows.compactMap { row -> Date? in
            guard let hours = row.updateIntervalHours, hours > 0, row.hasFetchableAddress else { return nil }
            let due = (row.updatedAt ?? now).addingTimeInterval(TimeInterval(hours) * 3600)
            return max(due, now.addingTimeInterval(minimumLead))
        }
        return dates.min()
    }

    static func shouldScanOnForeground(now: Date, lastScan: Date?, minimumInterval: TimeInterval = foregroundScanInterval) -> Bool {
        guard let lastScan else { return true }
        if lastScan > now { return false }
        return now.timeIntervalSince(lastScan) >= minimumInterval
    }

     
     
     
    @MainActor
    static func scanOnForegroundIfDue(
        store: ClashTVSubscriptionStore,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        refresh: (ClashTVSubscription) async -> Void
    ) async {
        let lastScan = defaults.object(forKey: foregroundScanKey) as? Date
        guard shouldScanOnForeground(now: now, lastScan: lastScan) else { return }
        defaults.set(now, forKey: foregroundScanKey)
        guard let current = store.current, isDue(current, now: now) else { return }
        ClashLogStore.shared.append("tv auto update: row in use is due (interval \(current.updateIntervalHours ?? 0) h)", stream: .app)
        await refresh(current)
    }

     

     
     
     
     
    static func register(handler: @escaping () async -> Bool) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let work = Task {
                let success = await handler()
                task.setTaskCompleted(success: success)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule(earliest date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }

     
     
     
     
     
    @MainActor
    static func refreshInBackground(now: Date = Date()) async -> Bool {
        var store = ClashTVSubscriptionStore(defaults: .standard)
        guard let current = store.current, isDue(current, now: now),
              let container = ClashTVTunnelController.defaultContainer
        else { return true }
         
         
        let previous = (try? ConfigResourceStore(containerURL: container))?.activeIdentityOrNil()
        do {
            _ = try await ClashTVConfigPipeline(container: container, inBackground: true).activate(subscription: current) { _ in }
            store.markUpdated(current.id, at: now)
            keepBackgroundOutcome(.init(subscriptionID: current.id, at: now, failure: nil, previous: previous))
            ClashLogStore.shared.append("tv auto update: background fetch published", stream: .app)
            return true
        } catch {
            keepBackgroundOutcome(.init(subscriptionID: current.id, at: now, failure: error.localizedDescription, previous: previous))
            ClashLogStore.shared.append("tv auto update: background fetch failed  reason=\(error.localizedDescription)", stream: .app, level: .warning)
            return false
        }
    }

     
    struct BackgroundOutcome: Codable, Equatable {
        let subscriptionID: URL
        let at: Date
         
        let failure: String?
         
         
        var previous: ActiveConfigurationPointer? = nil
    }

    static let backgroundOutcomeKey = "clash.tv.autoUpdate.backgroundOutcome"

    static func keepBackgroundOutcome(_ outcome: BackgroundOutcome, defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(outcome), forKey: backgroundOutcomeKey)
    }

     
    static func takeBackgroundOutcome(defaults: UserDefaults = .standard) -> BackgroundOutcome? {
        guard let data = defaults.data(forKey: backgroundOutcomeKey) else { return nil }
        defaults.removeObject(forKey: backgroundOutcomeKey)
        return try? JSONDecoder().decode(BackgroundOutcome.self, from: data)
    }
}
