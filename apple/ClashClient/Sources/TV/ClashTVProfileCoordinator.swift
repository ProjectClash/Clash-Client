import Foundation
import NetworkExtension

 
 
 
 
 
@MainActor
final class ClashTVProfileCoordinator {
    typealias Loader = @MainActor () async throws -> [any ClashTVSystemProfile]
    typealias Maker = @MainActor () -> any ClashTVSystemProfile

    enum StartError: Error { case permissionNotGranted }

    enum SaveOutcome {
        case saved
        case refused(Error)
        case indeterminate(Error)
         
        case loadFailed(Error)
         
         
        case noProfile
         
         
        case superseded
    }

    private var profile: (any ClashTVSystemProfile)?
     
     
     
    private var intent: Bool
    private var intentSeq = 0
     
     
     
    private(set) var commandSeq = 0
     
     
     
    private(set) var disarmUnconfirmed = false
     
     
     
    private(set) var armedWanted = false
    private var profileStamp = 0
    private var queue: Task<Void, Never>?
    private var systemSaveTail: Task<Void, Error>?
     
     
     
    private var armedSaveRevision: UInt64 = 0

    private let load: Loader
    private let make: Maker
    private let timeout: TimeInterval
    private let ownedBy: @MainActor (any ClashTVSystemProfile) -> Bool
     
     
     
    private let persistIntent: @MainActor (Bool) -> Void
     
     
     
     
     
     
    private var storedIntent: Bool

    init(
        intent: Bool,
        persistIntent: @escaping @MainActor (Bool) -> Void,
        load: @escaping Loader,
        make: @escaping Maker,
        timeout: TimeInterval,
        ownedBy: @escaping @MainActor (any ClashTVSystemProfile) -> Bool
    ) {
        self.intent = intent
        self.storedIntent = intent
        self.persistIntent = persistIntent
        self.load = load
        self.make = make
        self.timeout = timeout
        self.ownedBy = ownedBy
    }

     
     
    var current: (any ClashTVSystemProfile)? { profile }

     

    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let task = enqueue(work)
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let prior = queue
        let task = Task { @MainActor in
            await prior?.value
            await work()
        }
        queue = task
        return task
    }

    private func install(_ profile: any ClashTVSystemProfile) {
        self.profile = profile
        profileStamp += 1
    }

    private func arm(_ profile: any ClashTVSystemProfile, wanted: Bool) {
        profile.onDemandRules = wanted ? [NEOnDemandRuleConnect()] : nil
        profile.isOnDemandEnabled = wanted
        armedWanted = wanted
    }

     
     
     
    private func enqueueSave(_ profile: any ClashTVSystemProfile) -> Task<Void, Error> {
        let prior = systemSaveTail
        let proto = profile.protocolConfiguration?.copy() as? NEVPNProtocol
        let rules = profile.onDemandRules?.map { $0.copy() as! NEOnDemandRule }
        let enabled = profile.isEnabled
        let onDemand = profile.isOnDemandEnabled
        let title = profile.localizedDescription
        let task = Task { @MainActor in
            _ = try? await prior?.value
            profile.protocolConfiguration = proto
            profile.onDemandRules = rules
            profile.isEnabled = enabled
            profile.isOnDemandEnabled = onDemand
            profile.localizedDescription = title
            try await profile.saveToPreferences()
            if onDemand { self.armedSaveRevision &+= 1 }
        }
        systemSaveTail = task
        return task
    }

    private func save(_ profile: any ClashTVSystemProfile) async throws {
        let operation = enqueueSave(profile)
        try await ClashTVTunnelController.bounded(timeout) { try await operation.value }
    }

    private func isIndeterminate(_ error: Error) -> Bool {
        if case ClashTVTunnelController.ControllerError.systemTimedOut = error { return true }
        return false
    }

     
     
     
    private func loadInstalled() async throws -> (any ClashTVSystemProfile)? {
        let stamp = profileStamp
        let installed = try await ClashTVTunnelController.bounded(timeout) { try await self.load() }
        guard let found = installed.first(where: ownedBy) else { return nil }
        if profileStamp == stamp, profile == nil { install(found) }
        return profile ?? found
    }

     

     
     
     
    func find() async throws {
        guard profile == nil else { return }
        _ = try await loadInstalled()
    }

     
     
     
     
    func setWanted(_ wanted: Bool, apply: @escaping @MainActor (SaveOutcome, Bool) -> Void) async {
        commandSeq += 1
        intentSeq += 1
        let seq = intentSeq
        intent = wanted
        await serialized { [weak self] in
            guard let self else { return }
            guard seq == self.intentSeq else { return apply(.superseded, wanted) }
            let outcome = await self.applyWanted(wanted)
            switch outcome {
            case .refused, .loadFailed:
                 
                 
                 
                self.intent = self.storedIntent
            case .saved, .indeterminate, .noProfile, .superseded:
                break
            }
            apply(outcome, wanted)
        }
    }

    private func store(_ wanted: Bool) {
        storedIntent = wanted
        persistIntent(wanted)
    }

    private func applyWanted(_ wanted: Bool) async -> SaveOutcome {
        if profile == nil {
            do { _ = try await loadInstalled() }
            catch { return .loadFailed(error) }
        }
        guard let profile else {
             
             
             
            store(wanted)
            return .noProfile
        }
        let previous = armedWanted
        arm(profile, wanted: wanted)
        do {
            try await save(profile)
            store(wanted)
            return .saved
        } catch {
            if isIndeterminate(error) {
                 
                store(wanted)
                return .indeterminate(error)
            }
            arm(profile, wanted: previous)
            return .refused(error)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    func commitStart(
        replacingInstalled: Bool = false,
        configure: @escaping @MainActor (any ClashTVSystemProfile) throws -> Void,
        shouldAbort: @escaping @MainActor () -> Bool,
        onWaiting: @escaping @MainActor () -> Void = {}
    ) async throws {
        commandSeq += 1
        var failure: Error?
        await serialized { [weak self] in
            guard let self else { return }
            if shouldAbort() { failure = CancellationError(); return }
            do {
                if let pending = self.systemSaveTail { _ = try? await pending.value }
                 
                 
                let installed = try await ClashTVTunnelController.bounded(self.timeout) { try await self.load() }
                if shouldAbort() || Task.isCancelled { throw CancellationError() }
                var found = installed.first(where: self.ownedBy)
                if replacingInstalled, let stale = found {
                    try await ClashTVTunnelController.bounded(self.timeout) { try await stale.removeFromPreferences() }
                    if shouldAbort() || Task.isCancelled { throw CancellationError() }
                    found = nil
                }
                let profile = found ?? self.make()
                self.profile = found
                self.profileStamp += 1
                try configure(profile)
                self.arm(profile, wanted: self.intent)
                self.disarmUnconfirmed = false
                try await VPNStartAuthorization.perform(
                    save: {
                        do { try await self.enqueueSave(profile).value }
                        catch {
                            if found == nil, VPNStartAuthorization.isPermissionDenial(error as NSError) {
                                throw StartError.permissionNotGranted
                            }
                            throw error
                        }
                        self.install(profile)
                    },
                    reload: {
                        try await ClashTVTunnelController.bounded(self.timeout) { try await profile.loadFromPreferences() }
                    },
                    start: {},
                    abort: {
                        self.arm(profile, wanted: false)
                        try? await self.enqueueSave(profile).value
                    },
                    isCurrent: { !shouldAbort() },
                    delay: { try await Task.sleep(for: .seconds(self.timeout)) },
                    onWaiting: onWaiting
                )
            } catch { failure = error }
        }
        if let failure { throw failure }
    }

     
     
    func applyIPStack(_ next: IPStackSettings, defaults: UserDefaults) async throws {
        var failure: Error?
        await serialized {
            do {
                if let pending = self.systemSaveTail { _ = try? await pending.value }
                let installed = try await ClashTVTunnelController.bounded(self.timeout) { try await self.load() }
                try Task.checkCancellation()
                let profile = installed.first(where: self.ownedBy)
                self.profile = profile
                self.profileStamp += 1
                let previous = profile?.protocolConfiguration?.copy() as? NEVPNProtocol
                try await IPStackSettingsApplication.apply(next, defaults: defaults,
                    saveProtocol: { settings in
                        guard let profile else { return }
                        guard let proto = profile.protocolConfiguration?.copy() as? NETunnelProviderProtocol else {
                            throw IPStackSettingsError.invalidSnapshot
                        }
                        proto.providerConfiguration = try settings.applying(to: proto.providerConfiguration)
                        profile.protocolConfiguration = proto
                        do { try await self.enqueueSave(profile).value }
                        catch { profile.protocolConfiguration = previous; throw error }
                    },
                    restoreProtocol: {
                        guard let profile else { return }
                        profile.protocolConfiguration = previous
                        try await self.enqueueSave(profile).value
                    },
                    isRunning: { false }, restart: {})
            } catch { failure = error }
        }
        if let failure { throw failure }
    }

     
     
     
     
    func requestStop(performStop: @escaping @MainActor (any ClashTVSystemProfile) -> Void) -> Task<Void, Never> {
        commandSeq += 1
        let stopped = profile
        let stoppedAtArmedRevision = armedSaveRevision
        if let stopped { performStop(stopped) }
        return enqueue { [self] in
             
             
            _ = try? await systemSaveTail?.value
            let needsDisarm = armedWanted || profile?.isOnDemandEnabled == true || disarmUnconfirmed
            armedWanted = false
            guard let profile else { return }
            if needsDisarm {
                arm(profile, wanted: false)
                if (try? await enqueueSave(profile).value) != nil { disarmUnconfirmed = false }
            }
            let armedAfterStop = armedSaveRevision != stoppedAtArmedRevision
            if stopped !== profile || (armedAfterStop &&
                (profile.status == .connecting || profile.status == .connected || profile.status == .reasserting)) {
                performStop(profile)
            }
        }
    }

    func stop(performStop: @escaping @MainActor (any ClashTVSystemProfile) -> Void) async {
        await requestStop(performStop: performStop).value
    }

     
     
    func reloadIfDisarmUnconfirmed() async {
        guard disarmUnconfirmed else { return }
        await serialized { [weak self] in
            guard let self, self.disarmUnconfirmed, let profile = self.profile else { return }
             
            _ = try? await self.systemSaveTail?.value
            guard (try? await ClashTVTunnelController.bounded(self.timeout) { try await profile.loadFromPreferences() }) != nil
            else { return }
            if !profile.isOnDemandEnabled { self.disarmUnconfirmed = false }
            self.armedWanted = profile.isOnDemandEnabled
        }
    }

     
    enum PauseOutcome {
        case saved
         
        case indeterminate
         
         
        case overtaken
        case refused(Error)
         
         
        case skipped
    }

     
     
     
     
     
    func pauseOnDemand(askedAt seq: Int) async -> PauseOutcome {
        var outcome = PauseOutcome.skipped
        await serialized { [weak self] in
            guard let self, seq == self.commandSeq, let profile = self.profile else { return }
             
             
            do {
                try await ClashTVTunnelController.bounded(self.timeout) { try await profile.loadFromPreferences() }
            } catch {
                outcome = .refused(error)
                return
            }
            guard seq == self.commandSeq, profile.isOnDemandEnabled else { return }
            self.arm(profile, wanted: false)
            do {
                try await self.save(profile)
                outcome = seq == self.commandSeq ? .saved : .overtaken
            } catch {
                if self.isIndeterminate(error) {
                    self.disarmUnconfirmed = true
                    outcome = seq == self.commandSeq ? .indeterminate : .overtaken
                    return
                }
                 
                 
                 
                self.arm(profile, wanted: true)
                outcome = .refused(error)
            }
        }
        return outcome
    }
}
