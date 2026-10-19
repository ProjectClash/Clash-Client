import BackgroundTasks
import Foundation
import ClashClientKit
#if canImport(UIKit)
import UIKit
#endif

 
 
enum ProfilesDueForRefresh {
    static func select(profiles: [Profile], now: Date) -> [Profile] {
        profiles.filter { profile in
            guard profile.autoUpdate, case .url = profile.source else { return false }
            guard let last = profile.lastUpdatedAt else { return true }
            return last.addingTimeInterval(TimeInterval(profile.updateIntervalHours) * 3600) <= now
        }
    }
}

extension Notification.Name {
     
     
     
     
     
     
     
     
    static let clashConfigurationSourcesRefreshed = Notification.Name("ClashConfigurationSourcesRefreshed")
    static let clashActiveConfigurationRepublished = Notification.Name("ClashActiveConfigurationRepublished")
}

 
 
 
 
 
 
 
 
 
 
 
 
 
enum ConfigurationSourcesDueForRefresh {
    static func select(sources: [ConfigurationSourceRecord], now: Date) -> [ConfigurationSourceRecord] {
        sources.filter { source in
            guard case .subscription = source.origin, source.isRetainedSnapshot != true,
                  let hours = source.updateIntervalHours, hours > 0 else { return false }
            return source.updatedAt.addingTimeInterval(TimeInterval(hours) * 3600) <= now
        }
    }
}

enum BackgroundRefreshPolicy {
    static func earliestEligibility(afterHours hours: Int, from date: Date = Date()) -> Date {
        date.addingTimeInterval(TimeInterval(max(1, hours)) * 3600)
    }
}

struct BackgroundRefreshOutcome: Equatable {
    var attempted = 0
    var updated = 0
    var unchanged = 0
    var failed = 0
     
     
     
     
    var sideDeferred = 0
    var cancelled = false
    var deferredReason: String? = nil
    var nextEligibleAt: Date? = nil

    var isSuccessful: Bool { !cancelled && failed == 0 }
    var isDeferred: Bool { deferredReason != nil }

     
     
     
     
    mutating func record(_ error: Error) {
        if SideUpdateDeferral.isDeferred(error) {
            sideDeferred += 1
        } else {
            failed += 1
        }
    }
}

 
 
 
 
enum BackgroundRefresh {
    static let identifier = ClashAppIdentifiers.backgroundRefreshTask

    static func register(handler: @escaping () async -> BackgroundRefreshOutcome) {
#if os(macOS)
         
         
        _ = handler
#else
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let work = Task {
                 
                 
                 
                let deadline = Date().addingTimeInterval(await refreshTaskBudget())
                let outcome = await DirectFetchFallback.$deadline.withValue(deadline) { await handler() }
                schedule(earliest: outcome.nextEligibleAt ?? nextEligibility())
                task.setTaskCompleted(success: outcome.isSuccessful)
            }
            task.expirationHandler = { work.cancel() }
        }
#endif
    }

     
     
     
    static let appRefreshBudget: TimeInterval = 30

#if canImport(UIKit)
    @MainActor
    private static func refreshTaskBudget() -> TimeInterval {
         
         
        let remaining = UIApplication.shared.backgroundTimeRemaining
        return remaining < appRefreshBudget ? max(0, remaining) : appRefreshBudget
    }
#endif

    static func schedule(afterHours: Int) {
        schedule(earliest: BackgroundRefreshPolicy.earliestEligibility(
            afterHours: afterHours
        ))
    }

    static func schedule(earliest date: Date) {
#if os(macOS)
        _ = date
#else
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
#endif
    }

     
     
     
     
    static func nextEligibility(
        now: Date = Date(),
        containerURL: URL? = nil
    ) -> Date {
        var fallback = BackgroundRefreshPolicy.earliestEligibility(
            afterHours: 4,
            from: now
        )
        let container = containerURL ?? ClashAppIdentifiers.appGroupContainer
        if let container,
           let snapshot = try? ConfigurationLibraryStore(directory: container.appendingPathComponent("working/configuration-library")).snapshot() {
            for source in snapshot.availableSources {
                guard case .subscription = source.origin, let hours = source.updateIntervalHours, hours > 0 else { continue }
                fallback = min(fallback, max(now.addingTimeInterval(60), source.updatedAt.addingTimeInterval(Double(hours) * 3600)))
            }
        }
        return fallback
    }

     
     
     
     
    static let foregroundScanInterval: TimeInterval = 20 * 60

    static let foregroundScanKey = "backgroundRefresh.lastForegroundScan"

     
     
     
    static func shouldScanOnForeground(
        now: Date = Date(),
        lastScan: Date?,
        minimumInterval: TimeInterval = foregroundScanInterval
    ) -> Bool {
        guard let lastScan else { return true }
        let elapsed = now.timeIntervalSince(lastScan)
        return elapsed >= minimumInterval
    }

     
     
     
     
     
     
     
    @discardableResult
     
     
     
     
    static func scanOnForegroundIfDue(
        now: Date = Date(),
        defaults: UserDefaults = GlobalConfig.appGroupDefaults,
        refresh: (Date) async -> BackgroundRefreshOutcome = {
            await refreshDueProfiles(now: $0)
        }
    ) async -> Bool {
        let last = defaults.object(forKey: foregroundScanKey) as? Date
        guard shouldScanOnForeground(now: now, lastScan: last) else {
            return false
        }
        let outcome = await refresh(now)
         
         
         
         
         
        guard outcome.deferredReason == nil else { return false }
        defaults.set(now, forKey: foregroundScanKey)
        return true
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func announceIfRepublished(before: ActiveConfigurationPointer?, after: ActiveConfigurationPointer?,
                                      center: NotificationCenter = .default,
                                      defaults: UserDefaults = GlobalConfig.appGroupDefaults) {
        guard let after, after != before else { return }
        defaults.set([after.profileID, after.revision], forKey: pendingHandoverKey)
        center.post(name: .clashActiveConfigurationRepublished, object: nil,
                    userInfo: ["profileID": after.profileID, "revision": after.revision])
    }

    static let pendingHandoverKey = "backgroundRefresh.republishedForTunnel"

     
     
     
     
    static func revisionToReplace(activeNow: ActiveConfigurationPointer?,
                                  refreshing profileID: String) -> ActiveConfigurationPointer? {
        guard let activeNow, activeNow.profileID == profileID else { return nil }
        return activeNow
    }

    static func republished(from note: Notification) -> ActiveConfigurationPointer? {
        guard let profileID = note.userInfo?["profileID"] as? String,
              let revision = note.userInfo?["revision"] as? String else { return nil }
        return ActiveConfigurationPointer(profileID: profileID, revision: revision)
    }

    static func pendingHandover(in defaults: UserDefaults = GlobalConfig.appGroupDefaults) -> ActiveConfigurationPointer? {
        guard let pair = defaults.stringArray(forKey: pendingHandoverKey), pair.count == 2 else { return nil }
        return ActiveConfigurationPointer(profileID: pair[0], revision: pair[1])
    }

     
    static func clearPendingHandover(_ pointer: ActiveConfigurationPointer,
                                     in defaults: UserDefaults = GlobalConfig.appGroupDefaults) {
        guard pendingHandover(in: defaults) == pointer else { return }
        defaults.removeObject(forKey: pendingHandoverKey)
    }

    static func refreshDueProfiles(
        now: Date = Date(),
        pathSnapshot: NetworkPathSnapshot? = nil,
        pathSettings: NetworkPathPolicySettings = .load()
    ) async -> BackgroundRefreshOutcome {
        var outcome = BackgroundRefreshOutcome()
        guard let container = ClashAppIdentifiers.appGroupContainer,
            let store = try? ConfigResourceStore(containerURL: container)
        else {
            outcome.failed = 1
            return outcome
        }
         
         
         
         
        let activeBefore = try? store.activePointer()
        defer { announceIfRepublished(before: activeBefore, after: try? store.activePointer()) }
        let snapshot: NetworkPathSnapshot
        if let pathSnapshot {
            snapshot = pathSnapshot
        } else {
            snapshot = await NetworkPathProbe.current()
        }
        let pathDecision = NetworkPathPolicy.automaticRefresh(
            snapshot: snapshot,
            settings: pathSettings
        )
        guard pathDecision.action == .allow else {
            outcome.deferredReason = pathDecision.message
            return outcome
        }
        let working = container.appendingPathComponent("working")
         
         
         
         
        do {
            _ = try await Task.detached(priority: .utility) {
                try ConfigurationCenterPublicationBridge.recoverReplacements(
                    library: ConfigurationLibraryStore(directory: working.appendingPathComponent("configuration-library")),
                    workingDir: working)
            }.value
        } catch { outcome.record(error); return outcome }
        let profileStore = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        let credentials = CredentialStore()
        let downloader = ResourceDownloader()
        let active = try? store.activePointer()
        let profiles = profileStore.load()
        let dueProfiles = ProfilesDueForRefresh.select(profiles: profiles, now: now)

         
         
         
         
         
         
         
         
         

         
         
         
        let sourceUpdates = await ConfigurationCenterSourceBridge.refreshDueSources(container: container, now: now)
        outcome.attempted += sourceUpdates.attempted
        outcome.updated += sourceUpdates.updated
        outcome.failed += sourceUpdates.failed
        if sourceUpdates.cancelled { outcome.cancelled = true; return outcome }

        let firstLoad = await ProviderFirstLoadRetry.run(trigger: .scan, container: container, now: now)
        outcome.attempted += firstLoad.attempted
        outcome.updated += firstLoad.updated

         
         
         
         
        if let downloads = GeoResourceSettings.scheduledDownloads(
            following: ConfigurationGeoSettings.active(container: container), now: now) {
            var allGeoSucceeded = true
            for (resource, url) in downloads {
                if Task.isCancelled {
                    outcome.cancelled = true
                    return outcome
                }
                outcome.attempted += 1
                let geoPlan = RemoteResourcePlan(
                    providers: [],
                    geodata: [.init(
                        kind: resource.planKind,
                        url: url
                    )],
                    notices: [],
                    errors: []
                )
                do {
                    try await GeodataManager(downloader: downloader).stage(
                        plan: geoPlan,
                        homeDir: working,
                        maxBytesEach: ProfileActivationCoordinator.maxGeodataBytes
                    )
                    outcome.updated += 1
                } catch is CancellationError {
                    outcome.cancelled = true
                    return outcome
                } catch {
                    allGeoSucceeded = false
                    outcome.failed += 1
                }
            }
            if allGeoSucceeded {
                GeoResourceSettings.recordSync(at: now)
            }
        }

        for listed in dueProfiles {
            if Task.isCancelled {
                outcome.cancelled = true
                return outcome
            }
            outcome.attempted += 1
             
             
             
             
            guard let profile = profileStore.load().first(where: { $0.id == listed.id }),
                  !ProfilesDueForRefresh.select(profiles: [profile], now: now).isEmpty else {
                outcome.unchanged += 1
                continue
            }
             
             
            let decided = ProfileSourceIdentity(profile, workingDirectory: working)
            do {
                if profile.id == active?.profileID {
                    let coordinator = ProfileActivationCoordinator(
                        store: store, profileStore: profileStore, credentials: credentials,
                        downloader: downloader, coreHomeDir: working,
                         
                         
                        compileRuleSets: false,
                        activator: { _ in })
                     
                     
                    func refreshSourceOnly() async throws {
                        let result = try await SubscriptionSourceRefresher.refresh(
                            profile: profile,
                            manager: SubscriptionManager(downloader: downloader, credentials: credentials),
                            profileStore: profileStore,
                            credentials: credentials,
                            workingDirectory: working,
                            now: now,
                            expecting: decided
                        )
                        if result == .unchanged { outcome.unchanged += 1 } else { outcome.updated += 1 }
                    }
                     
                     
                     
                     
                     
                     
                    if let before = revisionToReplace(activeNow: try? store.activePointer(), refreshing: profile.id) {
                        do {
                            let pointer = try await coordinator.activate(profile: profile, sourceYAML: nil,
                                                                         onlyIfActive: before)
                            if before.revision == pointer.revision {
                                outcome.unchanged += 1
                            } else {
                                outcome.updated += 1
                            }
                        } catch where ProfileActivationCoordinator.superseded(error) {
                             
                             
                            outcome.unchanged += 1
                        } catch where ProfileActivationCoordinator.lostToASwitch(error) {
                            try await refreshSourceOnly()
                        }
                    } else {
                        try await refreshSourceOnly()
                    }
                } else {
                    let subscriptions = SubscriptionManager(
                        downloader: downloader,
                        credentials: credentials
                    )
                    let result = try await SubscriptionSourceRefresher.refresh(
                        profile: profile,
                        manager: subscriptions,
                        profileStore: profileStore,
                        credentials: credentials,
                        workingDirectory: working,
                        now: now,
                        expecting: decided
                    )
                    if result == .unchanged {
                        outcome.unchanged += 1
                    } else {
                        outcome.updated += 1
                    }
                }
            } catch is CancellationError {
                outcome.cancelled = true
                return outcome
            } catch {
                 
                 
                 
                 
                outcome.record(error)
            }
        }
         
         
         
         
         
         
         
         
        if Task.isCancelled {
            outcome.cancelled = true
            return outcome
        }
        await refreshAdBlockModules(AdBlockModuleStore.shared(container), container: container,
                                    now: now, outcome: &outcome)
        if Task.isCancelled {
            outcome.cancelled = true
            return outcome
        }
        // Scheduled module scripts run from the app, not the tunnel, because
        // the tunnel is only up while the VPN is. This refresh is the wake-up
        // they ride on; a module that needs them is refreshed above first, so
        // the schedule read here is the current one.
        AdBlockCronRunner.runDue(now: now, locations: AdBlockModuleLocations(container: container))
        if Task.isCancelled {
            outcome.cancelled = true
            return outcome
        }
        outcome.nextEligibleAt = nextEligibility(now: now, containerURL: container)
        return outcome
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func refreshAdBlockModules(
        _ modules: AdBlockModuleStore, container: URL, now: Date,
        outcome: inout BackgroundRefreshOutcome,
        coordinator makeCoordinator: (ConfigResourceStore, ProfileStore, URL, Date) -> ProfileActivationCoordinator
            = BackgroundRefresh.backgroundCoordinator(store:profileStore:working:now:)
    ) async {
        let aModelTakesIt = await MainActor.run { AdBlockModuleChangeTakers.shared.aLiveModelTakesChanges(in: container) }
        let before = await modules.publishedGlobalManifest()
        let results = await modules.refreshDue(announcedAs: aModelTakesIt ? nil : .scheduledRefresh)
        let after = await modules.publishedGlobalManifest()
        guard !aModelTakesIt, results.values.contains(.updated) || after != before else { return }
        await AdBlockModuleStore.$publishing.withValue(.scheduledRefresh) {
            await restageInUseForModules(container: container, now: now, outcome: &outcome, coordinator: makeCoordinator)
        }
    }

     
     
     
     
     
     
    private static func restageInUseForModules(
        container: URL, now: Date, outcome: inout BackgroundRefreshOutcome,
        coordinator makeCoordinator: (ConfigResourceStore, ProfileStore, URL, Date) -> ProfileActivationCoordinator
    ) async {
        let working = container.appendingPathComponent("working")
        guard let store = try? ConfigResourceStore(containerURL: container),
              let active = try? store.activePointer() else { return }
        let profileStore = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        guard let profile = profileStore.load().first(where: { $0.id == active.profileID }),
              let document = try? String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: working,
                  profileID: active.profileID), encoding: .utf8) else { return }
        do {
            let coordinator = makeCoordinator(store, profileStore, working, now)
            let published = try await coordinator.activate(profile: profile, sourceYAML: document, onlyIfActive: active)
             
             
             
            if let reroll = coordinator.portReroll {
                await reroll.value
                _ = try await makeCoordinator(store, profileStore, working, now)
                    .activate(profile: profile, sourceYAML: document, onlyIfActive: published)
            }
        } catch is CancellationError {
            outcome.cancelled = true
        } catch where ProfileActivationCoordinator.lostToASwitch(error)
                        || ProfileActivationCoordinator.superseded(error) {
             
        } catch {
            outcome.record(error)
        }
    }

     
     
     
     
    static func backgroundCoordinator(store: ConfigResourceStore, profileStore: ProfileStore, working: URL,
                                      now: Date) -> ProfileActivationCoordinator {
        ProfileActivationCoordinator(store: store, profileStore: profileStore, credentials: CredentialStore(),
                                     downloader: ResourceDownloader(), coreHomeDir: working,
                                     compileRuleSets: false, activator: { _ in }, now: { now })
    }
}
