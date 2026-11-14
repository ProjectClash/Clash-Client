import AppIntents
import SwiftUI
import WidgetKit

@main
struct ClashControlsBundle: WidgetBundle {
    var body: some Widget {
        ClashMainWidget()
         
         
        if #available(iOS 18.0, *) {
            ClashVPNControl()
        }
    }
}

@available(iOS 18.0, *)
struct ClashVPNControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ClashSystemHandoff.controlKind,
            provider: Provider()
        ) { active in
            ControlWidgetToggle(
                "Clash VPN",
                isOn: active,
                action: ClashVPNControlIntent()
            ) { isOn in
                 
                 
                 
                 
                Label(
                    isOn ? "Connected" : "Disconnected",
                    image: ClashSystemHandoff.controlSymbolName
                )
            }
        }
        .displayName("Clash VPN")
        .description("Start or stop the installed Clash VPN profile.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
             
             
             
             
             
             
             
             
            if let live = await ClashVPNControlDriver.isActive() { return live }
            return ClashSystemHandoff().isVPNSnapshotActive
        }
    }
}
