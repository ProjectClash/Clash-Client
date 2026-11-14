import AppKit
import ClashClientUI
import ServiceManagement

 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacLoginItem {
    enum State: Equatable {
        case on
        case off
         
         
        case needsApproval
    }

     
    static var service: any ClashMacLoginItemService = ClashMacMainAppLoginItem()

    static var state: State {
        state(of: service.status)
    }

    nonisolated static func state(of status: SMAppService.Status) -> State {
        switch status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
         
        case .notRegistered, .notFound: .off
        @unknown default: .off
        }
    }

     
     
    static func set(_ on: Bool) throws {
        if on {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        service.openSystemSettings()
    }

     
     
     
     
    static func change(to on: Bool, report: (Error) -> Void) {
        do {
            try set(on)
        } catch {
            if on, state == .needsApproval {
                openSystemSettings()
            } else {
                report(error)
            }
        }
    }

     
     
     
     
     
     
     
    nonisolated static func launchedAsLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

     
     
     
     
     
    static func reportFailure(_ error: Error, turningOn: Bool, on window: NSWindow?, locale: Locale) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ClashCopy.string(
            turningOn ? "Clash could not be set to launch at login." : "Clash could not be stopped from launching at login.",
            locale: locale
        )
         
         
        alert.informativeText = ClashCopy.string(
            "You can turn Clash on or off in System Settings › General › Login Items.", locale: locale
        ) + "\n\n" + ClashErrorCopy.message(error, locale: locale)
        alert.addButton(withTitle: ClashCopy.string("OK", locale: locale))
        alert.addButton(withTitle: ClashCopy.string("Open System Settings", locale: locale))
        NSApplication.shared.activate(ignoringOtherApps: true)
        let answered: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertSecondButtonReturn { openSystemSettings() }
        }
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            alert.beginSheetModal(for: window, completionHandler: answered)
        } else {
            answered(alert.runModal())
        }
    }
}

 
@MainActor
protocol ClashMacLoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
struct ClashMacMainAppLoginItem: ClashMacLoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

 
 
 
 
 
 
struct ClashMacQuietLaunch {
    static let wait: TimeInterval = 5
    private(set) var until: Date?

    mutating func arm(at now: Date) {
        until = now.addingTimeInterval(Self.wait)
    }

    mutating func cancel() {
        until = nil
    }

     
     
    mutating func putsAway(at now: Date) -> Bool {
        defer { until = nil }
        guard let until else { return false }
        return now < until
    }
}
