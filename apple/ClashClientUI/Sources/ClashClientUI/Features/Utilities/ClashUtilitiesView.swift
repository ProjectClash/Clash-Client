import SwiftUI

 
 
 
 
 
 
public struct ClashUtilitiesView<Icon: View, DestinationContent: View>: View {
    private let snapshot: AppleClientSnapshot
    @Binding private var destination: ClashUtilitiesDestination
    private let presentationClass: ClashPresentationClass
    private let palette: ClashProductPalette
    private let icon: (ClashSymbol) -> Icon
    private let destinationContent:
        (ClashUtilitiesDestination) -> DestinationContent
    private let omitting: Set<ClashUtilitiesDestination>

    public init(
        snapshot: AppleClientSnapshot,
        destination: Binding<ClashUtilitiesDestination>,
        presentationClass: ClashPresentationClass,
        palette: ClashProductPalette,
        omitting: Set<ClashUtilitiesDestination> = [],
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon,
        @ViewBuilder destinationContent: @escaping (
            ClashUtilitiesDestination
        ) -> DestinationContent
    ) {
        self.snapshot = snapshot
        _destination = destination
        self.presentationClass = presentationClass
        self.palette = palette
        self.omitting = omitting
        self.icon = icon
        self.destinationContent = destinationContent
    }

     
     
    private var visibleSections: [ClashUtilitiesSectionDescriptor] {
        ClashUtilitiesCatalog.sections.compactMap { section in
            let remaining = section.destinations.filter {
                !omitting.contains($0)
            }
            guard !remaining.isEmpty else {
                return nil
            }
            return ClashUtilitiesSectionDescriptor(
                id: section.id,
                destinations: remaining
            )
        }
    }

    public var body: some View {
        ClashProductRootPage(
            palette: palette,
            accessibilityIdentifier: "utilities.root"
        ) {
            ForEach(visibleSections, id: \.id) {
                section in
                ClashProductPageSection(
                    title: section.id.title,
                    palette: palette,
                    presentationClass: presentationClass
                ) {
                    ForEach(section.destinations, id: \.self) {
                        item in
                        destinationLink(item)

                         
                         
                         
                        if item != section.destinations.last,
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
                .accessibilityIdentifier(
                    "utilities.section.\(section.id.title)"
                )
            }
        }
        .background(deepLink)
    }

     
     
     
     
     
     
     
    @ViewBuilder
    private var deepLink: some View {
        if presentationClass == .compactTouch {
             
             
             
             
             
             
             
            ClashRoutedViewDestination(isPresented: deepLinkBinding) {
                if let item = ClashUtilitiesDeepLink.presented(for: destination) {
                    destinationContent(item)
                }
            }
            .opacity(0)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private var deepLinkBinding: Binding<Bool> {
        Binding(
            get: { ClashUtilitiesDeepLink.presented(for: destination) != nil },
            set: { presented in
                guard !presented else { return }
                 
                 
                 
                 
                 
                guard ClashUtilitiesDeepLink.presented(for: destination) != nil
                else { return }
                destination = ClashUtilitiesDeepLink.dismissed
            }
        )
    }

    @ViewBuilder
    private func destinationLink(
        _ item: ClashUtilitiesDestination
    ) -> some View {
        if ClashHubNavigationPolicy.usesSelection(for: presentationClass) {
            Button {
                destination = item
            } label: {
                destinationRow(item)
            }
             
             
             
             
             
             
             
             
            .buttonStyle(ClashPushRowButtonStyle())
            .accessibilityIdentifier("utilities.\(item.rawValue)")
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
            .accessibilityIdentifier("utilities.\(item.rawValue)")
        }
    }

    private func destinationRow(
        _ item: ClashUtilitiesDestination
    ) -> some View {
        ClashProductDestinationRow(
            presentation: snapshot.utilities.presentation(for: item),
            symbol: item.symbol,
            tint: item.accent.color,
            presentationClass: presentationClass,
            palette: palette,
            icon: icon
        )
    }
}
