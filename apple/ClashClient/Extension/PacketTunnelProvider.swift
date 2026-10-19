import NetworkExtension
import os.log

 
 
 
class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var provider = ExtensionProvider(tunnelProvider: self)
    private static let launchLog = Logger(
        subsystem: "org.example.clash.demo.extension", category: "launch")
    #if os(iOS) || os(macOS)
     
    private static let adBlockLog = Logger(subsystem: "org.example.clash.demo.extension", category: "adblock")
     
     
     
     
    private lazy var adBlockHost: AdBlockEngineHost? = AdBlockEngineLocations.production.map { locations in
        // Scripts are run in-process, in their own JavaScriptCore context per
        // request. The runner is built here, without a connector: the engine
        // assembly hands it one when a configuration starts, so a script's HTTP
        // follows the same routing as the app's traffic.
        let scripts = AdBlockScriptRunner(queue: DispatchQueue(label: "adblock.scripts", qos: .userInitiated),
                                          log: AdBlockEngineLog { line in
                                              PacketTunnelProvider.adBlockLog.notice("\(line, privacy: .public)")
                                              ClashLogStore.shared.append(line, stream: .app)
                                          },
                                          readChoices: AdBlockScriptSettings.choices)
        return AdBlockEngineHost(locations: locations, log: AdBlockEngineLog { line in
            PacketTunnelProvider.adBlockLog.notice("\(line, privacy: .public)")
            ClashLogStore.shared.append(line, stream: .app)
        }, scripts: scripts, carriesEngineProxy: { revision in
            PacketTunnelProvider.runtimeDocument(in: locations.container, revision)
                .map { AdBlockRuntimeDocumentScan.carriesInjectedEngine(at: $0, known: .read(locations)) } ?? false
        }, configure: { engine, inputs, reporter, scripts in
            AdBlockEngineAssembly.configure(engine, inputs, reporter, locations: locations, scripts: scripts, thresholds: .current)
        })
    }

     
     
    private static func runtimeDocument(in container: URL, _ revision: AdBlockRunningRevision) -> URL? {
        (try? ConfigResourceStore(containerURL: container))?
            .providersDirectory(profileID: revision.profileID, revision: revision.revision)?
            .deletingLastPathComponent().appendingPathComponent("config.resolved.yaml")
    }
    #endif

     
     
     
     
     
     
     
     
     
     
     
     
     
    override init() {
        super.init()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        Self.launchLog.notice("tunnel extension launched  version=\(version, privacy: .public) (\(build, privacy: .public))")
        ClashLogStore.shared.append(
            "tunnel extension launched  version=\(version) (\(build))",
            stream: .app, level: .warning)
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
         
        let userInitiated = (options?[ClashTunnelStart.userInitiatedStartOption] as? NSNumber)?.boolValue ?? false
        #if os(iOS) || os(macOS)
        provider.adBlockHooks = adBlockHost
        #endif
        do {
            try await provider.start(userInitiated: userInitiated)
        } catch {
            #if os(iOS) || os(macOS)
             
             
            adBlockHost?.tunnelStopped()
            #endif
            throw error
        }
        #if os(iOS) || os(macOS)
         
        provider.widgetMailbox.start()
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        #if os(iOS) || os(macOS)
         
         
        provider.widgetMailbox.stop()
        #endif
        await provider.stop(reason: reason)
        #if os(iOS) || os(macOS)
         
        adBlockHost?.tunnelStopped()
        #endif
    }

    override func sleep() async {
        provider.sleep()
    }

    override func wake() {
        provider.wake()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        Task {
            let (reply, afterReply) = await provider.handleMessage(messageData)
            completionHandler?(reply)
            afterReply?()
        }
    }
}
