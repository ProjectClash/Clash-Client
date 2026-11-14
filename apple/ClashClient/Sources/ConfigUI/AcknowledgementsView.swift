import ClashClientUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private enum AckModalRoute: Identifiable {
    case license(ThirdPartyLicenseInventory.Module)
    case allModules

    var id: String {
        switch self {
        case .license(let module): "license-\(module.id)"
        case .allModules: "all-modules"
        }
    }
}

struct AcknowledgementsView: View {
    private let inventory = ThirdPartyLicenseInventory.shared
    @State private var modalRoute: AckModalRoute?
    @Environment(\.locale) private var locale
#if os(macOS)
    @Environment(\.clashDoorMayPush) private var mayPush
#endif

     
    @ViewBuilder
    private func door<DoorLabel: View>(
        macOS route: @autoclosure @escaping () -> AckModalRoute,
        @ViewBuilder destination: @escaping () -> some View,
        @ViewBuilder label: () -> DoorLabel
    ) -> some View {
#if os(macOS)
         
         
         
         
         
        if mayPush {
            ClashRoutedViewLink {
                destination()
            } label: {
                label()
            }
        } else {
            Button {
                 
                 
                 
                 
                 
                 
                ClashPageProbe.markNavigation()
                modalRoute = route()
            } label: {
                HStack(spacing: 6) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: ClashSymbol.chevronForward.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
#else
        ClashRoutedViewLink {
            destination()
        } label: {
            label()
        }
#endif
    }

    var body: some View {
         
         
         
         
        ClashMacSettingsContainer {
            Section {
                if let module = inventory.module(
                    AcknowledgementsCatalog.framework.module
                ) {
                    door(macOS: .license(module)) {
                        LicenseTextView(module: module)
                    } label: {
                        row(module, role: AcknowledgementsCatalog.framework.role)
                    }
                    .accessibilityIdentifier("acknowledgements.framework")
                }
            } header: {
                Text(clash: .copy("Framework"))
            } footer: {
                Text(clash: .verbatim(
                    AcknowledgementsCatalog.sourceOfferStatement
                ))
            }

            Section {
                ForEach(AcknowledgementsCatalog.highlights) { highlight in
                    if let module = inventory.module(highlight.module) {
                        door(macOS: .license(module)) {
                            LicenseTextView(module: module)
                        } label: {
                            row(module, role: highlight.role)
                        }
                        .accessibilityIdentifier(
                            "acknowledgements.\(module.shortName)"
                        )
                    }
                }
            } header: {
                Text(clash: .copy("Inside Clash"))
            } footer: {
                Text(clash: .copy(
                    "This app calls none of these directly. All of them are compiled into the binary it ships."
                ))
            }

            Section {
                door(macOS: .allModules) {
                    LinkedModulesView(inventory: inventory)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clash: .copy("All linked modules"))
                        Text(clash: summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("acknowledgements.allModules")
            }
             
             
             
             
             
             
             
             

            Section {
                ForEach(AcknowledgementsCatalog.systemFrameworks) { framework in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clash: .verbatim(framework.name))
                            .font(.subheadline.weight(.semibold))
                        Text(clash: .copy(framework.usage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(clash: .copy("System frameworks"))
            } footer: {
                Text(clash: .copy(
                    "These ship with the operating system rather than with this app, and are named here to describe what it is built against."
                ))
            }

            Section {
                ForEach(AcknowledgementsCatalog.trademarkNotices, id: \.self) {
                    notice in
                    Text(clash: .verbatim(notice))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(clash: .copy("Trademarks"))
            } footer: {
                Text(clash: .verbatim(
                    AcknowledgementsCatalog.trademarkStatement
                ))
            }
        }
        .clashGroupedList()
        .clashDetailPageInsets()
#if os(macOS)
         
         
        .clashProductModal(item: $modalRoute, role: .form) { route in
            ClashFeatureNavigationContainer {
                 
                 
                 
                 
                 
                Group {
                    switch route {
                    case .license(let module):
                        LicenseTextView(module: module)
                    case .allModules:
                        LinkedModulesView(inventory: inventory)
                    }
                }
                .clashProductModalRoot(title: {
                    switch route {
                     
                    case .license(let module): ClashDisplayText.verbatim(module.module)
                    case .allModules: ClashDisplayText.copy("Linked modules")
                    }
                }())
            }
            .clashPageSizedSheet()
        }
#endif
#if os(macOS)
        .clashPageTitle(.copy("Acknowledgements"), watchAs: "acknowledgements")
#else
        .clashPageTitle(.copy("Acknowledgements"), watchAs: "acknowledgements")
#endif
         
         
         
#if os(macOS)
        .clashPageProbe("acknowledgements")
#endif
        .accessibilityIdentifier("legal.Acknowledgements")
    }

     
     
     
    private var summary: ClashDisplayText {
        let chinese = ConfigurationFieldCopy.Language.shown(in: locale) != .en
        let families = inventory.licenseSummary
            .prefix(4)
            .map { #"\#($0.license) \#(ClashCopy.count($0.count, locale: locale))"# }
            .joined(separator: chinese ? "\u{3001}" : #", "#)
        return .format("%@ modules · %@", [ClashCopy.count(inventory.modules.count, locale: locale), families])
    }

    @ViewBuilder
    private func row(
        _ module: ThirdPartyLicenseInventory.Module, role: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clash: .verbatim(module.shortName))
                .font(.subheadline.weight(.semibold))
             
             
            Text(clash: .copy(role))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(clash: .verbatim(versionLine(module)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func versionLine(
        _ module: ThirdPartyLicenseInventory.Module
    ) -> String {
        module.version.isEmpty
            ? module.license
            : #"\#(module.license) · \#(module.version)"#
    }
}

 
 
 
 
 
struct LinkedModulesView: View {
    let inventory: ThirdPartyLicenseInventory

    @ViewBuilder
    var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            List {
                ForEach(inventory.modules) { module in
#if os(macOS)
                    Button {
                        push(module)
                    } label: {
                        HStack(spacing: 6) {
                            moduleLabel(module)
                            Spacer(minLength: 0)
                            Image(
                                systemName: ClashSymbol.chevronForward.rawValue
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                     
                     
                     
                     
                    .accessibilityIdentifier(
                        "acknowledgements.module.\(module.shortName)"
                    )
#else
                    moduleLabel(module)
#endif
                }
            }
            .clashMacSettingsList(minRowHeight: 30)
            .clashDetailPageInsets()
#if os(macOS)
            .clashPageTitle(.copy("Linked modules"), watchAs: "linked-modules")
#else
            .clashPageTitle(.copy("Linked modules"), watchAs: "linked-modules")
#endif
            .accessibilityIdentifier("acknowledgements.modules")
             
             
             
             
            .clashProductModal(item: $modalModule, role: .form) { module in
                ClashFeatureNavigationContainer {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    LicenseTextView(module: module)
#if os(macOS)
                        .clashProductModalRoot(title: .verbatim(module.module))
#endif
                }
                .clashPageSizedSheet()
            }
        } else {
            List {
                ForEach(inventory.modules) { module in
                    ClashRoutedViewLink {
                        LicenseTextView(module: module)
                    } label: {
                        moduleLabel(module)
                    }
                }
            }
            .clashGroupedList()
            .clashDetailPageInsets()
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            .clashPageTitle(.copy("Linked modules"), watchAs: "linked-modules")
            .accessibilityIdentifier("acknowledgements.modules")
        }
    }


     
     
     
    @State private var modalModule: ThirdPartyLicenseInventory.Module?
#if os(macOS)
    @Environment(\.clashDoorMayPush) private var mayPush
    @Environment(\.clashPushRoute) private var pushRoute
    @State private var routeToken = UUID()
#endif

     
     
     
     
     
     
     
     
     
     
     
     
    @MainActor
    private func push(_ module: ThirdPartyLicenseInventory.Module) {
#if os(macOS)
        ClashPushAuthorityProbe.trace(
            "licence-row", mayPush: mayPush, hasPusher: pushRoute != nil
        )
        if mayPush, let pushRoute {
            ClashViewRouteRegistry.set(
                routeToken,
                ownership: .rowOwned,
                onReturn: {}
            ) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                AnyView(
                    LicenseTextView(module: module)
                        .clashProductModalChild(title: .verbatim(module.module))
                )
            }
            pushRoute(ClashViewRoute(id: routeToken))
            return
        }
#endif
        modalModule = module
    }

    @ViewBuilder
    private func moduleLabel(
        _ module: ThirdPartyLicenseInventory.Module
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clash: .verbatim(module.module))
                .font(.subheadline)
            Text(clash: .verbatim(
                module.version.isEmpty
                    ? module.license
                    : #"\#(module.license) · \#(module.version)"#
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let note = module.note {
                Text(clash: .verbatim(note))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

 
struct LicenseTextView: View {
    let module: ThirdPartyLicenseInventory.Module

    var body: some View {
        content
            .clashDetailPageInsets()
            .clashPageTitle(
                .verbatim(module.shortName), watchAs: "license-module"
            )
            .accessibilityIdentifier("license.\(module.shortName)")
    }

    @ViewBuilder
    private var content: some View {
#if canImport(AppKit)
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
             
             
             
             
             
            ClashMacLicenseText(
                text: ThirdPartyLicenseInventory.shared.text(for: module)
            )
        } else {
            touchScroll
        }
#else
        touchScroll
#endif
    }

    private var touchScroll: some View {
        ScrollView {
             
             
            Text(clash: .verbatim(
                ThirdPartyLicenseInventory.shared.text(for: module)
            ))
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ClashTheme.Spacing.standard)
        }
    }
}

#if canImport(AppKit)
 
private struct ClashMacLicenseText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        scroll.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular
        )
        textView.textContainerInset = NSSize(
            width: ClashTheme.Spacing.standard,
            height: ClashTheme.Spacing.standard
        )
         
         
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }
}
#endif
