import AppKit
import ClashClientUI
import SwiftUI

private struct ClashMacRegularDetailLayoutKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var clashUsesRegularDetailLayout: Bool {
        get { self[ClashMacRegularDetailLayoutKey.self] }
        set { self[ClashMacRegularDetailLayoutKey.self] = newValue }
    }
}

 
 
 
typealias ClashSymbol = ClashClientUI.ClashSymbol
typealias ClashBadgeRole = ClashClientUI.ClashBadgeRole
typealias UITextContentType = ClashMacTextContentType

 
 
 
 
 
enum ClashMacAsset: String {
    case menuBarTemplate = "ClashMenuBarTemplate"
}

extension Image {
    init(clashMacAsset asset: ClashMacAsset) {
        self.init(asset.rawValue)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashMacSymbolNameCache {
    private static let guardrail = NSLock()
    nonisolated(unsafe) private static var resolved: [ClashClientUI.ClashSymbol: String] = [:]

    static func name(for symbol: ClashClientUI.ClashSymbol) -> String {
        guardrail.lock()
        let cached = resolved[symbol]
        guardrail.unlock()
        if let cached { return cached }
        let answer = probe(symbol)
        guardrail.lock()
        resolved[symbol] = answer
        guardrail.unlock()
        return answer
    }

    private static func probe(_ symbol: ClashClientUI.ClashSymbol) -> String {
        if symbol.isCustom { return symbol.rawValue }
        return symbol.candidates.first {
            NSImage(
                systemSymbolName: $0,
                accessibilityDescription: nil
            ) != nil
        } ?? symbol.rawValue
    }

    static func resetForTesting() {
        guardrail.lock(); resolved.removeAll(); guardrail.unlock()
    }

    static func isResolvedForTesting(_ symbol: ClashClientUI.ClashSymbol) -> Bool {
        guardrail.lock(); defer { guardrail.unlock() }
        return resolved[symbol] != nil
    }
}

extension ClashClientUI.ClashSymbol {
    var name: String {
        ClashMacSymbolNameCache.name(for: self)
    }
}

struct ClashSymbolImage: View {
    let symbol: ClashSymbol
    var resizesToFit = false

    @ViewBuilder
    var body: some View {
        Group {
            if symbol.isCustom {
                 
                rendered(symbol.customImage())
            } else {
                rendered(Image(systemName: symbol.name))
            }
        }
        .scaleEffect(symbol.opticalScale)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rendered(_ image: Image) -> some View {
        if resizesToFit {
            image
                .resizable()
                .scaledToFit()
        } else {
            image
        }
    }
}

struct ClashIconWell: View {
    let symbol: ClashSymbol
    let tint: Color

    var body: some View {
        ClashClientUI.ClashIconWell(tint: tint) {
            ClashSymbolImage(symbol: symbol)
                .font(.body.weight(.semibold))
        }
    }
}

struct ClashStatusBadge: View {
    let title: String
    let tint: Color
    var role: ClashBadgeRole = .status

    var body: some View {
        ClashClientUI.ClashStatusBadge(
            title: title,
            tint: tint,
            role: role,
            categoryFill: Color(nsColor: .controlBackgroundColor),
            requirementFill: Color(nsColor: .controlBackgroundColor),
            separator: Color(nsColor: .separatorColor)
        )
    }
}

struct ClashFeatureCard<Content: View>: View {
    let content: Content
    var isInteractive: Bool = false

    init(
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        ClashClientUI.ClashCardSurface(
            fill: ClashTheme.surface,
            separator: ClashTheme.separator
        ) {
            content
                .padding(ClashTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ClashOverviewCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ClashClientUI.ClashCardSurface(
            fill: ClashTheme.surface,
            separator: ClashTheme.separator
        ) {
            content
                .padding(ClashTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct OverviewBadge {
    let title: String
    let tint: Color
}

struct OverviewCardHeader: View {
    let title: String
    let symbol: ClashSymbol
    let tint: Color
    var badge: OverviewBadge?

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            ClashIconWell(symbol: symbol, tint: tint)
            Text(clash: .copy(title))
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let badge {
                ClashStatusBadge(
                    title: badge.title,
                    tint: badge.tint
                )
            }
        }
    }
}

struct ClashGlassEffectContainer<Content: View>: View {
    let content: Content

    init(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        _ = spacing
        self.content = content()
    }

    var body: some View {
        content
    }
}

struct ClashDestinationRow: View {
    let title: ClashDisplayText
    var subtitle: ClashDisplayText?
    let symbol: ClashSymbol
    let tint: Color
    var badge: String?
    var badgeTint: Color = .blue
    var badgeRole: ClashBadgeRole = .requirement
    var linksOut = false

     
     
     
     
     
     
     
     
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
            spacing: ClashTheme.Spacing.row
        ) {
            ClashClientUI.ClashIconWell(tint: tint) {
                ClashSymbolImage(symbol: symbol)
                    .font(.body.weight(.semibold))
            }

            VStack(
                alignment: .leading,
                spacing: ClashTheme.Typography.rowSubtitleGap(locale)
            ) {
                HStack(alignment: .firstTextBaseline) {
                    Text(clash: title)
                    if let badge, !dynamicTypeSize.isAccessibilitySize {
                        ClashClientUI.ClashStatusBadge(
                            title: badge,
                            tint: badgeTint,
                            role: badgeRole,
                            categoryFill: Color(
                                nsColor: .controlBackgroundColor
                            ),
                            requirementFill: Color(
                                nsColor: .controlBackgroundColor
                            ),
                            separator: Color(nsColor: .separatorColor)
                        )
                    }
                }
                if let subtitle {
                    Text(clash: subtitle)
                        .font(ClashTheme.Typography.rowSubtitle(locale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let badge, dynamicTypeSize.isAccessibilitySize {
                    ClashClientUI.ClashStatusBadge(
                        title: badge,
                        tint: badgeTint,
                        role: badgeRole,
                        categoryFill: Color(nsColor: .controlBackgroundColor),
                        requirementFill: Color(nsColor: .controlBackgroundColor),
                        separator: Color(nsColor: .separatorColor)
                    )
                }
            }
            Spacer(minLength: 0)
            if linksOut {
                ClashSymbolImage(symbol: .link)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, subtitle == nil ? 0 : ClashTheme.Spacing.compact)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ClashEmptyState: View {
    let title: String
    let message: String
    let symbol: ClashSymbol
    var isLoading = false

    var body: some View {
        ClashClientUI.ClashEmptyState(
            title: title,
            message: message,
            isLoading: isLoading
        ) {
            ClashSymbolImage(symbol: symbol)
        }
    }
}

struct OverviewValueRow: View {
    let title: ClashDisplayText
    let value: ClashDisplayText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Text(clash: title)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(clash: value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(ClashPlatformLayout.pageUsesSystemSettingsIdiom ? ClashMacSettingsType.value : .subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct RuntimeMetricRow: View {
    let title: ClashDisplayText
    let value: ClashDisplayText
    let symbol: ClashSymbol

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Label {
                Text(clash: title)
            } icon: {
                Image(systemName: symbol.name)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(clash: value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

enum ClashStatusKind {
    case information
    case success
    case warning
    case error

    var symbol: ClashSymbol {
        switch self {
        case .information: .infoCircleFill
        case .success: .checkmarkCircleFill
        case .warning: .exclamationmarkTriangleFill
        case .error: .xmarkOctagonFill
        }
    }

    var tint: Color {
        switch self {
        case .information: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

struct ClashStatusMessage: View {
    let text: ClashDisplayText
    let kind: ClashStatusKind

    var body: some View {
        Label {
            Text(clash: text)
                .font(.subheadline)
                .foregroundStyle(
                    kind == .information ? .secondary : kind.tint
                )
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.symbol.name)
                .foregroundStyle(kind.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ClashMacRegularDetailPageLayoutModifier: ViewModifier {
    let isEnabled: Bool
    @Environment(\.clashDetailCanvas) private var detailCanvas
    @Environment(\.clashInsideModalPresentation)
    private var insideNativeModal
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled && !(insideProductModal || insideNativeModal) {
            ClashClientUI.ClashRegularDetailPageLayout(
                 
                 
                 
                 
                 
                background: detailCanvas
                    ?? Color(nsColor: .underPageBackgroundColor)
            ) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func clashRegularDetailPageLayout(enabled: Bool) -> some View {
        modifier(
            ClashMacRegularDetailPageLayoutModifier(isEnabled: enabled)
        )
    }

    func clashDetailPageInsets() -> some View {
        clashRegularDetailPageLayout(enabled: true)
    }

    func keyboardType(_ type: ClashMacKeyboardType) -> some View {
        self
    }

    func textInputAutocapitalization(
        _ behavior: ClashMacTextInputAutocapitalization
    ) -> some View {
        self
    }

    func textContentType(
        _ type: ClashMacTextContentType?
    ) -> some View {
        self
    }

    func clashSecondaryActionButtonStyle() -> some View {
        buttonStyle(.bordered)
    }
}

enum ClashMacKeyboardType {
    case `default`
    case URL
    case asciiCapable
    case numberPad
    case numbersAndPunctuation
}

enum ClashMacTextInputAutocapitalization {
    case never
}

enum ClashMacTextContentType {
    case URL
}

enum ByteRateFormatter {
    static func string(_ bytesPerSecond: Int64, unit: ClashThroughputUnit) -> String {
        ClashThroughputFormatter.rate(bytesPerSecond, unit: unit)
    }
}

enum ByteCountFormatter {
    static func string(_ bytes: Int64) -> String {
        let absolute = Double(max(bytes, 0))
        if absolute < 1_024 {
            return String(format: "%.0f B", absolute)
        }
        if absolute < 1_048_576 {
            return String(format: "%.1f KB", absolute / 1_024)
        }
        if absolute < 1_073_741_824 {
            return String(format: "%.1f MB", absolute / 1_048_576)
        }
        return String(format: "%.2f GB", absolute / 1_073_741_824)
    }
}
