#if os(iOS) || os(macOS)
@preconcurrency import Clash
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleScriptHostWiring {
     
    static func makeHost(
        container: URL? = ClashAppIdentifiers.appGroupContainer,
        network: any ModuleScriptNetworking = ModuleScriptNoNetwork(),
        routing: ModuleScriptRouting = .none,
        configuration: ModuleScriptHost.Configuration = .platformDefault,
        onStop: @escaping (ModuleScriptStopReason) -> Void = { _ in }
    ) -> ModuleScriptHost? {
        guard let container else { return nil }
        let log: @Sendable (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) }
         
         
         
#if os(macOS)
        let postsItself = false
#else
        let postsItself = true
#endif
        let notifier = ModuleScriptTunnelNotifier(mailbox: ModuleScriptNotificationMailbox(container: container),
                                                  postsItself: postsItself, log: log)
        var services = ModuleScriptServices(
            log: log,
            notify: { request in
                notifier.post(ModuleScriptNotificationRecord(
                    scriptName: request.scriptName, title: request.title, subtitle: request.subtitle,
                    body: request.body, openURL: request.openURL, clipboardText: request.clipboardText,
                    sound: request.sound, mediaURL: request.mediaURL, delaySeconds: request.delaySeconds))
            },
            geoip: { ClashGeoIPCountryForIP($0)?.value },
            selectPolicy: { group, policy in
                 
                var error: NSError?
                let selected = ClashSelectProxy(group, policy, &error)
                return selected && error == nil
            },
            environment: ModuleScriptEnvironment.current(),
            network: network)
        services.config = configAccess(routing)
        services.dns = dnsAccess()
        let store = ModuleScriptStore(
            directory: container.appendingPathComponent(ModuleScriptStore.directoryName, isDirectory: true),
            log: log)
         
         
        let quarantine = ModuleScriptQuarantine(file: container.appendingPathComponent(ModuleScriptQuarantine.fileName))
        return ModuleScriptHost(configuration: configuration, services: services, store: store,
                                quarantine: quarantine, onStop: onStop)
    }

     
     
     
     
    static func makeRunner(container: URL? = ClashAppIdentifiers.appGroupContainer,
                           routing: ModuleScriptRouting = .none) -> ModuleScriptRunning {
        let log: (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) }
        let network = ModuleScriptNetwork(log: log)
        guard let host = makeHost(container: container, network: network, routing: routing) else {
            log(#"[script] no App Group container: scripts are not run in this tunnel"#)
            return ModuleNoScripts()
        }
        return ModuleScriptRunner(host: host, log: log, network: network)
    }

     
     
     
     
     
    static func configAccess(_ routing: ModuleScriptRouting) -> ModuleScriptConfigAccess {
        ModuleScriptConfigAccess(
            isAvailable: { true },
            mode: routing.mode,
            setMode: routing.setMode,
            groups: { ModuleScriptCoreReading.groups(summary: ClashProxiesSummaryJSON()) },
            members: { group, limit in ModuleScriptCoreReading.members(page: ClashGroupMembersJSON(group, 0, Int32(clamping: limit))) },
            selected: { group in ModuleScriptCoreReading.selected(widget: ClashWidgetGroupJSON(group, 1)) },
            final: { ModuleScriptCoreReading.final(rulesPage: ClashRulesPageJSON(0, 1, #"["MATCH"]"#)) },
            builtins: { ModuleScriptCoreReading.builtins },
            groupTypes: { ModuleScriptCoreReading.groupTypes(summary: ClashProxiesSummaryJSON()) },
            globalRefusal: {
                ClashTunnelOutboundMode.refusalKey(onto: TunnelGlobalReading.exit())
            })
    }

     
     
     
     
     
     
    static func dnsAccess() -> ModuleScriptDNSAccess {
        ModuleScriptDNSAccess { query, completion in
            dnsQueue.addOperation {
                completion(ModuleScriptCoreReading.scriptDNSResult(ClashScriptDNSQueryJSON(ModuleScriptCoreReading.scriptDNSRequest(query))))
            }
        }
    }

    private static let dnsQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "modules.scripts.dns"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 8
        return queue
    }()
}

 
 
 
struct ModuleScriptRouting {
    var mode: () -> String?
    var setMode: (String) -> Bool

    static let none = ModuleScriptRouting(mode: { nil }, setMode: { _ in false })
}
#endif
