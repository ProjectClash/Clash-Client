import SwiftUI

 
 
 
 
 
public struct ClashMoreView<Icon: View, DestinationContent: View>: View {
    private let snapshot: AppleClientSnapshot
    @Binding private var destination: ClashMoreDestination
    private let presentationClass: ClashPresentationClass
    private let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon
    private let destinationContent:
        (ClashMoreDestination) -> DestinationContent
    private let omitting: Set<ClashMoreDestination>
     
     
    private let attentionAction: (String) -> Void

    public init(
        snapshot: AppleClientSnapshot,
        destination: Binding<ClashMoreDestination>,
        presentationClass: ClashPresentationClass,
        palette: ClashProductPalette,
        omitting: Set<ClashMoreDestination> = [],
        attentionAction: @escaping (String) -> Void = { _ in },
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        @ViewBuilder destinationContent: @escaping (
            ClashMoreDestination
        ) -> DestinationContent
    ) {
        self.snapshot = snapshot
        _destination = destination
        self.presentationClass = presentationClass
        self.palette = palette
        self.omitting = omitting
        self.attentionAction = attentionAction
        self.icon = icon
        self.destinationContent = destinationContent
    }

     
     
    private var visibleSections: [ClashMoreSectionDescriptor] {
        ClashMoreCatalog.sections.compactMap { section in
            let remaining = section.destinations.filter {
                !omitting.contains($0)
            }
            guard !remaining.isEmpty else {
                return nil
            }
            return ClashMoreSectionDescriptor(
                id: section.id,
                destinations: remaining
            )
        }
    }

    public var body: some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "more.root"
        ) {
            if let attention = snapshot.more.attention {
                attentionSection(attention)
            }
            ForEach(visibleSections, id: \.id) { section in
                productSection(
                    title: section.id.title,
                    identifier: "more.section.\(section.id.title)",
                    destinations: section.destinations
                )
            }

            if snapshot.more.showsDeveloperDestination {
                productSection(
                    title: "Development",
                    identifier: "more.section.Development",
                    destinations: [.developer]
                )
            }
        }
    }


     
     
     
     
    private func attentionSection(_ attention: ClashMoreAttention) -> some View {
        ClashProductPageSection(
            title: "Needs Attention",
            palette: palette,
            presentationClass: presentationClass
        ) {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                HStack(alignment: .top, spacing: ClashTheme.Spacing.compact) {
                    icon(attention.emphasised ? .exclamationmarkTriangle : .infoCircle)
                    Text(clash: attention.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: ClashTheme.Spacing.row) {
                    ForEach(attention.actions) { action in
                        Button(role: action.destructive ? .destructive : nil) {
                            attentionAction(action.id)
                        } label: {
                            Text(clash: action.title)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("more.legacy-settings-action.\(action.id)")
                    }
                }
            }
            .padding(.vertical, ClashTheme.Spacing.tight)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("more.legacy-settings")
        }
    }

    private func productSection(
        title: String,
        identifier: String,
        destinations: [ClashMoreDestination]
    ) -> some View {
        ClashProductPageSection(
            title: title,
            palette: palette,
            presentationClass: presentationClass
        ) {
            ForEach(destinations, id: \.self) { item in
                destinationLink(item)

                 
                 
                 
                if item != destinations.last,
                   !ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                    Divider()
                        .padding(
                            .leading,
                            ClashTheme.Layout
                                .destinationRowDividerInset
                        )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func destinationLink(
        _ item: ClashMoreDestination
    ) -> some View {
        if ClashHubNavigationPolicy.usesSelection(for: presentationClass) {
            Button {
                destination = item
            } label: {
                destinationRow(item)
            }
             
             
             
             
             
             
             
             
            .buttonStyle(ClashPushRowButtonStyle())
            .accessibilityIdentifier("more.\(item.rawValue)")
        } else {
             
             
             
             
             
             
            NavigationLink {
                ClashLazyView {
                    destinationContent(item)
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                .clashNativePushBoundary()
            } label: {
                destinationRow(item)
            }
             
             
             
             
             
             
             
             
            .buttonStyle(ClashPushRowButtonStyle())
            .accessibilityIdentifier("more.\(item.rawValue)")
        }
    }

    private func destinationRow(
        _ item: ClashMoreDestination
    ) -> some View {
        ClashProductDestinationRow(
            presentation: snapshot.more.presentation(for: item),
            symbol: item.symbol,
            tint: item.accent.color,
            presentationClass: presentationClass,
            palette: palette,
            icon: icon
        )
    }
}
