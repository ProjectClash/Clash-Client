import Foundation

 
 
 
 
 
 
enum GeoResource: String, CaseIterable, Identifiable {
    case geoip
    case geosite
    case mmdb
    case asn

    var id: String { rawValue }

     
    var title: String {
        switch self {
        case .geoip: return "GEOIP"
        case .geosite: return "GEOSITE"
        case .mmdb: return "MMDB"
        case .asn: return "ASN"
        }
    }

     
    var fileName: String {
        switch self {
        case .geoip: return "GeoIP.dat"
        case .geosite: return "GeoSite.dat"
        case .mmdb: return "geoip.metadb"
        case .asn: return "ASN.mmdb"
        }
    }

     
    var planKind: String { rawValue }

    var defaultURL: String {
         
         
         
        let base = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"
        switch self {
        case .geoip: return "\(base)/geoip.dat"
        case .geosite: return "\(base)/geosite.dat"
        case .mmdb: return "\(base)/geoip.metadb"
        case .asn: return "\(base)/GeoLite2-ASN.mmdb"
        }
    }
}

 
 
 
 
 
 
enum GeoResourceSettings {
    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard
    }

    private static let lastSyncKey = "geo.lastSyncAt"

     
     
    static let upstreamAutoUpdate = false
    static let upstreamIntervalHours = 24

    static func isValidURL(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw) else { return false }
         
         
        let scheme = components.scheme?.lowercased()
        return (scheme == "https" || scheme == "http") && !(components.host ?? "").isEmpty
    }

    static func lastSync(from defaults: UserDefaults = appGroupDefaults) -> Date? {
        defaults.object(forKey: lastSyncKey) as? Date
    }

    static func recordSync(at date: Date = Date(),
                           in defaults: UserDefaults = appGroupDefaults) {
        defaults.set(date, forKey: lastSyncKey)
    }

    static func isAutoUpdateDue(enabled: Bool, intervalHours: Int,
                                lastSync: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastSync else { return true }
        return lastSync.addingTimeInterval(TimeInterval(intervalHours) * 3600).timeIntervalSince(now) <= 0
    }
}

 
 
 
 
 
 
struct ConfigurationGeoSettings: Equatable {
    var autoUpdate: Bool?
    var intervalHours: Int?
    var urls: [GeoResource: String] = [:]

    static let silent = ConfigurationGeoSettings()

    init(autoUpdate: Bool? = nil, intervalHours: Int? = nil, urls: [GeoResource: String] = [:]) {
        self.autoUpdate = autoUpdate
        self.intervalHours = intervalHours
        self.urls = urls
    }

     
     
     
    init(document: [String: Any]) {
        autoUpdate = Self.bool(document["geo-auto-update"])
        if let hours = Self.int(document["geo-update-interval"]), hours > 0 { intervalHours = hours }
        if let geox = document["geox-url"] as? [String: Any] {
            for resource in GeoResource.allCases {
                guard let raw = geox[resource.rawValue] as? String else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if GeoResourceSettings.isValidURL(trimmed) { urls[resource] = trimmed }
            }
        }
    }

     
    init(yaml: String) {
        guard let json = try? ConfigTransforms.yamlToJSON(yaml),
              let document = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        else { self = .silent; return }
        self.init(document: document)
    }

     
     
    static func active(container: URL? = ClashAppIdentifiers.appGroupContainer) -> ConfigurationGeoSettings {
        guard let container,
              let store = try? ConfigResourceStore(containerURL: container),
              let yaml = try? String(contentsOf: store.activeConfigURL, encoding: .utf8)
        else { return .silent }
        return ConfigurationGeoSettings(yaml: yaml)
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}

extension GeoResourceSettings {
     
    static func autoUpdateEnabled(following file: ConfigurationGeoSettings) -> Bool {
        file.autoUpdate ?? upstreamAutoUpdate
    }

     
    static func autoUpdateIntervalHours(following file: ConfigurationGeoSettings) -> Int {
        file.intervalHours ?? upstreamIntervalHours
    }

     
    static func url(for resource: GeoResource, following file: ConfigurationGeoSettings) -> String {
        file.urls[resource] ?? resource.defaultURL
    }

     
    static func scheduledDownloads(following file: ConfigurationGeoSettings,
                                   from defaults: UserDefaults = appGroupDefaults,
                                   now: Date) -> [(resource: GeoResource, url: String)]? {
        guard isAutoUpdateDue(
            enabled: autoUpdateEnabled(following: file),
            intervalHours: autoUpdateIntervalHours(following: file),
            lastSync: lastSync(from: defaults), now: now
        ) else { return nil }
        return GeoResource.allCases.map { ($0, url(for: $0, following: file)) }
    }
}

 
enum GeoResourceInventory {
    struct Entry {
        let resource: GeoResource
        let sizeBytes: Int?
        let updatedAt: Date?
    }

    static func scan(homeDir: URL) -> [Entry] {
        GeoResource.allCases.map { resource in
            let url = homeDir.appendingPathComponent(resource.fileName)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                return Entry(resource: resource, sizeBytes: nil, updatedAt: nil)
            }
            return Entry(resource: resource,
                         sizeBytes: (attributes[.size] as? NSNumber)?.intValue,
                         updatedAt: attributes[.modificationDate] as? Date)
        }
    }
}
