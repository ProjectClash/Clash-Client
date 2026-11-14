import Foundation
import Clash

 
 
 
 
enum AppCoreSetup {
     
     
    private static let containerLock = NSLock()
    private static var containerStorage: URL?
    private static var containerForApplication: URL? {
        get { containerLock.lock(); defer { containerLock.unlock() }; return containerStorage }
        set { containerLock.lock(); containerStorage = newValue; containerLock.unlock() }
    }

     
    nonisolated(unsafe) private(set) static var setupCount = 0

     
     
    private struct SetupIdentity: Equatable {
        let container: String
        let timeZone: String
    }
     
    private struct Policy: Equatable {
        let queryMode: String
        let tunIPv6Mode: String
        let resolvers: String
    }
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var setUpStorage: SetupIdentity?
    nonisolated(unsafe) private static var policyStorage: Policy?
    private static var setUp: SetupIdentity? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return setUpStorage }
        set { stateLock.lock(); setUpStorage = newValue; stateLock.unlock() }
    }
    private static var appliedPolicy: Policy? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return policyStorage }
        set { stateLock.lock(); policyStorage = newValue; stateLock.unlock() }
    }

    static func serialized<T>(_ operation: () throws -> T) rethrows -> T {
        try AppCore.exclusiveWaiting(operation)
    }

    static var applicationContainer: URL? {
        containerForApplication ?? ClashAppIdentifiers.appGroupContainer
    }

    static func currentSettings() throws -> IPStackSettings {
#if os(tvOS)
        try IPStackSettings.load(from: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard)
#else
         
         
         
         
         
        IPStackSettings()
#endif
    }

     
     
     
     
    static var runtimeProfileName: String? {
#if os(macOS)
        "macosPacketTunnel"
#elseif os(tvOS)
        "tvosPacketTunnel"
#else
        nil
#endif
    }

    static func withConfiguration<T>(
        container: URL,
        settings: IPStackSettings? = nil,
        _ operation: () throws -> T
    ) throws -> T {
         
         
        let frozen = try settings ?? currentSettings()
        return try serialized {
            let identity = SetupIdentity(container: container.path, timeZone: TimeZone.current.identifier)
            let policy = Policy(queryMode: frozen.queryMode.rawValue, tunIPv6Mode: frozen.tunIPv6Mode.rawValue,
                                resolvers: ClashSystemResolverLines())
            var error: NSError?
            if setUp != identity {
                let options = ClashSetupOptions()
                options.basePath = container.path
                options.workingPath = container.appendingPathComponent("working").path
                options.tempPath = container.appendingPathComponent("temp").path
                options.timeZone = identity.timeZone
                options.logMaxLines = 100
                 
                 
                options.disablePersistentCache = true
                 
                if let profile = runtimeProfileName { options.runtimeProfile = profile }
                options.ipQueryMode = frozen.queryMode.rawValue
                options.tunIPv6Mode = frozen.tunIPv6Mode.rawValue
                options.systemDNSServerLines = ClashSystemResolverLines()
                AppCore.setup(options, &error)
                setupCount += 1
                if let error { throw error }
                setUp = identity
                appliedPolicy = policy
            } else {
                 
                 
                let options = ClashAppPolicyOptions()
                options.ipQueryMode = policy.queryMode
                options.tunIPv6Mode = policy.tunIPv6Mode
                options.systemDNSServerLines = policy.resolvers
                AppCore.updateAppPolicy(options, &error)
                if let error { throw error }
                appliedPolicy = policy
            }
            return try operation()
        }
    }

     
     
     
     
    static func ensureForReaders() -> Bool {
        if containerForApplication != nil { return true }
        guard let container = ClashAppIdentifiers.appGroupContainer else { return false }
        return (try? ensure(container: container)) != nil
    }

     
     
    static func ensure(container: URL, settings: IPStackSettings? = nil) throws {
         
         
         
        let frozen = try settings ?? currentSettings()
        let identity = SetupIdentity(container: container.path, timeZone: TimeZone.current.identifier)
        let policy = Policy(queryMode: frozen.queryMode.rawValue, tunIPv6Mode: frozen.tunIPv6Mode.rawValue,
                            resolvers: ClashSystemResolverLines())
        if setUp == identity, appliedPolicy == policy {
            containerForApplication = container
            return
        }
        try withConfiguration(container: container, settings: frozen) {
            containerForApplication = container
        }
    }
}
