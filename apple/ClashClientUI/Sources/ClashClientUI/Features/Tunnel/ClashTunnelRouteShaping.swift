import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashTunnelRouteShaping {
    public static let hideVPNIconKey = "vpn.tunnel.hideVPNIcon"
    public static let homeKitCompatibilityKey = "vpn.tunnel.homeKitCompatibility"
     
     
     
     
     
     
    public static let excludeAPNsRouteKey = "vpn.tunnel.excludeAPNsRoute"
     
     
     
     
    public static let moduleDeviceSettingsPath = "modules/device-settings.json"

    public struct Switches: Equatable, Sendable {
        public var hideVPNIcon: Bool
        public var homeKitCompatibility: Bool
        public var excludeAPNsRoute: Bool

        public init(hideVPNIcon: Bool = false, homeKitCompatibility: Bool = false, excludeAPNsRoute: Bool = false) {
            self.hideVPNIcon = hideVPNIcon
            self.homeKitCompatibility = homeKitCompatibility
            self.excludeAPNsRoute = excludeAPNsRoute
        }

         
        public static func read(from defaults: UserDefaults?) -> Switches {
            Switches(
                hideVPNIcon: defaults?.bool(forKey: hideVPNIconKey) ?? false,
                homeKitCompatibility: defaults?.bool(forKey: homeKitCompatibilityKey) ?? false,
                excludeAPNsRoute: defaults?.bool(forKey: excludeAPNsRouteKey) ?? false
            )
        }

         
         
         
         
         
        public static func read(from defaults: UserDefaults?, moduleOverlay: URL?) -> Switches {
            var switches = read(from: defaults)
            guard let moduleOverlay, let data = try? Data(contentsOf: moduleOverlay),
                  let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return switches }
            func flag(_ name: String) -> Bool? {
                switch values[name]?.lowercased() {
                case "true"?: return true
                case "false"?: return false
                default: return nil
                }
            }
            if let on = flag("hideVPNIcon") { switches.hideVPNIcon = on }
            if let on = flag("homeKitCompatibility") { switches.homeKitCompatibility = on }
            return switches
        }
    }

    public struct V4: Equatable, Sendable {
        public let address: String
        public let mask: String
        public init(address: String, mask: String) {
            self.address = address
            self.mask = mask
        }
    }

    public struct V6: Equatable, Sendable {
        public let address: String
        public let prefix: Int
        public init(address: String, prefix: Int) {
            self.address = address
            self.prefix = prefix
        }
    }

     
    public static let v4SplitTable: [V4] = [
        V4(address: "1.0.0.0", mask: "255.0.0.0"),
        V4(address: "2.0.0.0", mask: "254.0.0.0"),
        V4(address: "4.0.0.0", mask: "252.0.0.0"),
        V4(address: "8.0.0.0", mask: "248.0.0.0"),
        V4(address: "16.0.0.0", mask: "240.0.0.0"),
        V4(address: "32.0.0.0", mask: "224.0.0.0"),
        V4(address: "64.0.0.0", mask: "192.0.0.0"),
        V4(address: "128.0.0.0", mask: "128.0.0.0"),
    ]

     
     
     
     
    public static let v6SplitTable: [V6] = [
        V6(address: "100::", prefix: 8),
        V6(address: "200::", prefix: 7),
        V6(address: "400::", prefix: 6),
        V6(address: "800::", prefix: 5),
        V6(address: "1000::", prefix: 4),
        V6(address: "2000::", prefix: 3),
        V6(address: "4000::", prefix: 2),
        V6(address: "8000::", prefix: 1),
    ]

     
    public static let v4IconHole = V4(address: "0.0.0.0", mask: "255.255.255.254")
    public static let v6IconHole = V6(address: "::", prefix: 127)

     
     
     
    public static let v4APNsRange = V4(address: "17.0.0.0", mask: "255.0.0.0")

     
     
     
     
     
     
    public static let apnsFakeIPFilterEntry = "+.push.apple.com"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func usesSplitTable(strictRoute: Bool, enforceRoutes: Bool, loopbackConfigured: Bool, switches: Switches) -> Bool {
        switches.homeKitCompatibility || (strictRoute && (enforceRoutes || (!switches.hideVPNIcon && !loopbackConfigured)))
    }

     
     
    public static func v4Default(splitTable: Bool) -> [V4] {
        splitTable ? v4SplitTable : [V4(address: "0.0.0.0", mask: "0.0.0.0")]
    }

    public static func v6Default(splitTable: Bool) -> [V6] {
        splitTable ? v6SplitTable : [V6(address: "::", prefix: 0)]
    }

     
     
     
     
     
     
    public static func takesWholeAsDefault(splitTable: Bool, hideVPNIcon: Bool) -> Bool {
        hideVPNIcon && !splitTable
    }

     
     
     
     
     
     
    public static let v4HostMask = "255.255.255.255"

     
     
     
     
     
     
     
    public static func v4DeclaresHostAddress(leftOut: [V4]?, excluded: [V4], dnsServer: String) -> Bool {
        guard leftOut != nil, let server = bytes(dnsServer, AF_INET) else { return false }
        return !v4Prefixes(excluded).contains { samePrefix($0.bytes, server, $0.length) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func v4LeftOutBesideLoopback(_ effective: [V4], keeping: [V4] = []) -> [V4]? {
        let prefixes = v4Prefixes(effective)
        guard prefixes.contains(where: { holdsTheZeroAddress($0) }) else { return nil }
        return uncovered(prefixes + v4Prefixes(keeping), bits: 32).map { block in
            let mask = block.length == 0 ? UInt32(0) : ~UInt32(0) << (32 - block.length)
            return V4(address: block.bytes.map(String.init).joined(separator: "."),
                      mask: [24, 16, 8, 0].map { String((mask >> $0) & 0xff) }.joined(separator: "."))
        }
    }

     
     
     
    public static func v4Excluded(_ configured: [V4], includedIsEmpty: Bool, switches: Switches) -> [V4] {
        guard !includedIsEmpty else { return configured }
        var excluded = configured
        if switches.hideVPNIcon, !excluded.contains(v4IconHole) {
            excluded.append(v4IconHole)
        }
        if switches.excludeAPNsRoute, !excluded.contains(v4APNsRange) {
            excluded.append(v4APNsRange)
        }
        return excluded
    }

    public static func v6Excluded(_ configured: [V6], includedIsEmpty: Bool, switches: Switches) -> [V6] {
        guard switches.hideVPNIcon, !includedIsEmpty, !configured.contains(v6IconHole) else { return configured }
        return configured + [v6IconHole]
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func v4Included(_ effective: [V4], loopback: [V4], wholeAsDefault: Bool = false, besideLoopback: Bool = false) -> [V4] {
        let prefixes = v4Prefixes(effective)
        if (besideLoopback && prefixes.contains(where: { holdsTheZeroAddress($0) }))
            || (wholeAsDefault && takesEveryAddress(prefixes, bits: 32)) {
            let whole = V4(address: "0.0.0.0", mask: "0.0.0.0")
            return [whole] + loopback.filter { $0 != whole }
        }
        let routes = unique(effective.flatMap { route -> [V4] in
            guard let length = v4Length(route.mask), length > 0, startsAtZero(route.address, length, AF_INET) else { return [route] }
            return v4SplitTable.filter { (v4Length($0.mask) ?? 0) > length }
        })
        return routes + loopback.filter { !routes.contains($0) }
    }

     
     
    public static func v6Included(_ effective: [V6], loopback: [V6], wholeAsDefault: Bool = false) -> [V6] {
        if wholeAsDefault, takesEveryAddress(effective.compactMap { route in
            bytes(route.address, AF_INET6).map { ($0, route.prefix) }
        }, bits: 128) {
            let whole = V6(address: "::", prefix: 0)
            return [whole] + loopback.filter { $0 != whole }
        }
        let routes = unique(effective.flatMap { route -> [V6] in
            guard route.prefix > 0, startsAtZero(route.address, route.prefix, AF_INET6) else { return [route] }
            return v6SplitTable.filter { $0.prefix > route.prefix }
        })
        return routes + loopback.filter { !routes.contains($0) }
    }

    private static func unique<Route: Equatable>(_ routes: [Route]) -> [Route] {
        routes.reduce(into: []) { kept, route in if !kept.contains(route) { kept.append(route) } }
    }

    private static func v4Prefixes(_ routes: [V4]) -> [(bytes: [UInt8], length: Int)] {
        routes.compactMap { route in v4Length(route.mask).flatMap { length in bytes(route.address, AF_INET).map { ($0, length) } } }
    }

     
    private static func samePrefix(_ a: [UInt8], _ b: [UInt8], _ length: Int) -> Bool {
        a.count == b.count && (0..<min(length, a.count * 8)).allSatisfy { (a[$0 / 8] ^ b[$0 / 8]) & UInt8(0x80 >> ($0 % 8)) == 0 }
    }

     
    private static func holdsTheZeroAddress(_ prefix: (bytes: [UInt8], length: Int)) -> Bool {
        (0..<min(prefix.length, prefix.bytes.count * 8)).allSatisfy { prefix.bytes[$0 / 8] & UInt8(0x80 >> ($0 % 8)) == 0 }
    }

    private static func v4Length(_ mask: String) -> Int? {
        var s = in_addr()
        guard inet_pton(AF_INET, mask, &s) == 1 else { return nil }
        return (~UInt32(bigEndian: s.s_addr)).leadingZeroBitCount
    }

    private static func bytes(_ address: String, _ family: Int32) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: family == AF_INET ? 4 : 16)
        return inet_pton(family, address, &bytes) == 1 ? bytes : nil
    }

     
     
    private static func takesEveryAddress(_ prefixes: [(bytes: [UInt8], length: Int)], bits: Int) -> Bool {
        uncovered(prefixes, bits: bits).isEmpty
    }

     
     
     
     
     
     
    private static func uncovered(_ prefixes: [(bytes: [UInt8], length: Int)], bits: Int) -> [(bytes: [UInt8], length: Int)] {
        func left(_ block: [UInt8], _ length: Int, _ reaching: [(bytes: [UInt8], length: Int)]) -> [(bytes: [UInt8], length: Int)] {
            if reaching.contains(where: { $0.length <= length }) { return [] }
            guard length < bits, !reaching.isEmpty else { return [(block, length)] }
            let bit = UInt8(0x80 >> (length % 8))
            var upper = block
            upper[length / 8] |= bit
            let (low, high) = reaching.reduce(into: ([(bytes: [UInt8], length: Int)](), [(bytes: [UInt8], length: Int)]())) { split, prefix in
                if prefix.bytes[length / 8] & bit == 0 { split.0.append(prefix) } else { split.1.append(prefix) }
            }
            return left(block, length + 1, low) + left(upper, length + 1, high)
        }
        return left([UInt8](repeating: 0, count: bits / 8), 0,
                    prefixes.filter { (0...bits).contains($0.length) && $0.bytes.count == bits / 8 })
    }

     
    private static func startsAtZero(_ address: String, _ length: Int, _ family: Int32) -> Bool {
        bytes(address, family).map { holdsTheZeroAddress(($0, length)) } ?? false
    }
}

extension ClashTunnelRouteShaping {
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func declaresIPv6(
        coreOffersIPv6: Bool,
        physicalPathSupportsIPv6: Bool
    ) -> Bool {
        coreOffersIPv6 && physicalPathSupportsIPv6
    }
}


 

#if os(macOS)
extension ClashTunnelRouteShaping {
     
     
    public struct OtherInterfaceRoute: Equatable, Sendable {
        public let address: String
        public let prefix: Int
        public let interface: String
         
        public let scoped: Bool
        public init(address: String, prefix: Int, interface: String, scoped: Bool = false) {
            self.address = address; self.prefix = prefix; self.interface = interface; self.scoped = scoped
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func macDeclaredExclusions(_ excluded: [V4], included: [V4], otherRoutes: [OtherInterfaceRoute],
                                             recentlyLeft: Set<String> = [],
                                             scopedStays: Set<String> = []) -> ExclusionSplit<V4> {
        split(excluded, prefix: RoutePrefix.init, key: exclusionKey, included: included.compactMap(RoutePrefix.init),
              covers: otherRoutes.compactMap { r in RoutePrefix.v4(r.address, r.prefix).map { ($0, r.scoped) } },
              recentlyLeft: recentlyLeft, scopedStays: scopedStays)
    }

    public static func macDeclaredExclusions(_ excluded: [V6], included: [V6], otherRoutes: [OtherInterfaceRoute],
                                             recentlyLeft: Set<String> = [],
                                             scopedStays: Set<String> = []) -> ExclusionSplit<V6> {
        split(excluded, prefix: RoutePrefix.init, key: exclusionKey, included: included.compactMap(RoutePrefix.init),
              covers: otherRoutes.compactMap { r in RoutePrefix.v6(r.address, r.prefix).map { ($0, r.scoped) } },
              recentlyLeft: recentlyLeft, scopedStays: scopedStays)
    }

    public static func exclusionKey(_ route: V4) -> String { "\(route.address)/\(route.mask)" }
    public static func exclusionKey(_ route: V6) -> String { "\(route.address)/\(route.prefix)" }

    public struct ExclusionSplit<Route: Equatable>: Equatable {
         
        public var declared: [Route] = []
         
        public var leftToOthers: [Route] = []
         
         
        public var held: [Route] = []
         
        public var leftOnScoped: [Route] = []
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static func split<Route>(_ excluded: [Route], prefix: (Route) -> RoutePrefix?, key: (Route) -> String,
                                     included: [RoutePrefix], covers: [(RoutePrefix, Bool)],
                                     recentlyLeft: Set<String>, scopedStays: Set<String>) -> ExclusionSplit<Route> {
        var out = ExclusionSplit<Route>()
        for route in excluded {
            guard let p = prefix(route) else { out.declared.append(route); continue }
            let claims = covers.filter { cover, scoped in
                cover.length > 0 && cover.contains(p)
                    && (!scoped || (cover.length == p.length && !scopedStays.contains(key(route))))
            }
            let best = claims.map(\.0.length).max()
            if let best {
                 
                 
                guard !included.contains(where: { $0.length > best && ($0.contains(p) || p.contains($0)) }) else {
                    out.declared.append(route); continue
                }
                out.leftToOthers.append(route)
                if claims.allSatisfy(\.1) { out.leftOnScoped.append(route) }
            } else if recentlyLeft.contains(key(route)) {
                out.held.append(route)
            } else {
                out.declared.append(route)
            }
        }
        return out
    }

     
    public static func interfaces(carrying addresses: Set<String>) -> Set<String> {
        guard !addresses.isEmpty else { return [] }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var names: Set<String> = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = entry.pointee.ifa_addr else { continue }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            switch Int32(sa.pointee.sa_family) {
            case AF_INET:
                var a = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                inet_ntop(AF_INET, &a, &text, socklen_t(text.count))
            case AF_INET6:
                var a = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                inet_ntop(AF_INET6, &a, &text, socklen_t(text.count))
            default: continue
            }
             
            let family = Int32(sa.pointee.sa_family)
            let found = RoutePrefix.bytes(String(cString: text), family)
            if addresses.contains(where: { RoutePrefix.bytes($0, family) == found && found != nil }) {
                names.insert(String(cString: entry.pointee.ifa_name))
            }
        }
        return names
    }

     
     
     
    public static func isPhysicalOrLocal(_ interface: String) -> Bool {
        ["en", "pdp_ip", "bridge", "lo", "awdl", "llw", "anpi", "ap", "gif", "stf", "XHC", "vmenet"].contains { interface.hasPrefix($0) }
    }

     
     
    public static func otherInterfaceRoutes(inDump dump: [UInt8], ownInterfaces: Set<String>,
                                            interfaceName: (Int) -> String?) -> [OtherInterfaceRoute] {
        var out: [OtherInterfaceRoute] = []
        var offset = 0
        while offset + 16 <= dump.count {
            let length = Int(UInt16(dump[offset]) | UInt16(dump[offset + 1]) << 8)
            guard length >= 16, offset + length <= dump.count else { break }
            defer { offset += length }
            let index = Int(UInt16(dump[offset + 4]) | UInt16(dump[offset + 5]) << 8)
            let flags = Int32(bitPattern: UInt32(dump[offset + 8]) | UInt32(dump[offset + 9]) << 8 | UInt32(dump[offset + 10]) << 16 | UInt32(dump[offset + 11]) << 24)
            let addrs = Int32(bitPattern: UInt32(dump[offset + 12]) | UInt32(dump[offset + 13]) << 8 | UInt32(dump[offset + 14]) << 16 | UInt32(dump[offset + 15]) << 24)
             
             
             
            guard flags & RTF_UP != 0, let name = interfaceName(index), !isPhysicalOrLocal(name),
                  !ownInterfaces.contains(name) else { continue }
             
            var cursor = offset + MemoryLayout<rt_msghdr>.size
            var destination: [UInt8]?, mask: [UInt8]?, family = 0
            for bit in 0..<8 where addrs & (1 << bit) != 0 {
                guard cursor < offset + length else { break }
                let saLen = Int(dump[cursor])
                let saFamily = Int(dump[cursor + 1])
                let end = min(cursor + max(saLen, 1), offset + length)
                let bytes = Array(dump[cursor..<end])
                if bit == 0 { destination = bytes; family = saFamily }
                if bit == 2 { mask = bytes }
                cursor += saLen == 0 ? 4 : (saLen + 3) & ~3
            }
            guard let destination else { continue }
            if family == AF_INET, destination.count >= 8 {
                let address = destination[4..<8].map(String.init).joined(separator: ".")
                let prefix = flags & RTF_HOST != 0 ? 32 : Self.maskLength(mask, at: 4, width: 4)
                out.append(.init(address: address, prefix: prefix, interface: name, scoped: flags & RTF_IFSCOPE != 0))
            } else if family == AF_INET6, destination.count >= 24 {
                var storage = in6_addr()
                withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: destination[8..<24]) }
                 
                if storage.__u6_addr.__u6_addr8.0 == 0xfe, storage.__u6_addr.__u6_addr8.1 & 0xc0 == 0x80 { continue }
                var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &storage, &text, socklen_t(text.count)) != nil else { continue }
                let prefix = flags & RTF_HOST != 0 ? 128 : Self.maskLength(mask, at: 8, width: 16)
                out.append(.init(address: String(cString: text), prefix: prefix, interface: name,
                                 scoped: flags & RTF_IFSCOPE != 0))
            }
        }
        return out
    }

     
     
    static func maskLength(_ mask: [UInt8]?, at start: Int, width: Int) -> Int {
        guard let mask, mask.count > start else { return 0 }
        var length = 0
        for index in 0..<width {
            let byte = start + index < mask.count ? mask[start + index] : 0
            if byte == 0xFF { length += 8; continue }
            length += (~byte).leadingZeroBitCount
            break
        }
        return length
    }

     
     
     
     
     
     
     
     
    public static func currentOtherInterfaceRoutes(ownInterfaces: Set<String>) -> [OtherInterfaceRoute] {
        [AF_INET, AF_INET6].flatMap { family -> [OtherInterfaceRoute] in
            var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, family, NET_RT_DUMP, 0]
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
            var buffer = [UInt8](repeating: 0, count: size + 4096)
            size = buffer.count
            guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return [] }
            return otherInterfaceRoutes(inDump: Array(buffer[0..<size]), ownInterfaces: ownInterfaces) { index in
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                return if_indextoname(UInt32(index), &name) != nil ? String(cString: name) : nil
            }
        }
    }

     
    struct RoutePrefix: Equatable {
        let bytes: [UInt8]
        let length: Int

        init?(bytes: [UInt8]?, length: Int) {
            guard let bytes, (0...bytes.count * 8).contains(length) else { return nil }
            self.bytes = bytes; self.length = length
        }
        init?(_ route: V4) {
            guard let mask = Self.bytes(route.mask, AF_INET) else { return nil }
            self.init(bytes: Self.bytes(route.address, AF_INET), length: mask.reduce(0) { $0 + $1.nonzeroBitCount })
        }
        init?(_ route: V6) { self.init(bytes: Self.bytes(route.address, AF_INET6), length: route.prefix) }
        static func v4(_ address: String, _ length: Int) -> RoutePrefix? { RoutePrefix(bytes: bytes(address, AF_INET), length: length) }
        static func v6(_ address: String, _ length: Int) -> RoutePrefix? { RoutePrefix(bytes: bytes(address, AF_INET6), length: length) }

        func contains(_ other: RoutePrefix) -> Bool {
            guard other.bytes.count == bytes.count, other.length >= length else { return false }
            for bit in 0..<length where bytes[bit / 8] & UInt8(0x80 >> (bit % 8)) != other.bytes[bit / 8] & UInt8(0x80 >> (bit % 8)) {
                return false
            }
            return true
        }

        static func bytes(_ text: String, _ family: Int32) -> [UInt8]? {
            if family == AF_INET {
                var s = in_addr(); guard inet_pton(AF_INET, text, &s) == 1 else { return nil }
                return withUnsafeBytes(of: &s) { Array($0) }
            }
            var s = in6_addr(); guard inet_pton(AF_INET6, text, &s) == 1 else { return nil }
            return withUnsafeBytes(of: &s) { Array($0) }
        }
    }
}
#endif
