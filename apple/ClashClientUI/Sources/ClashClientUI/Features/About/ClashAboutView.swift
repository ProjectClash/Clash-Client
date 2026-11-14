import Foundation
import SwiftUI

public enum ClashAboutComponentDetailRole: String, Sendable {
    case version
    case upstream
}

public enum ClashAboutComponent:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case clashCore

    public var id: Self { self }

    public var title: String {
        switch self {
        case .clashCore: "Clash Core"
        }
    }

     
     
     
     
     
     
    public var description: String {
        switch self {
        case .clashCore:
            "The open-source core that carries traffic."
        }
    }

    public var detailRole: ClashAboutComponentDetailRole {
        switch self {
        case .clashCore: .version
        }
    }

    public var accent: ClashAccentRole {
        switch self {
        case .clashCore: .indigo
        }
    }

    public var url: URL {
        switch self {
        case .clashCore:
            URL(string: "https://github.com/ProjectClash/Clash")!
        }
    }
}

 
 
 
 
public enum ClashAboutAcknowledgement:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case mihomo
    case singBox

    public var id: Self { self }

    public var title: String {
        switch self {
        case .mihomo: "mihomo"
        case .singBox: "sing-box"
        }
    }

     
     
    public var role: String {
        switch self {
        case .mihomo: "A rule-based proxy kernel"
        case .singBox: "The universal proxy platform"
        }
    }

     
     
     
    public var url: URL? {
        switch self {
        case .mihomo:
            URL(string: "https://github.com/MetaCubeX/mihomo")
        case .singBox:
            URL(string: "https://github.com/SagerNet/sing-box")
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
public enum ClashAboutLink:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
     
     
    case guide
    case telegram
    case followOnX
    case sourceRepository
    case reportIssue

    public var id: Self { self }

    public var title: String {
        switch self {
        case .guide: "User Guide"
        case .sourceRepository: "Source Repository"
        case .reportIssue: "Ideas & Gripes"
        case .followOnX: "Follow on X"
        case .telegram: "Telegram"
        }
    }

    public var symbol: ClashSymbol {
        switch self {
        case .guide: .bookClosed
        case .sourceRepository: .githubMark
        case .reportIssue: .exclamationmarkBubble
        case .followOnX: .xLogo
        case .telegram: .paperplane
        }
    }

     
     
     
     
     
     
    public func detail(for language: ConfigurationFieldCopy.Language) -> String {
        switch self {
        case .guide:
            let url = url(for: language)
            return (url.host ?? "") + url.path.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression)
        case .sourceRepository: return "github.com/ProjectClash/Clash-Client"
        case .reportIssue: return "GitHub Issues"
        case .followOnX: return "@ClashbyClash"
        case .telegram: return "t.me/clashbyclash"
        }
    }

     
     
     
    public func url(for language: ConfigurationFieldCopy.Language) -> URL {
        switch self {
        case .guide:
            URL(string: ClashSite.root(for: language) + "/guide/")!
        case .sourceRepository:
            URL(string: "https://github.com/ProjectClash/Clash-Client")!
        case .reportIssue:
            URL(string: "https://github.com/ProjectClash/Clash-Client/issues")!
        case .followOnX:
            URL(string: "https://x.com/ClashbyClash")!
        case .telegram:
            URL(string: "https://t.me/clashbyclash")!
        }
    }
}

 
 
 
public enum ClashAboutDocument: String, CaseIterable, Sendable {
    case terms
    case privacy

    public var title: String {
        switch self {
        case .terms: "Terms of Use"
        case .privacy: "Privacy Policy"
        }
    }

     
     
    public func url(for language: ConfigurationFieldCopy.Language) -> URL {
        switch self {
        case .terms: return URL(string: ClashSite.root(for: language) + "/terms")!
        case .privacy: return URL(string: ClashSite.root(for: language) + "/privacy")!
        }
    }
}

 
 
 
enum ClashSite {
    static func root(for language: ConfigurationFieldCopy.Language) -> String {
        language == .en ? "https://clash.md" : "https://clash.md/zh"
    }
}

 
public struct ClashAboutView<
    Icon: View,
    ComponentLogo: View,
    Acknowledgements: View
>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    private let snapshot: ClashAboutSnapshot
    private let palette: ClashProductPalette
    private let developerMode: Binding<Bool>?
    private let icon: (ClashSymbol) -> Icon
    private let componentLogo:
        (ClashAboutComponent) -> ComponentLogo

     
     
     
     
    private let acknowledgements: (AnyView) -> Acknowledgements
     
     
    private let rate: (() -> Void)?

    public init(
        snapshot: ClashAboutSnapshot,
        palette: ClashProductPalette,
        developerMode: Binding<Bool>? = nil,
        rate: (() -> Void)? = nil,
        @ViewBuilder acknowledgements: @escaping (AnyView) -> Acknowledgements = { _ in EmptyView() },
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        @ViewBuilder componentLogo: @escaping (
            ClashAboutComponent
        ) -> ComponentLogo
    ) {
        self.snapshot = snapshot
        self.palette = palette
        self.developerMode = developerMode
        self.acknowledgements = acknowledgements
        self.rate = rate
        self.icon = icon
        self.componentLogo = componentLogo
    }

    public var body: some View {
         
         
         
         
        ClashMacSettingsContainer {
            Section {
                appHeader
                    .padding(.vertical, ClashTheme.Spacing.compact)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Clash, Version \(snapshot.appVersion)"
                    )
                    .accessibilityIdentifier("about.appHeader")

                Text(
                    "The Clash family of clients, powered by the Clash core."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

             
             
             
             
            openSourceSection

            componentsSection

             
             
             
            if let rate {
                Section {
                    Button(action: rate) {
                        linkStyleRow(symbol: .starFill, title: "Rate Clash on the App Store",
                                     detail: nil, trailing: .none, markTint: .yellow)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("about.rate")
                }
            }

            if let developerMode {
                developerSection(developerMode)
            }

             
            acknowledgementsSection

            legalFooter
        }
         
         
        .clashRootHeading("About")
    }

    @ViewBuilder
    private var appHeader: some View {
        if dynamicTypeSize >= .accessibility1 {
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.standard
            ) {
                appIcon
                appIdentity
            }
        } else {
            HStack(spacing: ClashTheme.Spacing.standard) {
                appIcon
                appIdentity
            }
        }
    }

    private var appIcon: some View {
        icon(.catCircleFill)
            .font(.system(size: 56, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
    }

    private var appIdentity: some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            Text("Clash")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Powered by Clash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
             
             
             
            Text("Version \(snapshot.versionLine)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !snapshot.sourceRevision.isEmpty {
                Text(snapshot.sourceRevision)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .clashTextSelectionEnabled()
                    .accessibilityLabel(
                        Text(clash: .format(
                            "Source revision %@",
                            [snapshot.sourceRevision]
                        ))
                    )
                    .accessibilityIdentifier("about.source-revision")
            }
        }
    }

    private var componentsSection: some View {
        Section {
            ForEach(ClashAboutComponent.allCases) { component in
                Link(destination: component.url) {
                    componentRow(component)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "about.component.\(component.rawValue)"
                )
            }
        } header: {
            Text("Components")
                .accessibilityIdentifier("about.section.components")
        }
    }

    @ViewBuilder
    private var acknowledgementsSection: some View {
        Section {
            ForEach(ClashAboutAcknowledgement.allCases) { project in
                if let url = project.url {
                    Link(destination: url) {
                        acknowledgementRow(project, linksOut: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "about.acknowledgement.\(project.rawValue)"
                    )
                } else {
                    acknowledgementRow(project, linksOut: false)
                        .accessibilityIdentifier(
                            "about.acknowledgement.\(project.rawValue)"
                        )
                }
            }
            acknowledgements(AnyView(
                 
                 
                 
                linkStyleRow(symbol: nil, title: "Acknowledgements",
                             detail: nil, trailing: .none)
            ))
            .accessibilityIdentifier("about.acknowledgements")
        } header: {
            Text("Thanks To")
                .accessibilityIdentifier("about.section.acknowledgements")
        }
    }

    private func acknowledgementRow(
        _ project: ClashAboutAcknowledgement,
        linksOut: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.tight
            ) {
                Text(project.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(clash: .copy(project.role))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ClashTheme.Spacing.compact)
            if linksOut {
                componentLinkIcon
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
         
         
        .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: 0))
        .contentShape(Rectangle())
    }

    private func developerSection(
        _ developerMode: Binding<Bool>
    ) -> some View {
        Section {
            Toggle("Developer Mode", isOn: developerMode)
                .accessibilityIdentifier("about.developerMode")
        } header: {
            Text("Advanced")
        } footer: {
            Text(
                "Shows on-device diagnostics and local data maintenance in Tools."
            )
        }
    }

     
     
    private var shownLanguage: ConfigurationFieldCopy.Language { .shown(in: locale) }

    private var openSourceSection: some View {
        Section {
            ForEach(ClashAboutLink.allCases) { link in
                 
                 
                 
                Link(destination: link.url(for: shownLanguage)) {
                    linkRow(link)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about.link.\(link.rawValue)")
            }
        } header: {
            Text("Links")
                .accessibilityIdentifier("about.section.openSource")
        }
    }

    private func componentRow(
        _ component: ClashAboutComponent
    ) -> some View {
        Group {
            if dynamicTypeSize >= .accessibility1 {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.compact
                ) {
                    HStack(
                        alignment: .top,
                        spacing: ClashTheme.Spacing.row
                    ) {
                        componentLogoView(component)
                        componentCopy(component)
                    }

                    HStack(spacing: ClashTheme.Spacing.compact) {
                        componentDetail(component)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        componentLinkIcon
                    }
                    .padding(
                        .leading,
                        ClashTheme.Layout.resolvedDestinationRowIconSize
                            + ClashTheme.Spacing.row
                    )
                }
            } else {
                HStack(spacing: ClashTheme.Spacing.row) {
                    componentLogoView(component)
                    componentCopy(component)
                    Spacer(minLength: ClashTheme.Spacing.compact)
                    componentDetail(component)
                    componentLinkIcon
                }
            }
        }
         
         
         
         
        .padding(
            .vertical,
            ClashMacSettingsMetrics.rowVerticalInset(
                touch: ClashTheme.Spacing.tight
            )
        )
    }

    private func componentLogoView(
        _ component: ClashAboutComponent
    ) -> some View {
        componentLogo(component)
            .frame(
                width: ClashTheme.Layout.resolvedDestinationRowIconSize,
                height: ClashTheme.Layout.resolvedDestinationRowIconSize
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ClashTheme.Radius.icon,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }

    private func componentCopy(
        _ component: ClashAboutComponent
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ClashTheme.Spacing.tight
        ) {
            Text(LocalizedStringKey(component.title))
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Text(LocalizedStringKey(component.description))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func componentDetail(
        _ component: ClashAboutComponent
    ) -> some View {
        if component.detailRole == .version {
            Text(snapshot.coreVersion)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            ClashStatusBadge(
                title: "Upstream",
                tint: component.accent.color,
                role: .category,
                categoryFill: palette.raisedFill,
                requirementFill: palette.raisedFill,
                separator: palette.separator
            )
        }
    }

     
     
     
     
     
    private func linkRow(_ link: ClashAboutLink) -> some View {
        linkStyleRow(symbol: link.symbol, title: link.title, detail: link.detail(for: shownLanguage), trailing: .linksOut)
    }

    enum RowTrailing { case linksOut, none }

    private func linkStyleRow(symbol: ClashSymbol?, title: String, detail: String?, trailing: RowTrailing,
                              markTint: Color? = nil) -> some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            if let symbol {
                icon(symbol)
                    .font(.body)
                    .foregroundStyle(markTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                    .frame(width: linkMarkColumn, height: linkMarkColumn)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(LocalizedStringKey(title))
                    .font(.body)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: ClashTheme.Spacing.compact)
            switch trailing {
            case .linksOut: componentLinkIcon
            case .none: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: 0))
        .contentShape(Rectangle())
    }

     
     
     
     
    private var legalFooter: some View {
        Section {} footer: {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Link(destination: ClashAboutDocument.terms.url(for: shownLanguage)) { Text(clash: .copy(ClashAboutDocument.terms.title)) }
                    .accessibilityIdentifier("about.terms")
                Text(verbatim: "·").accessibilityHidden(true)
                Link(destination: ClashAboutDocument.privacy.url(for: shownLanguage)) { Text(clash: .copy(ClashAboutDocument.privacy.title)) }
                    .accessibilityIdentifier("about.privacy")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, ClashTheme.Spacing.compact)
        }
    }

     
     
    private var linkMarkColumn: CGFloat { 22 }

    private var componentLinkIcon: some View {
        icon(.link)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}
