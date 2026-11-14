import Darwin
import Foundation
import Combine
import Clash

enum ProxyShareProtocol: String, CaseIterable, Hashable {
    case http
    case socks5
}

struct ProxyShareStatus: Equatable {
    let enabled: Bool
    let port: Int32
    let protocols: [ProxyShareProtocol]
    let authenticationRequired: Bool

    static let disabled = ProxyShareStatus(
        enabled: false,
        port: 0,
        protocols: [],
        authenticationRequired: false
    )
}

struct ProxyShareConfiguration: Equatable {
    let port: Int32
    let username: String
    let password: String
}

enum ProxyShareError: Error, Equatable {
    case apiUnavailable
    case invalidResponse
    case invalidPort
     
     
    case invalidListenerPort
     
     
     
    case sameListenerPort
    case missingUsername
    case malformedUsername
    case usernameTooLong
    case passwordTooShort
    case passwordTooLong
    case malformedPassword
    case portInUse
    case listenerConflict
    case timedOut
    case coreRejected
    case credentialStore
    case credentialRecovery
    case operationInProgress
}

enum ProxyShareCredentialPolicy {
    static let minimumPasswordBytes = Int(ClashProxyShareMinimumPasswordBytes)

    static var passwordByteRangeDescription: String {
        "\(passwordByteRange) bytes"
    }

     
     
    static var passwordByteRange: String {
        "\(minimumPasswordBytes)–\(ClashProxyShareMaximumCredentialBytes)"
    }

     
     
     
     
     
    static var invalidPasswordDescription: String {
        "That password is too short."
    }
}

extension ProxyShareError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .apiUnavailable:
            return "Connect Clash before sharing the proxy on your local network."
        case .invalidResponse:
            return "Clash returned an invalid LAN proxy status. Sharing remains unavailable."
        case .invalidPort:
            return "Choose a port from 1024 through 65535."
        case .invalidListenerPort:
            return "Choose a port from 0 through 65535; 0 turns it off."
        case .sameListenerPort:
            return "Another port on this page already has that number, and the core opens only one of them. Choose a different port, or leave one empty."
        case .missingUsername:
            return "Enter a username for the shared proxy."
        case .malformedUsername:
            return "A username cannot begin or end with a space, contain a colon, or contain hidden characters."
        case .usernameTooLong:
            return "That username is too long. Choose a shorter one."
        case .passwordTooShort:
            return ProxyShareCredentialPolicy.invalidPasswordDescription
        case .passwordTooLong:
            return "That password is too long. Choose a shorter one."
        case .malformedPassword:
            return "A password cannot contain hidden characters."
        case .portInUse:
            return "That port is already in use. Choose another port and try again."
        case .listenerConflict:
            return "Another local listener conflicts with LAN proxy sharing."
        case .timedOut:
            return "Clash did not confirm the LAN proxy change in time."
        case .coreRejected:
            return "Clash could not apply the LAN proxy setting. Check the port and try again."
        case .credentialStore:
            return "The LAN proxy credentials could not be saved securely on this device."
        case .credentialRecovery:
            return "The previous LAN proxy credentials could not be restored securely. Reset them before trying again."
        case .operationInProgress:
            return "Wait for the current LAN proxy change to finish."
        }
    }
}

enum ProxyShareFailureClassifier {
    static func classify(_ error: Error) -> ProxyShareError {
        if let error = error as? ProxyShareError { return error }
        if error is CancellationError { return .timedOut }
        let description = error.localizedDescription.lowercased()
         
         
         
         
         
         
         
         
         
        if description.contains("address already in use") ||
            description.contains("bind: address in use") ||
            description.contains("proxy-share port") {
            return .portInUse
        }
        if description.contains("conflicts with an existing local listener") {
            return .listenerConflict
        }
        if description.contains("requires a running service") ||
            description.contains("not connected") ||
            description.contains("unavailable") {
            return .apiUnavailable
        }
        return .coreRejected
    }
}

enum ProxyShareStatusParser {
    private static let forbiddenKeys: Set<String> = [
        "auth", "authorization", "credential", "credentials", "password",
        "secret", "token", "username",
    ]

    static func parse(_ json: String) throws -> ProxyShareStatus {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              !object.keys.contains(where: { forbiddenKeys.contains($0.lowercased()) }),
              let enabled = object["enabled"] as? Bool
        else {
            throw ProxyShareError.invalidResponse
        }
        guard enabled else { return .disabled }
        guard let portNumber = object["port"] as? NSNumber,
              CFGetTypeID(portNumber) != CFBooleanGetTypeID(),
              let authenticationRequired = object["authenticationRequired"] as? Bool,
              authenticationRequired,
              let rawProtocols = object["protocols"] as? [String]
        else {
            throw ProxyShareError.invalidResponse
        }
        let port = portNumber.intValue
        guard port >= Int(ClashProxyShareMinimumPort),
              port <= Int(ClashProxyShareMaximumPort),
              rawProtocols.count == ProxyShareProtocol.allCases.count
        else {
            throw ProxyShareError.invalidResponse
        }
        let protocols = rawProtocols.compactMap {
            ProxyShareProtocol(rawValue: $0.lowercased())
        }
        guard Set(protocols) == Set(ProxyShareProtocol.allCases),
              protocols.count == ProxyShareProtocol.allCases.count
        else {
            throw ProxyShareError.invalidResponse
        }
        return ProxyShareStatus(
            enabled: true,
            port: Int32(port),
            protocols: ProxyShareProtocol.allCases,
            authenticationRequired: true
        )
    }
}

enum ProxyShareValidator {
    static func validate(
        portText: String,
        username: String,
        password: String
    ) throws -> ProxyShareConfiguration {
        guard !portText.isEmpty,
              portText.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains),
              let port = Int32(portText),
              port >= ClashProxyShareMinimumPort,
              port <= ClashProxyShareMaximumPort
        else {
            throw ProxyShareError.invalidPort
        }
         
         
         
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty {
            throw ProxyShareError.missingUsername
        }
        if username != trimmedUsername
            || username.contains(":")
            || containsControlCharacter(username) {
            throw ProxyShareError.malformedUsername
        }
        if username.utf8.count > Int(ClashProxyShareMaximumCredentialBytes) {
            throw ProxyShareError.usernameTooLong
        }
        if containsControlCharacter(password) {
            throw ProxyShareError.malformedPassword
        }
        if password.utf8.count < ProxyShareCredentialPolicy.minimumPasswordBytes {
            throw ProxyShareError.passwordTooShort
        }
        if password.utf8.count > Int(ClashProxyShareMaximumCredentialBytes) {
            throw ProxyShareError.passwordTooLong
        }
        return ProxyShareConfiguration(
            port: port,
            username: username,
            password: password
        )
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }
}

enum LANAddressFamily: Int, Equatable {
    case ipv4 = 4
    case ipv6 = 6
}

struct LANInterfaceAddress: Equatable {
    let name: String
    let address: String
    let family: LANAddressFamily
    let isUp: Bool
}

enum LANAddressInventory {
    static func current() -> [String] {
        displayAddresses(from: systemRecords())
    }

    static func currentInterfaces() -> [String: String] {
        interfaceNames(from: systemRecords())
    }

     
     
    static func interfaceNames(from records: [LANInterfaceAddress]) -> [String: String] {
        Dictionary(displayed(from: records).map { ($0.display, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    static func displayAddresses(from records: [LANInterfaceAddress]) -> [String] {
        displayed(from: records).map(\.display)
    }

    private static func displayed(from records: [LANInterfaceAddress]) -> [(display: String, name: String)] {
        let candidates = records.filter {
            $0.isUp && isPhysicalLANInterface($0.name) && isLocal($0)
        }.sorted { lhs, rhs in
            if lhs.family != rhs.family { return lhs.family.rawValue < rhs.family.rawValue }
            let lhsRank = interfaceRank(lhs.name)
            let rhsRank = interfaceRank(rhs.name)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.address < rhs.address
        }

        var seen = Set<String>()
        return candidates.compactMap { record in
            let display: String
            if record.family == .ipv6, isIPv6LinkLocal(record.address) {
                let unscoped = record.address
                    .split(separator: "%", maxSplits: 1)
                    .first
                    .map(String.init) ?? record.address
                display = "\(unscoped)%\(record.name)"
            } else {
                display = record.address
            }
            return seen.insert(display).inserted ? (display, record.name) : nil
        }
    }

    private static func systemRecords() -> [LANInterfaceAddress] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var records: [LANInterfaceAddress] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr else { continue }
            let family: LANAddressFamily
            switch Int32(address.pointee.sa_family) {
            case AF_INET: family = .ipv4
            case AF_INET6: family = .ipv6
            default: continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            records.append(LANInterfaceAddress(
                name: String(cString: interface.ifa_name),
                address: String(cString: host),
                family: family,
                isUp: (Int32(interface.ifa_flags) & IFF_UP) != 0
            ))
        }
        return records
    }

    private static func isPhysicalLANInterface(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("bridge")
    }

    private static func interfaceRank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        return 2
    }

    private static func isLocal(_ record: LANInterfaceAddress) -> Bool {
        switch record.family {
        case .ipv4: return isIPv4PrivateOrLinkLocal(record.address)
        case .ipv6: return isIPv6ULA(record.address) || isIPv6LinkLocal(record.address)
        }
    }

    private static func isIPv4PrivateOrLinkLocal(_ address: String) -> Bool {
        var value = in_addr()
        guard inet_pton(AF_INET, address, &value) == 1 else { return false }
        let host = UInt32(bigEndian: value.s_addr)
        let first = UInt8((host >> 24) & 0xff)
        let second = UInt8((host >> 16) & 0xff)
        return first == 10 ||
            (first == 172 && (16...31).contains(second)) ||
            (first == 192 && second == 168) ||
            (first == 169 && second == 254)
    }

    private static func isIPv6ULA(_ address: String) -> Bool {
        guard let bytes = ipv6Bytes(address) else { return false }
        return bytes[0] & 0xfe == 0xfc
    }

    private static func isIPv6LinkLocal(_ address: String) -> Bool {
        guard let bytes = ipv6Bytes(address) else { return false }
        return bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
    }

    private static func ipv6Bytes(_ address: String) -> [UInt8]? {
        let rawAddress = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        var value = in6_addr()
        guard inet_pton(AF_INET6, rawAddress, &value) == 1 else { return nil }
        return withUnsafeBytes(of: value) { Array($0) }
    }
}

struct ProxyShareCredentials: Equatable {
    let username: String
    let password: String
}

struct ProxyShareCredentialSnapshot {
    fileprivate let username: Data?
    fileprivate let password: Data?
}

final class ProxyShareCredentialVault {
    private static let usernameKey = "runtime.proxy-share.username"
    private static let passwordKey = "runtime.proxy-share.password"
    private let store: CredentialStore

    init(store: CredentialStore = CredentialStore()) {
        self.store = store
    }

    func load() -> ProxyShareCredentials? {
        guard let usernameData = store.get(Self.usernameKey),
              let passwordData = store.get(Self.passwordKey),
              let username = String(data: usernameData, encoding: .utf8),
              let password = String(data: passwordData, encoding: .utf8)
        else { return nil }
        return ProxyShareCredentials(username: username, password: password)
    }

    func snapshot() -> ProxyShareCredentialSnapshot {
        ProxyShareCredentialSnapshot(
            username: store.get(Self.usernameKey),
            password: store.get(Self.passwordKey)
        )
    }

    func replace(username: String, password: String) throws {
        let previous = snapshot()
        do {
            try store.set(Data(username.utf8), for: Self.usernameKey)
            try store.set(Data(password.utf8), for: Self.passwordKey)
        } catch {
            try? restore(previous)
            throw ProxyShareError.credentialStore
        }
    }

    func restore(_ snapshot: ProxyShareCredentialSnapshot) throws {
        do {
            try restore(snapshot.username, key: Self.usernameKey)
            try restore(snapshot.password, key: Self.passwordKey)
        } catch {
            throw ProxyShareError.credentialRecovery
        }
    }

    func remove() throws {
        let previous = snapshot()
        do {
            try store.remove(Self.usernameKey)
            try store.remove(Self.passwordKey)
        } catch {
            try? restore(previous)
            throw ProxyShareError.credentialStore
        }
    }

    private func restore(_ data: Data?, key: String) throws {
        if let data {
            try store.set(data, for: key)
        } else {
            try store.remove(key)
        }
    }
}

struct ProxySharePreferences {
    private static let portKey = "proxyShare.port"
    static let defaultPort: Int32 = 7890
    let defaults: UserDefaults

     
     
     
    init(defaults: UserDefaults = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard) {
        self.defaults = defaults
    }

    func port() -> Int32 {
        let value = defaults.integer(forKey: Self.portKey)
        guard value >= Int(ClashProxyShareMinimumPort),
              value <= Int(ClashProxyShareMaximumPort)
        else { return Self.defaultPort }
        return Int32(value)
    }

    func save(port: Int32) {
        defaults.set(Int(port), forKey: Self.portKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.portKey)
    }
}

@MainActor
protocol ProxyShareCommanding: AnyObject {
     
     
     
    var proxyShareAPIReady: Bool { get }
     
     
     
     
     
     
     
     
    var proxyShareAPIClientReady: Bool { get }
    func fetchProxyShareStatus() async throws -> ProxyShareStatus
    func startProxyShare(_ configuration: ProxyShareConfiguration) async throws -> ProxyShareStatus
    func stopProxyShare() async throws -> ProxyShareStatus
     
     
    var runningListenerPorts: RunningListenerPorts? { get }
     
    var runningListenerPortsChanges: AnyPublisher<RunningListenerPorts?, Never> { get }
     
    func refreshRunningListenerPorts() async
}

extension ProxyShareCommanding {
     
     
    var runningListenerPorts: RunningListenerPorts? { nil }
    var runningListenerPortsChanges: AnyPublisher<RunningListenerPorts?, Never> {
        Empty().eraseToAnyPublisher()
    }
    func refreshRunningListenerPorts() async {}
}

 
enum KernelSharePortStatus: Equatable {
     
    case closed
     
     
     
    case notListening
     
     
     
    case numberTakenByAnother
}

 
 
 
 
 
 
struct RunningListenerPorts: Equatable, Sendable {
    let mixedPort: Int32
    let httpPort: Int32
    let socksPort: Int32
     
     
     
    var allowsLAN: Bool? = nil

     
     
    static func read(configs object: [String: Any]) -> RunningListenerPorts? {
        func port(_ key: String) -> Int32? {
            guard let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int32(exactly: number.doubleValue)
        }
        guard let mixed = port("mixed-port"), let http = port("port"), let socks = port("socks-port") else { return nil }
        let allowsLAN = (object["allow-lan"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }
        return RunningListenerPorts(mixedPort: mixed, httpPort: http, socksPort: socks, allowsLAN: allowsLAN)
    }

    func value(_ port: KernelLANSharePort) -> Int32 {
        switch port {
        case .mixed: mixedPort
        case .http: httpPort
        case .socks: socksPort
        }
    }
}

enum ProxySharePhase: Equatable {
    case unavailable
    case loading
    case disabled
    case starting
    case running
    case stopping
    case failed

    var isBusy: Bool {
        switch self {
        case .loading, .starting, .stopping: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .unavailable: return "VPN Required"
        case .loading: return "Checking"
        case .disabled: return "Off"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .failed: return "Needs Attention"
        }
    }
}

private final class ProxyShareTimeoutGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func installTasks(operation: Task<Void, Never>, timeout: Task<Void, Never>) {
        lock.lock()
        if completed {
            lock.unlock()
            operation.cancel()
            timeout.cancel()
            return
        }
        operationTask = operation
        timeoutTask = timeout
        lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>, fromTimeout: Bool = false) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        let operationTask = self.operationTask
        let timeoutTask = self.timeoutTask
        lock.unlock()
        if fromTimeout {
            operationTask?.cancel()
        } else {
            timeoutTask?.cancel()
        }
        continuation.resume(with: result)
    }
}

 
 
 
 
 
 
 
 
 
struct KernelLANShare: Equatable {
    enum Source: Equatable {
         
        case profile
         
        case override
         
        case none
    }

    let isOn: Bool
    let source: Source
     
    let listener: ProfileListenerPorts?

    static let unbound = KernelLANShare(isOn: false, source: .none, listener: nil)

     
     
    static let defaultPort: Int32 = 7890
}

 
 
 
 
 
 
struct KernelLANShareOverride: Equatable {
    var allowLAN: Bool?
    var mixedPort: Int32?
     
     
     
    var httpPort: Int32? = nil
    var socksPort: Int32? = nil
}

extension KernelLANShareOverride {
    #if os(iOS) || os(macOS)
     
     
    init(patch: OverridePatch) {
        func port(_ key: String) -> Int32? {
            (patch.value(at: [key]) as? NSNumber).flatMap { Int32(exactly: $0.doubleValue) }
        }
        self.init(allowLAN: patch.value(at: ["allow-lan"]) as? Bool,
                  mixedPort: port("mixed-port"), httpPort: port("port"), socksPort: port("socks-port"))
    }
    #endif

    func hasListener(over source: ProfileListenerPorts?) -> Bool {
        [mixedPort ?? source?.mixedPort, httpPort ?? source?.httpPort, socksPort ?? source?.socksPort]
            .compactMap { $0 }.contains { (1...65535).contains($0) }
    }
}

 
 
 
enum KernelLANSharePort: CaseIterable {
    case mixed, http, socks

     
     
    static let range: ClosedRange<Int32> = 0...65535

     
    static func closes(_ text: String) -> Bool {
        Int32(text.trimmingCharacters(in: .whitespaces)) == 0
    }

    func value(in listener: ProfileListenerPorts?) -> Int32? {
        switch self {
        case .mixed: listener?.mixedPort
        case .http: listener?.httpPort
        case .socks: listener?.socksPort
        }
    }

    func value(in override: KernelLANShareOverride) -> Int32? {
        switch self {
        case .mixed: override.mixedPort
        case .http: override.httpPort
        case .socks: override.socksPort
        }
    }

    func set(_ port: Int32?, in override: inout KernelLANShareOverride) {
        switch self {
        case .mixed: override.mixedPort = port
        case .http: override.httpPort = port
        case .socks: override.socksPort = port
        }
    }

     
     
     
     
     
    static func numberTakenTwice(by port: KernelLANSharePort, in override: KernelLANShareOverride,
                                 over listener: ProfileListenerPorts?) -> Bool {
        func running(_ kind: KernelLANSharePort) -> Int32 {
            kind.value(in: override) ?? kind.value(in: listener) ?? 0
        }
        let number = running(port)
        guard number > 0 else { return false }
        return allCases.contains { $0 != port && running($0) == number }
    }
}

 
 
 
 
 
struct KernelLANShareBinding {
    let profileSourceYAML: @MainActor () -> String?
    let override: @MainActor () -> KernelLANShareOverride
     
    let writeOverride: @MainActor (KernelLANShareOverride) throws -> Void
    var profileID: @MainActor () -> String? = { nil }
     
    var applySequence: @MainActor () -> UInt64 = { 0 }
     
     
     
    var restartedSince: @MainActor (UInt64) async -> Bool = { _ in false }
     
     
    var settled: @MainActor () async -> Void = {}
     
     
     
    var modulesListenerKeys: @MainActor () -> KernelLANShareOverride = { KernelLANShareOverride() }
}

 
 
private struct KernelShareAsk {
     
     
    let isShown: (KernelLANShareOverride, ProfileListenerPorts?) -> Bool
     
    let overrideIsSilent: (KernelLANShareOverride) -> Bool
     
    let write: (inout KernelLANShareOverride) -> Void

    static func allowLAN(_ on: Bool) -> KernelShareAsk {
        KernelShareAsk(isShown: { ($0.allowLAN ?? $1?.allowLAN ?? false) == on },
                       overrideIsSilent: { $0.allowLAN == nil },
                       write: { $0.allowLAN = on })
    }

    static func port(_ port: KernelLANSharePort, _ typed: Int32) -> KernelShareAsk {
         
        KernelShareAsk(isShown: { ((port.value(in: $0) ?? port.value(in: $1)) ?? 0) == typed },
                       overrideIsSilent: { port.value(in: $0) == nil },
                       write: { port.set(typed, in: &$0) })
    }
}

 
 
 
 
 
 
enum KernelLANShareSwitch {
     
     
     
     
    static func override(on: Bool, current: KernelLANShareOverride,
                         profile: (listener: ProfileListenerPorts?, allowLAN: Bool),
                         filePortless: Bool? = nil) -> KernelLANShareOverride {
        var override = current
        override.allowLAN = on == profile.allowLAN ? nil : on
        if on, !current.hasListener(over: profile.listener) {
            override.mixedPort = KernelLANShare.defaultPort
        }
        if !on, filePortless ?? (profile.listener == nil), current.mixedPort == KernelLANShare.defaultPort {
            override.mixedPort = nil
        }
        return override
    }

}

@MainActor
final class ProxyShareModel: ObservableObject {
    @Published private(set) var phase: ProxySharePhase = .unavailable
    @Published private(set) var status: ProxyShareStatus = .disabled
    @Published private(set) var errorMessage = ""
     
     
     
    @Published var restartNotice: String?
    @Published private(set) var savedUsername = ""
    @Published private(set) var hasSavedPassword = false
    @Published private(set) var rememberedPort: Int32
    @Published private(set) var localAddresses: [String] = []
    @Published private(set) var localInterfaces: [String: String] = [:]

    private weak var command: ProxyShareCommanding?
    private var runningListenerSubscription: AnyCancellable?
    private var runningPortsAwaited = false
    private var runningPortsGeneration: UInt64 = 0
    private var profileListener: () -> ProfileListenerPorts? = { nil }
    private var profileYAML: (() -> String?)?
     
     
    let terminalListenerDidChange = PassthroughSubject<Void, Never>()
    private let profileListenerParser: @Sendable (String) -> ProfileListenerPorts?
    private lazy var preparedProfileListener = PreparedProfileListener(parse: profileListenerParser) { [weak self] in
        self?.objectWillChange.send()
        self?.terminalListenerDidChange.send()
    }
    private var lanListenerPermitted: () -> Bool = { false }
    private var kernelShareBinding: KernelLANShareBinding?
     
     
     
     
     
     
    @Published private(set) var kernelShareInFlight: Bool?
     
    private var kernelShareInFlightProfile: String?
    private var kernelShareGeneration: UInt64 = 0
    private let vault: ProxyShareCredentialVault
    private let preferences: ProxySharePreferences
    private let addressProvider: () -> [String]
    private let interfaceProvider: () -> [String: String]
    private let timeoutNanoseconds: UInt64
    private var apiReady = false
    private var generation: UInt64 = 0

    init(
        vault: ProxyShareCredentialVault = ProxyShareCredentialVault(),
        preferences: ProxySharePreferences = ProxySharePreferences(),
        addressProvider: @escaping () -> [String] = LANAddressInventory.current,
        interfaceProvider: @escaping () -> [String: String] = LANAddressInventory.currentInterfaces,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        profileListenerParser: @escaping @Sendable (String) -> ProfileListenerPorts? = { ProfileListenerPorts.parse(yaml: $0) }
    ) {
        self.vault = vault
        self.preferences = preferences
        self.addressProvider = addressProvider
        self.interfaceProvider = interfaceProvider
        self.timeoutNanoseconds = timeoutNanoseconds
        self.profileListenerParser = profileListenerParser
        rememberedPort = preferences.port()
        refreshCredentialSummary()
        refreshAddresses()
    }

     
     
     
    func bind(
        profileListener: @escaping () -> ProfileListenerPorts?,
        lanListenerPermitted: @escaping () -> Bool
    ) {
        self.profileListener = profileListener
        self.profileYAML = nil
        self.lanListenerPermitted = lanListenerPermitted
    }

     
     
    func bind(
        profileYAML: @escaping () -> String?,
        lanListenerPermitted: @escaping () -> Bool
    ) {
        self.profileYAML = profileYAML
        self.lanListenerPermitted = lanListenerPermitted
    }

    func bind(kernelShare binding: KernelLANShareBinding) {
        kernelShareGeneration &+= 1
        kernelShareInFlight = nil
        kernelShareBinding = binding
    }

     
     
     
     
    var kernelShare: KernelLANShare {
        let listener = kernelShareListener()
        let override = kernelShareBinding?.override().allowLAN
        let pressed = kernelShareInFlightProfile == kernelShareBinding?.profileID() ? kernelShareInFlight : nil
        let isOn = pressed ?? override ?? (listener?.allowLAN ?? false)
        let source: KernelLANShare.Source
        if override != nil {
            source = .override
        } else {
            source = isOn ? .profile : .none
        }
        return KernelLANShare(isOn: isOn, source: source, listener: listener)
    }

     
     
     
     
     
     
     
    var nativeSharePortSuggestion: Int32? {
        guard let listener = currentProfileListener() else { return nil }
        let taken = Set([listener.mixedPort, listener.httpPort, listener.socksPort].compactMap { $0 })
        guard taken.contains(rememberedPort) else { return nil }
        var candidate = rememberedPort
        repeat {
            candidate = candidate == ClashProxyShareMaximumPort ? ClashProxyShareMinimumPort : candidate + 1
        } while taken.contains(candidate)
        return candidate
    }

     
     
     
     
     
     
     
     
     
     
    func setKernelShare(on: Bool) async {
        await setKernelShare(on: on, begun: beginKernelShareWrite(showing: on))
    }

    private func setKernelShare(on: Bool, begun: KernelShareWrite?) async {
        await writeKernelShare(begun, asking: .allowLAN(on)) { current, profile, filePortless in
            KernelLANShareSwitch.override(on: on, current: current, profile: profile, filePortless: filePortless)
        }
    }

     
     
     
     
     
     
    func pressKernelShare(on: Bool) {
        let begun = beginKernelShareWrite(showing: on)
        Task { await setKernelShare(on: on, begun: begun) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func setKernelSharePort(_ port: KernelLANSharePort = .mixed, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var typed: Int32 = 0
        if !trimmed.isEmpty {
            guard trimmed.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains),
                  let value = Int32(trimmed),
                  KernelLANSharePort.range.contains(value)
            else {
                errorMessage = ProxyShareError.invalidListenerPort.localizedDescription
                objectWillChange.send()
                return
            }
            typed = value
        }
        await writeKernelShare(beginKernelShareWrite(), asking: .port(port, typed), refusing: { override, listener in
            KernelLANSharePort.numberTakenTwice(by: port, in: override, over: listener) ? .sameListenerPort : nil
        }) { current, profile, _ in
            var override = current
            let profiles = port.value(in: profile.listener)
             
             
            port.set(typed == (profiles ?? 0) ? nil : typed, in: &override)
            return override
        }
    }

     
     
     
     
    func kernelSharePortText(_ port: KernelLANSharePort) -> String {
        let shown = kernelShareBinding.flatMap { port.value(in: $0.override()) } ?? port.value(in: kernelShare.listener)
        return shown.flatMap { $0 > 0 ? String($0) : nil } ?? ""
    }

     
    var kernelSharePortText: String { kernelSharePortText(.mixed) }

     
     
     
     
     
     
     
     
    private struct KernelShareWrite {
        let token: UInt64
        let binding: KernelLANShareBinding
    }

    private func beginKernelShareWrite(showing pressed: Bool? = nil) -> KernelShareWrite? {
        guard let binding = kernelShareBinding else { return nil }
        kernelShareGeneration &+= 1
        if let pressed {
            kernelShareInFlight = pressed
            kernelShareInFlightProfile = binding.profileID()
        }
        return KernelShareWrite(token: kernelShareGeneration, binding: binding)
    }

    private func writeKernelShare(
        _ begun: KernelShareWrite?,
        asking ask: KernelShareAsk?,
        refusing refusal: ((KernelLANShareOverride, ProfileListenerPorts?) -> ProxyShareError?)? = nil,
        _ decide: (KernelLANShareOverride, (listener: ProfileListenerPorts?, allowLAN: Bool), _ filePortless: Bool)
            -> KernelLANShareOverride
    ) async {
        guard let begun else { return }
        let token = begun.token, binding = begun.binding
        defer {
            if token == kernelShareGeneration { kernelShareInFlight = nil }
        }
        let profileID = binding.profileID()
        let source = binding.profileSourceYAML()
        let current = binding.override()
        let parser = profileListenerParser
        var profile = await Task.detached(priority: .userInitiated) {
            (listener: source.flatMap(parser),
             allowLAN: source.map { ProfileListenerPorts.configuredAllowLAN(yaml: $0) } ?? false)
        }.value
         
         
         
        let filePortless = profile.listener == nil
        let modules = binding.modulesListenerKeys()
        if let allowLAN = modules.allowLAN { profile.allowLAN = allowLAN }
        if modules.mixedPort != nil || modules.httpPort != nil || modules.socksPort != nil {
            let file = profile.listener
            profile.listener = ProfileListenerPorts(
                mixedPort: modules.mixedPort ?? file?.mixedPort, httpPort: modules.httpPort ?? file?.httpPort,
                socksPort: modules.socksPort ?? file?.socksPort, allowLAN: profile.allowLAN,
                credentials: file?.credentials)
        }
        guard token == kernelShareGeneration,
              !Task.isCancelled,
              binding.profileID() == profileID,
              binding.profileSourceYAML() == source,
              binding.override() == current else { return }
        var override = decide(current, profile, filePortless)
         
         
         
         
         
         
         
        if let ask, override == current, ask.overrideIsSilent(current),
           case .settled(let listener?) = readKernelShareListener(), !ask.isShown(current, listener) {
            ask.write(&override)
        }
         
         
         
        if override != current, let refused = refusal?(override, profile.listener) {
            errorMessage = refused.localizedDescription
            objectWillChange.send()
            terminalListenerDidChange.send()
            return
        }
        do {
            if override != current {
                try write(override, binding: binding)
                awaitRunningPorts(after: binding)
            }
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
            objectWillChange.send()
            terminalListenerDidChange.send()
            return
        }
        objectWillChange.send()
        terminalListenerDidChange.send()
         
         
        if override != current, let ask {
            await holdUntilTheDocumentAgrees(ask, token: token, profileID: profileID, binding: binding)
        }
    }

     
     
    private func write(_ override: KernelLANShareOverride, binding: KernelLANShareBinding) throws {
        let appliesBefore = binding.applySequence()
        try binding.writeOverride(override)
        Task { [weak self] in
            guard await binding.restartedSince(appliesBefore) else { return }
            self?.restartNotice = "Applied. The tunnel reconnected to apply it."
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func holdUntilTheDocumentAgrees(_ ask: KernelShareAsk, token: UInt64, profileID: String?,
                                            binding: KernelLANShareBinding) async {
        func stillThisPress() -> Bool {
            token == kernelShareGeneration && !Task.isCancelled && binding.profileID() == profileID
        }
        await binding.settled()
        var document: ProfileListenerPorts?
        for _ in 0..<40 {
            guard stillThisPress() else { return }
            switch readKernelShareListener() {
            case .settled(let listener):
                if ask.isShown(binding.override(), listener) { return }
                document = listener
            case .settling:
                document = nil
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard stillThisPress(), ask.overrideIsSilent(binding.override()), document != nil else { return }
        var override = binding.override()
        ask.write(&override)
        do {
            try write(override, binding: binding)
        } catch {
            errorMessage = error.localizedDescription
        }
        objectWillChange.send()
        terminalListenerDidChange.send()
    }

    private enum KernelShareListenerRead {
        case settling
        case settled(ProfileListenerPorts?)
    }

     
     
     
     
     
    private var settledKernelListener: (profileID: String, listener: ProfileListenerPorts?)?

    private func kernelShareListener() -> ProfileListenerPorts? {
        let profileID = kernelShareBinding?.profileID()
        if case .settled(let listener) = readKernelShareListener() { return listener }
        guard let profileID, let last = settledKernelListener, last.profileID == profileID else { return nil }
        return last.listener
    }

    private func readKernelShareListener() -> KernelShareListenerRead {
        let profileID = kernelShareBinding?.profileID()
        let read: KernelShareListenerRead
        if let profileYAML {
             
             
             
            guard let yaml = profileYAML() else {
                return profileID == nil ? .settled(nil) : .settling
            }
            switch preparedProfileListener.read(yaml: yaml) {
            case .preparing: read = .settling
            case .ready(let listener): read = .settled(listener)
            }
        } else {
            read = .settled(profileListener())
        }
        if case .settled(let listener) = read, let profileID {
            settledKernelListener = (profileID, listener)
        }
        return read
    }

     
     
    private func currentProfileListener() -> ProfileListenerPorts? {
        if let profileYAML {
            switch preparedProfileListener.read(yaml: profileYAML()) {
            case .preparing: return nil
            case .ready(let prepared): return prepared
            }
        }
        return profileListener()
    }

     
     
     
     
     
     
    var terminalListener: ProxyTerminalListener? {
        if let profileYAML,
           case .preparing = preparedProfileListener.read(yaml: profileYAML()) {
            return nil
        }
        let profile = currentProfileListener()
        if let profile {
            let http = profile.mixedPort ?? profile.httpPort
            let socks = profile.mixedPort ?? profile.socksPort
            if http != nil || socks != nil {
                return ProxyTerminalListener(
                    source: .profile, httpPort: http, socksPort: socks,
                    username: profile.credentials?.username ?? "",
                    password: profile.credentials?.password ?? "",
                    lanReachable: profile.allowLAN && lanListenerPermitted()
                )
            }
        }
        guard status.enabled else { return nil }
        return ProxyTerminalListener(
            source: .share, httpPort: status.port, socksPort: status.port,
            username: savedUsername, password: "", lanReachable: true
        )
    }

     
     
     
     
     
     
     
     
     
    var displayedTerminalListener: ProxyTerminalListener? {
        let listener = terminalListener
        let profileID = kernelShareBinding?.profileID()
        if terminalListenerIsSettling {
            guard let profileID, let last = settledTerminalListener, last.profileID == profileID else { return nil }
            return last.listener
        }
        if let profileID { settledTerminalListener = (profileID, listener) }
        return listener
    }

    private var settledTerminalListener: (profileID: String, listener: ProxyTerminalListener?)?

     
     
    private var terminalListenerIsSettling: Bool {
        guard let profileYAML else { return false }
        guard let yaml = profileYAML() else { return kernelShareBinding?.profileID() != nil }
        if case .preparing = preparedProfileListener.read(yaml: yaml) { return true }
        return false
    }

     
     
    func terminalPassword(for listener: ProxyTerminalListener) -> String {
        listener.source == .share ? (savedPassword() ?? "") : listener.password
    }

    func bind(command: ProxyShareCommanding) {
        self.command = command
        updateAPIAvailability(command.proxyShareAPIReady)
         
         
        runningListenerSubscription = command.runningListenerPortsChanges
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

     
     
     
     
     
     
     
     
     
    func kernelSharePortStatus(_ port: KernelLANSharePort, typed: String, running isRunning: Bool = true) -> KernelSharePortStatus? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        if KernelLANSharePort.closes(text) { return .closed }
        guard isRunning, !runningPortsAwaited, command?.proxyShareAPIReady == true, let running = command?.runningListenerPorts,
              let asked = Int32(text), asked > 0, text == kernelSharePortText(port),
              running.value(port) != asked else { return nil }
        return KernelLANSharePort.allCases.contains { $0 != port && running.value($0) == asked }
            ? .numberTakenByAnother : .notListening
    }

     
     
     
     
     
     
    func kernelShareReach(running isRunning: Bool) -> (allowsLAN: Bool, ports: [Int32]) {
        let ports: [Int32?]
        var allowsLAN = kernelShare.isOn
        if isRunning, !runningPortsAwaited, command?.proxyShareAPIReady == true, let running = command?.runningListenerPorts {
            ports = KernelLANSharePort.allCases.map { running.value($0) }
            allowsLAN = running.allowsLAN ?? allowsLAN
        } else {
            ports = KernelLANSharePort.allCases.map { Int32(kernelSharePortText($0)) }
        }
        var seen = Set<Int32>()
        return (allowsLAN, ports.compactMap { $0 }.filter { $0 > 0 && seen.insert($0).inserted })
    }

     
    func refreshRunningListenerPorts() {
        Task { [weak self] in await self?.command?.refreshRunningListenerPorts() }
    }

     
     
     
    private func awaitRunningPorts(after binding: KernelLANShareBinding) {
        runningPortsGeneration &+= 1
        let mine = runningPortsGeneration
        runningPortsAwaited = true
        Task { [weak self] in
            await binding.settled()
            await self?.command?.refreshRunningListenerPorts()
            guard let self, self.runningPortsGeneration == mine else { return }
            self.runningPortsAwaited = false
            self.objectWillChange.send()
        }
    }

    func updateAPIAvailability(_ ready: Bool) {
         
         
         
         
         
        let effectiveReady = ready && command?.proxyShareAPIClientReady == true
        guard effectiveReady != apiReady else { return }
        apiReady = effectiveReady
        generation &+= 1
        refreshAddresses()
        if effectiveReady {
            phase = .disabled
            errorMessage = ""
        } else {
            phase = .unavailable
            status = .disabled
            errorMessage = ""
        }
    }

    func refreshAddresses() {
         
         
        let addresses = addressProvider()
        if addresses != localAddresses { localAddresses = addresses }
        let interfaces = interfaceProvider()
        if interfaces != localInterfaces { localInterfaces = interfaces }
    }

    func refresh() async {
        refreshAddresses()
        refreshCredentialSummary()
        guard apiReady, let command, command.proxyShareAPIReady else {
            phase = .unavailable
            status = .disabled
            return
        }
        guard !phase.isBusy else { return }
        generation &+= 1
        let token = generation
        phase = .loading
        errorMessage = ""
        do {
            let fetched = try await performWithTimeout {
                try await command.fetchProxyShareStatus()
            }
            guard token == generation, apiReady else { return }
            apply(status: fetched)
        } catch {
            guard token == generation, apiReady else { return }
            publish(error: error)
        }
    }

    @discardableResult
    func start(portText: String, username: String, password: String) async -> Bool {
        guard apiReady, let command, command.proxyShareAPIReady else {
            errorMessage = ProxyShareError.apiUnavailable.localizedDescription
            phase = .unavailable
            return false
        }
        guard !phase.isBusy else {
            errorMessage = ProxyShareError.operationInProgress.localizedDescription
            return false
        }
         
         
         
         
         
         
         
         
        let configuration: ProxyShareConfiguration
        do {
            configuration = try ProxyShareValidator.validate(
                portText: portText,
                username: username,
                password: password
            )
        } catch {
            publish(error: error)
            return false
        }

        let previousCredentials = vault.snapshot()
        do {
            try vault.replace(
                username: configuration.username,
                password: configuration.password
            )
        } catch {
            publish(error: error)
            return false
        }

        generation &+= 1
        let token = generation
        phase = .starting
        errorMessage = ""
        do {
            let started = try await performWithTimeout {
                try await command.startProxyShare(configuration)
            }
            guard started.enabled,
                  started.port == configuration.port,
                  started.authenticationRequired,
                  Set(started.protocols) == Set(ProxyShareProtocol.allCases)
            else { throw ProxyShareError.invalidResponse }
            guard token == generation, apiReady else { return false }
            preferences.save(port: configuration.port)
            refreshCredentialSummary()
            apply(status: started)
            return true
        } catch {
            let boundedError = ProxyShareFailureClassifier.classify(error)
            if boundedError == .timedOut {
                _ = try? await performWithTimeout {
                    try await command.stopProxyShare()
                }
            }
            do {
                try vault.restore(previousCredentials)
            } catch {
                guard token == generation, apiReady else { return false }
                publish(error: ProxyShareError.credentialRecovery)
                return false
            }
            refreshCredentialSummary()
            guard token == generation, apiReady else { return false }
            publish(error: boundedError)
            return false
        }
    }

    @discardableResult
    func stop() async -> Bool {
        guard apiReady, let command, command.proxyShareAPIReady else {
            errorMessage = ProxyShareError.apiUnavailable.localizedDescription
            phase = .unavailable
            status = .disabled
            return false
        }
        guard !phase.isBusy else {
            errorMessage = ProxyShareError.operationInProgress.localizedDescription
            return false
        }
        generation &+= 1
        let token = generation
        phase = .stopping
        errorMessage = ""
        do {
            let stopped = try await performWithTimeout {
                try await command.stopProxyShare()
            }
            guard !stopped.enabled else { throw ProxyShareError.invalidResponse }
            guard token == generation, apiReady else { return false }
            apply(status: .disabled)
            return true
        } catch {
            guard token == generation, apiReady else { return false }
            publish(error: error)
            return false
        }
    }

    @discardableResult
    func reset() async -> Bool {
        if status.enabled, apiReady, !(await stop()) { return false }
        do {
            try vault.remove()
            preferences.reset()
            rememberedPort = ProxySharePreferences.defaultPort
            refreshCredentialSummary()
            errorMessage = ""
            phase = apiReady ? .disabled : .unavailable
            status = .disabled
            return true
        } catch {
            publish(error: error)
            return false
        }
    }

    private func apply(status: ProxyShareStatus) {
        self.status = status
        if status.enabled {
            rememberedPort = status.port
            preferences.save(port: status.port)
        }
        phase = status.enabled ? .running : .disabled
        errorMessage = ""
    }

    private func refreshCredentialSummary() {
        let credentials = vault.load()
        savedUsername = credentials?.username ?? ""
        hasSavedPassword = credentials != nil
    }

     
     
     
    func savedPassword() -> String? {
        vault.load()?.password
    }

     
     
     
     
     
    var reachableAddresses: [String] {
#if os(macOS)
        Self.dialable(localAddresses, keepingSelfAssignedWhenAlone: true)
#else
        Self.dialable(localAddresses, keepingSelfAssignedWhenAlone: false)
#endif
    }

     
     
     
     
     
     
     
     
     
    static func dialable(_ addresses: [String], keepingSelfAssignedWhenAlone: Bool) -> [String] {
        let dialable = addresses.filter { address in
            let value = address.lowercased()
            return !value.hasPrefix("169.254.")
                && !value.hasPrefix("fe80:")
                && !value.contains("%")
        }
        guard dialable.isEmpty, keepingSelfAssignedWhenAlone else { return dialable }
        return addresses.filter { $0.hasPrefix("169.254.") }
    }

    private func publish(error: Error) {
        let bounded = ProxyShareFailureClassifier.classify(error)
        errorMessage = bounded.localizedDescription
        phase = .failed
    }

    private func performWithTimeout<Value>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let gate = ProxyShareTimeoutGate<Value>()
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            let operationTask = Task { @MainActor in
                do {
                    gate.resolve(.success(try await operation()))
                } catch {
                    gate.resolve(.failure(error))
                }
            }
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    gate.resolve(.failure(ProxyShareError.timedOut), fromTimeout: true)
                } catch {
                     
                }
            }
            gate.installTasks(operation: operationTask, timeout: timeoutTask)
        }
    }
}


