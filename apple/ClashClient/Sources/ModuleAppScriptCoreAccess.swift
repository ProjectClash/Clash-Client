#if os(iOS) || os(macOS)
import Clash
import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
enum ModuleAppScriptCoreAccess {
     
    static func socketPath() -> String? {
        ClashAppIdentifiers.appGroupContainer?.appendingPathComponent("clash.sock").path
    }

     
    static let callSeconds: Double = 5

    static func config(socketPath: @escaping () -> String? = socketPath) -> ModuleScriptConfigAccess {
        ModuleScriptConfigAccess(
            isAvailable: { socketPath().map { FileManager.default.fileExists(atPath: $0) } ?? false },
            mode: { text(socketPath) { $0.getConfigs($1) }.flatMap(ModuleScriptCoreReading.mode(configs:)) },
            setMode: { mode in call(socketPath) { try $0.setMode(mode) } != nil },
            groups: { text(socketPath) { $0.getProxiesSummary($1) }.map(ModuleScriptCoreReading.groups(summary:)) ?? [] },
            members: { group, limit in
                text(socketPath) { $0.getGroupMembers(group, offset: 0, limit: Int32(clamping: limit), error: $1) }
                    .flatMap(ModuleScriptCoreReading.members(page:))
            },
            selected: { group in
                text(socketPath) { $0.getProxiesSummary($1) }.flatMap { ModuleScriptCoreReading.selected(summary: $0, group: group) }
            },
            final: {
                text(socketPath) { $0.getRulesPage(0, limit: 1, typesJSON: #"["MATCH"]"#, error: $1) }
                    .flatMap(ModuleScriptCoreReading.final(rulesPage:))
            },
            builtins: { ModuleScriptCoreReading.builtins },
            groupTypes: { text(socketPath) { $0.getProxiesSummary($1) }.map(ModuleScriptCoreReading.groupTypes(summary:)) ?? [:] },
            globalRefusal: {
                 
                 
                ClashTunnelOutboundMode.refusalKey(onto: ClashTunnelOutboundMode.readGlobalExit(
                    summary: { text(socketPath) { $0.getProxiesSummary($1) } },
                    members: { group in
                        text(socketPath) { $0.getGroupMembers(group, offset: 0, limit: Int32(ClashTunnelOutboundMode.membersRead), error: $1) }
                    }))
            })
    }

     
     
     
     
     
     
     
     
    static func dns(socketPath: @escaping () -> String? = socketPath) -> ModuleScriptDNSAccess {
        ModuleScriptDNSAccess { query, completion in
            dnsQueue.addOperation {
                guard let path = socketPath(), FileManager.default.fileExists(atPath: path) else {
                    return completion(.failure(ModuleScriptDNSFailure(code: "TUNNEL_UNAVAILABLE", message: #"Clash is not connected"#)))
                }
                func failed(_ error: NSError?, _ otherwise: String) {
                    completion(.failure(ModuleScriptDNSFailure(code: "QUERY_FAILED", message: error?.localizedDescription ?? otherwise)))
                }
                var error: NSError?
                guard let client = ClashNewAPIClientWithOptions(path, Handler(), ClashAPIClientOptions(), &error) else {
                    return failed(error, #"no client for Clash's controller"#)
                }
                defer { client.close() }
                let reply = client.scriptDNSQuery(ModuleScriptCoreReading.scriptDNSRequest(query), error: &error)
                if let error { return failed(error, "") }
                completion(ModuleScriptCoreReading.scriptDNSResult(reply))
            }
        }
    }

    private static let dnsQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "modules.app-scripts.dns"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 8
        return queue
    }()

     
    static func selectPolicy(socketPath: @escaping () -> String? = socketPath) -> (String, String) -> Bool {
        { group, policy in call(socketPath) { try $0.selectProxy(group, name: policy) } != nil }
    }

    private static let queue = DispatchQueue(label: "modules.app-scripts.core", qos: .utility, attributes: .concurrent)

     
     
    private static func call<T>(_ socketPath: () -> String?, _ body: @escaping (ClashAPIClient) throws -> T) -> T? {
        guard let path = socketPath(), FileManager.default.fileExists(atPath: path) else { return nil }
        let box = CallBox<T>()
        let done = DispatchSemaphore(value: 0)
        queue.async {
            defer { done.signal() }
            var error: NSError?
            guard let client = ClashNewAPIClientWithOptions(path, Handler(), ClashAPIClientOptions(), &error) else { return }
            defer { client.close() }
            box.value = try? body(client)
        }
        guard done.wait(timeout: .now() + callSeconds) == .success else { return nil }
        return box.value
    }

    private final class CallBox<T>: @unchecked Sendable { var value: T? }

     
    private static func text(_ socketPath: () -> String?, _ body: @escaping (ClashAPIClient, NSErrorPointer) -> String) -> String? {
        call(socketPath) { client in
            var error: NSError?
            let answer = body(client, &error)
            if let error { throw error }
            return answer
        }
    }

     
    private final class Handler: NSObject, ClashAPIClientHandlerProtocol {
        func connected() {}
        func disconnected(_ message: String?) {}
        func writeConnections(_ message: String?) {}
        func writeLogs(_ message: String?) {}
        func writeMemory(_ message: String?) {}
        func writeMode(_ message: String?) {}
        func writeTraffic(_ message: String?) {}
    }
}
#endif
