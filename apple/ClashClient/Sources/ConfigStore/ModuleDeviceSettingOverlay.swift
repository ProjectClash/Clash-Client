import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleDeviceSettingOverlay: Equatable, Sendable {
     
    private(set) var values: [ModuleDeviceSettingKey: String] = [:]
     
    private(set) var moduleIDs: [ModuleDeviceSettingKey: String] = [:]

    init() {}

     
     
     
    init(_ settings: [ModuleGlobalManifest.ModuleSettings]) {
        for module in settings {
            for setting in module.deviceSettings {
                values[setting.key] = setting.value
                moduleIDs[setting.key] = module.moduleID
            }
        }
    }

    var isEmpty: Bool { values.isEmpty }

     
    func bool(_ key: ModuleDeviceSettingKey, else app: Bool) -> Bool {
        guard let written = values[key] else { return app }
        return ModuleSettingsMapping.boolean(written) ?? app
    }

    func string(_ key: ModuleDeviceSettingKey, else app: String) -> String {
        values[key] ?? app
    }

     

     
    static func file(in locations: ModuleLocations) -> URL {
        locations.container.appendingPathComponent(ClashTunnelRouteShaping.moduleDeviceSettingsPath)
    }

     
     
     
     
     
     
    static func load(locations: ModuleLocations? = .production) -> ModuleDeviceSettingOverlay {
        guard let locations else { return ModuleDeviceSettingOverlay() }
        let url = file(in: locations)
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let kept = Cache.shared.overlay(at: url, date: date) { return kept }
        let overlay = date == nil ? ModuleDeviceSettingOverlay() : read(url)
        Cache.shared.keep(overlay, at: url, date: date)
        return overlay
    }

    private static func read(_ url: URL) -> ModuleDeviceSettingOverlay {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return ModuleDeviceSettingOverlay() }
        var overlay = ModuleDeviceSettingOverlay()
        for (name, value) in object {
            guard let key = ModuleDeviceSettingKey(rawValue: name) else { continue }
            overlay.values[key] = value
        }
        return overlay
    }

     
    private final class Cache: @unchecked Sendable {
        static let shared = Cache()
        private let lock = NSLock()
        private var kept: [URL: (date: Date?, overlay: ModuleDeviceSettingOverlay)] = [:]

        func overlay(at url: URL, date: Date?) -> ModuleDeviceSettingOverlay? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = kept[url], entry.date == date else { return nil }
            return entry.overlay
        }

        func keep(_ overlay: ModuleDeviceSettingOverlay, at url: URL, date: Date?) {
            lock.lock()
            kept[url] = (date, overlay)
            lock.unlock()
        }
    }

     
     
     
    func publish(to locations: ModuleLocations) throws {
        let url = Self.file(in: locations)
        defer {
            let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            Cache.shared.keep(date == nil ? ModuleDeviceSettingOverlay() : Self.read(url), at: url, date: date)
        }
        guard !values.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let object = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if (try? Data(contentsOf: url)) == data { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

extension VPNTunnelSettings {
     
     
    func overlaid(by overlay: ModuleDeviceSettingOverlay) -> VPNTunnelSettings {
        guard !overlay.isEmpty else { return self }
        var out = self
        out.includeAllNetworks = overlay.bool(.includeAllNetworks, else: includeAllNetworks)
        out.includeLocalNetworks = overlay.bool(.includeLocalNetworks, else: includeLocalNetworks)
        out.includeAPNs = overlay.bool(.includeAPNs, else: includeAPNs)
#if !os(macOS)
        out.includeCellularServices = overlay.bool(.includeCellularServices, else: includeCellularServices)
#endif
        out.hideVPNIcon = overlay.bool(.hideVPNIcon, else: hideVPNIcon)
        out.homeKitCompatibility = overlay.bool(.homeKitCompatibility, else: homeKitCompatibility)
        return out
    }

     
     
     
    func includeAllNetworksInEffect(moduleNotes: [ModuleDeviceSettingKey: ModuleDeviceSettingNote]) -> Bool {
        moduleNotes[.includeAllNetworks].flatMap { ModuleSettingsMapping.boolean($0.value) } ?? includeAllNetworks
    }

     
     
     
     
     
    func hideVPNIconSwitchIsEnabled(moduleNotes: [ModuleDeviceSettingKey: ModuleDeviceSettingNote]) -> Bool {
        ClashTunnelRouteShaping.appliesHideVPNIcon(includeAllNetworks: includeAllNetworksInEffect(moduleNotes: moduleNotes))
    }
}

extension DelayTestSettings {
     
     
     
    static func effectiveURL(from defaults: UserDefaults = appGroupDefaults,
                             overlay: ModuleDeviceSettingOverlay = .load()) -> String {
        if let written = overlay.values[.testURL], isValid(written) { return written }
        return url(from: defaults)
    }
}
