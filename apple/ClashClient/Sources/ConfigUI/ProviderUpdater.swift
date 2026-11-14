import ClashClientKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ProviderUpdater {
    enum Outcome: Equatable {
        case updated(countBefore: Int?, countAfter: Int?)
        case unchanged
         
        case failed(AuthoredText)
         
         
        case heldByTunnel(AuthoredText)
         
         
        case awaitingConnection
         
         
        case notConfirmed(AuthoredText)
        case notUpdatable(ProviderUpdateRoute.Reason)
         
        case skipped

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    struct Report: Equatable {
        var outcomes: [String: Outcome] = [:]
         
        var publication: ActiveConfigurationPointer?
         
         
        var errors: [String: PublicationFailure] = [:]
    }

     
    struct Publication: Equatable {
        var outcomes: [String: Outcome] = [:]
        var pointer: ActiveConfigurationPointer?
        var errors: [String: PublicationFailure] = [:]
    }

     
     
     
     
    struct PublicationFailure: Equatable {
        let error: Error
        static func == (lhs: Self, rhs: Self) -> Bool {
            String(describing: lhs.error) == String(describing: rhs.error)
        }
    }

     
     
    struct Environment {
         
         
        var targets: @MainActor ([String]) async -> [String: ProviderUpdateTarget]
        var tunnelRunning: @MainActor () -> Bool
         
         
        var stillInUse: @MainActor () -> Bool
        var tunnel: @MainActor (_ target: ProviderUpdateTarget) async -> ProviderTunnelCheck
         
         
        var publish: @MainActor (_ names: [String], _ compileNow: Bool) async -> Publication
         
        var pendingTaker: @MainActor (_ target: ProviderUpdateTarget, _ reason: String?) -> ProviderRefreshState.PendingTaker
         
        var busyRetryNanoseconds: UInt64 = 2_000_000_000
    }

     
     
     
     
     
     
     
    static func update(_ names: [String], in environment: Environment,
                       progress: (@MainActor (_ name: String, _ outcome: Outcome) -> Void)? = nil) async -> Report {
        var report = Report()
        func settle(_ name: String, _ outcome: Outcome) {
            report.outcomes[name] = outcome
            progress?(name, outcome)
        }
        let targets = await environment.targets(names)
        let tunnelRunning = environment.tunnelRunning()
        var appNames: [String] = []
        var appCompileNow = false
        var switched = false
        for name in names {
            guard !switched, !Task.isCancelled else { settle(name, .skipped); continue }
            guard let target = targets[name] else {
                settle(name, .notUpdatable(.local))
                continue
            }
            switch ProviderUpdateRoute.decide(target, tunnelRunning: tunnelRunning) {
            case .notUpdatable(let reason):
                settle(name, .notUpdatable(reason))
            case .awaitingConnection:
                settle(name, .awaitingConnection)
            case .appSeed:
                appNames.append(name)
            case .tunnel:
                guard environment.stillInUse() else {
                    switched = true
                    settle(name, .skipped)
                    continue
                }
                var check = await environment.tunnel(target)
                if check == .busy {
                     
                    try? await Task.sleep(nanoseconds: environment.busyRetryNanoseconds)
                    check = Task.isCancelled ? .cancelled : await environment.tunnel(target)
                }
                 
                 
                 
                 
                if !environment.stillInUse() { check = .switched }
                switch tunnelOutcome(check, target: target, environment: environment) {
                case .outcome(let outcome): settle(name, outcome)
                case .app(let compileNow):
                    appNames.append(name)
                    appCompileNow = appCompileNow || compileNow
                case .switched:
                    switched = true
                    settle(name, .skipped)
                }
            }
        }
        if !appNames.isEmpty {
            if switched || Task.isCancelled || !environment.stillInUse() {
                for name in appNames { settle(name, .skipped) }
            } else {
                let publication = await environment.publish(appNames, appCompileNow)
                report.publication = publication.pointer
                report.errors.merge(publication.errors) { _, new in new }
                for name in appNames { settle(name, publication.outcomes[name] ?? .skipped) }
            }
        }
        return report
    }

    private enum TunnelStep {
        case outcome(Outcome)
         
         
        case app(compileNow: Bool)
        case switched
    }

    private static func tunnelOutcome(_ check: ProviderTunnelCheck, target: ProviderUpdateTarget,
                                      environment: Environment) -> TunnelStep {
        switch check {
        case .answered(let answer):
            switch answer.result {
            case .updated?: return .outcome(.updated(countBefore: answer.countBefore, countAfter: answer.countAfter))
            case .unchanged?: return .outcome(.unchanged)
            case .failed?:
                return .outcome(.failed(answer.error.map(AuthoredText.verbatim) ?? .app(Self.noReason)))
            case .pendingApp?:
                let taker = environment.pendingTaker(target, answer.pendingReason)
                switch taker {
                 
                case .appWhenOpen, .appWhenAsked: return .app(compileNow: true)
                case .tunnelRetries, .tunnelKeepsOld:
                    return .outcome(.heldByTunnel(.app(ProviderRefreshState.keptLine(
                        taker, countBefore: answer.countBefore))))
                }
            case .scheduled?, nil:
                 
                 
                return .outcome(.notConfirmed(.app("Still updating “%@” — the result will show on its row",
                                                   arguments: [target.name])))
            }
        case .unavailable:
             
             
             
            return target.fetchedByCore ? .outcome(.awaitingConnection) : .app(compileNow: false)
        case .noSession:
            return target.fetchedByCore
                ? .outcome(.failed(.app("Can't update right now — try again in a moment")))
                : .app(compileNow: false)
        case .busy:
            return .outcome(.notConfirmed(.app("Busy — update “%@” again in a moment", arguments: [target.name])))
        case .stillRunning:
            return .outcome(.notConfirmed(.app("Still updating “%@” — the result will show on its row",
                                               arguments: [target.name])))
        case .switched:
            return .switched
        case .cancelled:
            return .outcome(.skipped)
        case .failed(let words):
            return .outcome(.failed(words.isEmpty ? .app(Self.noReason) : .verbatim(words)))
        }
    }

     
    static let noReason = "no reason given"
}

 

 
 
 
@MainActor
enum ProviderTunnelUpdate {
    static var perform: ((_ target: ProviderUpdateTarget, _ stillInUse: @escaping @MainActor () -> Bool) async -> ProviderTunnelCheck)?
}

extension ProviderUpdater.Environment {
     
     
     
     
     
     
    @MainActor
    static func live(profile: Profile, store: ConfigResourceStore, container: URL, vpn: VPNController,
                     scripts: ScriptEngine.Caller,
                     stillInUse: @escaping @MainActor () -> Bool) -> Self {
        let catalog = (try? store.activeProvidersDirectory()).flatMap { ProviderCatalog.load(providersDir: $0) }
        let working = container.appendingPathComponent("working", isDirectory: true)
        return Self(
            targets: { names in
                 
                 
                 
                guard let catalog else { return [:] }
                let coreFetched = await ProviderRefreshService.coreFetchedProviders(
                    in: catalog, profile: profile, store: store, container: container, vpn: vpn)
                return ProviderUpdater.targets(names, in: catalog, coreFetched: coreFetched)
            },
            tunnelRunning: { vpn.status == "connected" || vpn.status == "reasserting" },
            stillInUse: stillInUse,
            tunnel: { target in
                guard let perform = ProviderTunnelUpdate.perform else { return .noSession }
                return await perform(target, stillInUse)
            },
            publish: { names, compileNow in
                await ProviderUpdater.publish(names, compileNow: compileNow, profile: profile, store: store,
                                              container: container, vpn: vpn, scripts: scripts)
            },
            pendingTaker: { target, reason in
                let state = ProviderRefreshState.read(workingDirectory: working)
                return state?.pendingTaker(kind: target.kind, name: target.name, reason: reason,
                                           appCanFetch: !target.fetchedByCore)
                    ?? ProviderRefreshState.pendingTaker(kind: target.kind, reason: reason, variant: nil,
                                                         appCanFetch: !target.fetchedByCore)
            })
    }
}

extension ProviderUpdater {
     
     
     
     
     
     
    static func targets(_ names: [String], in catalog: ProviderCatalog?,
                        coreFetched: Set<String>? = nil) -> [String: ProviderUpdateTarget] {
        guard let catalog else { return [:] }
        let coreFetched = coreFetched ?? catalog.coreFetchedProviders ?? []
        let unusable = catalog.unusableProxyProviders ?? [:]
        var targets: [String: ProviderUpdateTarget] = [:]
        for name in names {
            guard let entry = catalog.entries.first(where: { $0.name == name }) else { continue }
            targets[name] = ProviderUpdateTarget(
                kind: entry.kind, name: entry.name, vehicle: "http", url: entry.url,
                fetchedByCore: coreFetched.contains(entry.name),
                unusableAddress: entry.kind == "proxy" && unusable[entry.name] != nil)
        }
        return targets
    }

     
     
     
    static func publish(_ names: [String], compileNow: Bool, profile: Profile, store: ConfigResourceStore,
                        container: URL, vpn: VPNController, scripts: ScriptEngine.Caller) async -> Publication {
        var publication = Publication()
        let before = store.activeIdentityOrNil()
        let many: ProviderRefreshService.ManyResult
        do {
            let coordinator = try vpn.activationCoordinator(store: store, container: container,
                                                            compileRuleSetsNow: compileNow)
            many = try await ProviderRefreshService.publishMany(
                names: names, profile: profile, store: store, coordinator: coordinator, expectedActive: before,
                scripts: scripts)
        } catch where Task.isCancelled {
            for name in names { publication.outcomes[name] = .skipped }
            return publication
        } catch where ProfileActivationCoordinator.lostToASwitch(error) {
             
             
            for name in names {
                publication.outcomes[name] = .notConfirmed(
                    .app("The configuration changed meanwhile; %@ was not updated.", arguments: [name]))
            }
            return publication
        } catch {
            let text = AuthoredText.of(error)
            for name in names {
                publication.outcomes[name] = .failed(text)
                publication.errors[name] = PublicationFailure(error: error)
            }
            return publication
        }
        for failure in many.failed {
            publication.outcomes[failure.name] = .failed(.of(failure.error))
            publication.errors[failure.name] = PublicationFailure(error: failure.error)
        }
        if many.switched {
            for name in names where publication.outcomes[name] == nil { publication.outcomes[name] = .skipped }
            return publication
        }
        if many.superseded {
            for name in names where publication.outcomes[name] == nil {
                publication.outcomes[name] = .notConfirmed(
                    .app("The configuration changed meanwhile; %@ was not updated.", arguments: [name]))
            }
            return publication
        }
        guard let pointer = many.pointer else { return publication }
        publication.pointer = pointer
         
         
         
         
         
         
         
        let handingOver = Date()
        let wait = await PublishedRuntimeHandover.bounded({
            await PublishedRuntimeHandover.apply(vpn: vpn, profileID: pointer.profileID)
        }, landedLate: PublishedRuntimeHandover.lateLanding(since: handingOver) {
            "provider update step=handover-late took=\($0)s outcome=\($1)"
        })
        for name in many.published {
            let changed = await Task.detached(priority: .userInitiated) {
                ProvidersModel.providerBytesChanged(name, store: store, before: before, after: pointer)
            }.value
            publication.outcomes[name] = publishedOutcome(name, changed: changed, wait: wait)
        }
        return publication
    }

     
     
     
     
    static func publishedOutcome(_ name: String, changed: Bool?, wait: PublishedRuntimeHandover.Wait) -> Outcome {
        switch wait {
        case .answered(let handover):
            return publishedOutcome(name, changed: changed, handover: handover)
        case .timedOut:
            return .notConfirmed(.app("The tunnel did not confirm this update."))
        case .cancelled:
            return .skipped
        }
    }

     
     
    static func publishedOutcome(_ name: String, changed: Bool?, handover: TunnelApplyOutcome?) -> Outcome {
        let fetched: Outcome = changed == false ? .unchanged : .updated(countBefore: nil, countAfter: nil)
        switch handover {
        case nil, .applied?, .restarted?, .savedForNext?:
            return fetched
        case .keptRunning(let words)?, .failed(let words)?:
            return .failed(words.isEmpty ? .app(noReason) : .verbatim(words))
        case .pending?:
             
             
             
            return .notConfirmed(.app("“%@” is downloaded — applies once Clash reconnects", arguments: [name]))
        }
    }
}
