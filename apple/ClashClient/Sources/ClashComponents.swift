import SwiftUI
import UIKit
import ClashClientUI

private struct ClashRegularDetailLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var clashUsesRegularDetailLayout: Bool {
        get { self[ClashRegularDetailLayoutKey.self] }
        set { self[ClashRegularDetailLayoutKey.self] = newValue }
    }
}

private struct ClashRegularDetailPageLayoutModifier: ViewModifier {
    let isEnabled: Bool
    @Environment(\.clashDetailCanvas) private var detailCanvas

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            ClashClientUI.ClashRegularDetailPageLayout(
                background: detailCanvas ?? ClashTheme.canvas
            ) {
                content
            }
        } else {
            content
        }
    }
}

 
 
 
 
 
 
private struct ClashDetailPageInsets: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.clashRegularDetailPageLayout(
            enabled: horizontalSizeClass == .regular
        )
    }
}

extension View {
    func clashRegularDetailPageLayout(enabled: Bool) -> some View {
        modifier(ClashRegularDetailPageLayoutModifier(isEnabled: enabled))
    }

     
    func clashDetailPageInsets() -> some View {
        modifier(ClashDetailPageInsets())
    }
}

 
 
typealias ClashSymbol = ClashClientUI.ClashSymbol

extension ClashClientUI.ClashSymbol {
     
     
    var name: String {
        if isCustom {
            return rawValue
        }

        return candidates.first(where: { UIImage(systemName: $0) != nil }) ?? rawValue
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

 
 
struct ClashGlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

     
     
     
     
    var body: AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                GlassEffectContainer(spacing: spacing) {
                    content
                }
            )
        }
        return AnyView(content)
    }
}

extension View {
     
     

     
     
     
     
     
    func clashSecondaryActionButtonStyle() -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(buttonStyle(.glass))
        }
        return AnyView(buttonStyle(.bordered))
    }

}

typealias ClashSelectionMark = ClashClientUI.ClashSelectionMark

 
 
 
 
struct ClashCardSurface<Content: View>: View {
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
        }
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
        ClashCardSurface {
            content
                .padding(ClashTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
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

typealias ClashBadgeRole = ClashClientUI.ClashBadgeRole

struct ClashStatusBadge: View {
    let title: String
    let tint: Color
    var role: ClashBadgeRole = .status

    var body: some View {
        ClashClientUI.ClashStatusBadge(
            title: title,
            tint: tint,
            role: role,
            categoryFill: Color(uiColor: .tertiarySystemFill),
            requirementFill: Color(uiColor: .secondarySystemGroupedBackground),
            separator: ClashTheme.separator
        )
    }
}

 
 
struct ClashDestinationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

     
     
     
     
    let title: ClashDisplayText
     
     
     
     
    var subtitle: ClashDisplayText?
    let symbol: ClashSymbol
    let tint: Color
    var badge: String?
    var badgeTint: Color = .blue
    var badgeRole: ClashBadgeRole = .requirement
     
     
     
    var linksOut = false

    var body: some View {
         
         
         
         
         
         
         
         
         
         
         

         
         
         
         
         
         
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
            spacing: ClashTheme.Spacing.row
        ) {
            ClashIconWell(symbol: symbol, tint: tint)

            VStack(
                alignment: .leading,
                spacing: ClashTheme.Typography.rowSubtitleGap(locale)
            ) {
                HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.compact) {
                    Text(clash: title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let badge, !dynamicTypeSize.isAccessibilitySize {
                        ClashStatusBadge(title: badge, tint: badgeTint, role: badgeRole)
                    }
                }

                if let subtitle {
                    Text(clash: subtitle)
                        .font(ClashTheme.Typography.rowSubtitle(locale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let badge, dynamicTypeSize.isAccessibilitySize {
                    ClashStatusBadge(title: badge, tint: badgeTint, role: badgeRole)
                }
            }

            Spacer(minLength: 0)
            if linksOut {
                externalLinkIcon
            }
        }
         
         
         
         
         
         
        .padding(.vertical, subtitle == nil ? 0 : ClashTheme.Spacing.compact)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var externalLinkIcon: some View {
        ClashSymbolImage(symbol: .link)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

 
 
struct ClashPrimaryDestinationRow: View {
    let title: ClashDisplayText
    let subtitle: ClashDisplayText
    let symbol: ClashSymbol
    let tint: Color

    var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            ClashDestinationRow(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                tint: tint
            )

             
             
            if !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                ClashSymbolImage(symbol: .chevronForward)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, ClashTheme.Spacing.compact)
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

extension View {
     
     
     
    func clashEmptyStateListCard() -> some View {
        self
            .background(
                RoundedRectangle(
                    cornerRadius: ClashTheme.Radius.groupedSection,
                    style: .continuous
                )
                .fill(ClashTheme.surface)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: ClashTheme.Radius.groupedSection,
                    style: .continuous
                )
                .stroke(ClashTheme.separator.opacity(0.16), lineWidth: 0.5)
            )
            .listRowInsets(
                EdgeInsets(
                    top: ClashTheme.Spacing.standard,
                    leading: ClashTheme.Spacing.standard,
                    bottom: ClashTheme.Spacing.standard,
                    trailing: ClashTheme.Spacing.standard
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

enum ClashStatusKind {
    case information
    case success
    case warning
    case error

    var symbol: ClashSymbol {
        switch self {
        case .information: return .infoCircleFill
        case .success: return .checkmarkCircleFill
        case .warning: return .exclamationmarkTriangleFill
        case .error: return .xmarkOctagonFill
        }
    }

    var tint: Color {
        switch self {
        case .information: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
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
                .foregroundStyle(kind == .information ? .secondary : kind.tint)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.symbol.name)
                .foregroundStyle(kind.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

 
 
 
struct ClashFeedbackOverlay: View {
    let presentation: ClashFeedbackPresentation
    let dismissTitle: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            ClashCardSurface {
                VStack(spacing: ClashTheme.Spacing.standard) {
                    feedbackSymbol
                        .frame(width: 64, height: 64)

                    VStack(spacing: ClashTheme.Spacing.compact) {
                        Text(clash: presentation.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if let message = presentation.message,
                           !message.rawValue.isEmpty {
                            Text(clash: message)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if presentation.requiresExplicitDismissal {
                        Button(dismissTitle.clashLocalized, action: onDismiss)
                            .font(.headline)
                            .clashPrimaryActionButtonStyle()
                            .controlSize(.large)
                            .frame(
                                minWidth: 140,
                                minHeight: ClashClientUI.ClashTheme.Control
                                    .minimumHitTarget
                            )
                            .accessibilityIdentifier(
                                "\(presentation.accessibilityIdentifier).dismiss"
                            )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(.horizontal, ClashTheme.Spacing.section)
                .padding(.vertical, ClashTheme.Spacing.standard)
            }
            .frame(maxWidth: 336)
            .padding(.horizontal, ClashTheme.Spacing.section)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(clash: presentation.title))
        .accessibilityValue(presentation.message?.rawValue ?? "")
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            if presentation.requiresExplicitDismissal {
                onDismiss()
            }
        }
        .onAppear(perform: announce)
        .onChange(of: presentation) { _ in announce() }
    }

    @ViewBuilder
    private var feedbackSymbol: some View {
        switch presentation.kind {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.blue)
                .accessibilityHidden(true)
        case .success:
            statusSymbol(.checkmarkCircleFill, tint: .green)
        case .information:
            statusSymbol(.infoCircleFill, tint: .blue)
        case .warning:
            statusSymbol(.exclamationmarkTriangleFill, tint: .orange)
        case .error:
            statusSymbol(.xmarkOctagonFill, tint: .red)
        }
    }

    private func statusSymbol(_ symbol: ClashSymbol, tint: Color) -> some View {
        ClashSymbolImage(symbol: symbol)
            .font(.system(size: 52, weight: .semibold))
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private func announce() {
         
        let spoken = [presentation.title, presentation.message]
            .compactMap { $0?.resolved(locale: .current) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        UIAccessibility.post(notification: .announcement, argument: spoken)
    }
}

private struct ClashFeedbackOverlayModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var presentation: ClashFeedbackPresentation?
    let dismissTitle: String

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(presentation != nil)

            if let presentation {
                ClashFeedbackOverlay(
                    presentation: presentation,
                    dismissTitle: dismissTitle,
                    onDismiss: { self.presentation = nil }
                )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.96).combined(with: .opacity)
                    )
                    .zIndex(1)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: presentation
        )
    }
}

extension View {
     
     
    func clashFeedbackOverlay(
        _ presentation: Binding<ClashFeedbackPresentation?>,
        dismissTitle: String
    ) -> some View {
        modifier(
            ClashFeedbackOverlayModifier(
                presentation: presentation,
                dismissTitle: dismissTitle
            )
        )
    }
}


