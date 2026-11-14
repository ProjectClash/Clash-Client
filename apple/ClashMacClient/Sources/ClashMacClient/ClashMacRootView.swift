import ClashClientUI
import SwiftUI

public struct ClashMacRootView: View {
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let secondaryContent: @MainActor (ClashMacSecondaryDestination) -> AnyView
     
     
     
    private let detailOverlay:
        @MainActor (ClashClientUI.ClashRootDestination?) -> AnyView
    private let moreAttentionAction: @MainActor (String) -> Void

    @State private var navigationState:
        ClashClientUI.AppleClientNavigationState
    @State private var configurationDestination:
        ClashMacSecondaryDestination = .configuration
    @State private var isPickingProfile = false
    @Binding private var navigationRequest:
        ClashMacSecondaryDestination?

    public init(
        snapshot: AppleClientSnapshot,
        selection: ClashMacDestination = .home,
        actions: AppleClientActions,
        navigationRequest:
            Binding<ClashMacSecondaryDestination?> = .constant(nil),
        secondaryContent: @escaping @MainActor (ClashMacSecondaryDestination) -> AnyView = {
            AnyView(ClashMacSecondaryUnavailableView(destination: $0))
        },
        detailOverlay: @escaping @MainActor (
            ClashClientUI.ClashRootDestination?
        ) -> AnyView = { _ in AnyView(EmptyView()) },
         
         
         
        moreAttentionAction: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.secondaryContent = secondaryContent
        self.detailOverlay = detailOverlay
        self.moreAttentionAction = moreAttentionAction
        _navigationRequest = navigationRequest
        _navigationState = State(
            initialValue: ClashClientUI.AppleClientNavigationState(
                selectedRoot: selection
            )
        )
    }

    public var body: some View {
         
         
         
        ClashClientUI.ClashRegularClientShell(
            navigationState: $navigationState,
            sidebarBehavior: .fixed,
            background: ClashMacPlatformPresentation.palette.canvas,
            sidebarBackground: ClashMacPlatformPresentation.palette.surface
        ) { destination in
            ClashSymbolImage(
                symbol: destination.symbol,
                resizesToFit: true
            )
        } rootContent: { destination in
            sharedProductPage(for: destination)
        } destinationContent: { destination in
            sharedDestinationContent(destination)
        } detailOverlay: { destination in
            detailOverlay(destination)
        }
        .frame(minWidth: 880, minHeight: 600)
         
         
         
        .background(ClashMacSidebarLock())
         
         
         
        .environment(
            \.clashFullWidthSegmentedPickerAdapter,
            ClashMacPlatformPresentation.fullWidthSegmentedPickerAdapter
        )
        .accessibilityIdentifier("clash.mac.root")
        .onAppear {
            ClashNavigationHooks.resignCurrentField =
                ClashMacPlatformPresentation.resignCurrentField
             
             
             
            ClashMacFrameCounter.install()
            consumeNavigationRequest()
        }
        .onChange(of: navigationRequest) { _ in
            consumeNavigationRequest()
        }
        .clashPageProbe("window-root")
    }

    @ViewBuilder
    private func sharedProductPage(
        for destination: ClashClientUI.ClashRootDestination
    ) -> some View {
        switch destination {
        case .home:
             
             
             
             
             
            ClashDeferredPageContent {
            ClashClientUI.ClashHomeView(
                snapshot: snapshot,
                actions: navigationAwareActions,
                presentationClass: .regularTouch,
                palette: productPalette,
                 
                 
                customizationPresentation: { _ in
                    AnyView(
                        ClashMacCardCustomizationPanel(
                            favorites: snapshot.home.favoriteCards
                        ) { cards in
                            let actions = navigationAwareActions
                            let snapshot = snapshot
                            Task {
                                try? await actions.perform(
                                    .home(.setCards(cards)),
                                    allowedBy: snapshot
                                )
                            }
                        }
                    )
                }
            ) { symbol in
                 
                 
                 
                 
                 
                 
                 
                ClashSymbolImage(symbol: symbol)
                    .popover(
                        isPresented: profilePickerPresentation(for: symbol),
                        arrowEdge: .bottom
                    ) {
                        ClashMacProfilePicker(
                            profiles: snapshot.profiles.profiles,
                            select: { id in
                                isPickingProfile = false
                                Task { @MainActor in
                                    try? await actions.perform(
                                        .selectProfile(id: id),
                                        allowedBy: snapshot
                                    )
                                }
                            }
                        )
                    }
                     
                     
                     
                     
                     
                     
                     
                     
                    .onChange(of: chipIsTheAddDoor) { isAddDoor in
                        if isAddDoor { isPickingProfile = false }
                    }
            }
            } placeholder: {
                ClashMacPlatformPresentation.palette.canvas
                    .ignoresSafeArea()
            }
        case .utilities:
            ClashClientUI.ClashUtilitiesView(
                snapshot: snapshot,
                destination: utilitiesDestinationBinding,
                presentationClass: .regularTouch,
                palette: productPalette,
                     
                 
                 
                 
                omitting: ClashUtilitiesCatalog.regularHubExcludes,
                icon: { symbol in
                    ClashSymbolImage(symbol: symbol)
                },
                destinationContent: { destination in
                    sharedDestinationContent(.utilities(destination))
                }
            )
        case .more:
            ClashClientUI.ClashMoreView(
                snapshot: snapshot,
                destination: moreDestinationBinding,
                presentationClass: .regularTouch,
                palette: productPalette,
                 
                 
                omitting: ClashMoreCatalog.regularHubExcludes,
                attentionAction: moreAttentionAction,
                icon: { symbol in
                    ClashSymbolImage(symbol: symbol)
                },
                destinationContent: { destination in
                    sharedDestinationContent(.more(destination))
                }
            )
        case .profiles, .proxies, .rules, .activity, .about:
            sharedDestinationContent(destination.productDestination)
        }
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashMacPlatformPresentation.palette
    }

    private var navigationAwareActions: AppleClientActions {
        let components = actions.providedCapabilities.map { capability in
            AppleClientActions(capability: capability) { action in
                navigate(for: action)
                try await actions.perform(action, allowedBy: snapshot)
            }
        }
        return (try? AppleClientActions.composing(components))
            ?? .unavailable
    }

    private var utilitiesDestinationBinding:
        Binding<ClashUtilitiesDestination>
    {
        Binding(
            get: {
                guard navigationState.selectedRoot == .utilities,
                      case .utilities(let destination) =
                        navigationState.destination
                else {
                    return .root
                }
                return destination
            },
            set: { destination in
                openUtility(destination)
            }
        )
    }

    private var moreDestinationBinding:
        Binding<ClashMoreDestination>
    {
        Binding(
            get: {
                guard navigationState.selectedRoot == .more,
                      case .more(let destination) =
                        navigationState.destination
                else {
                    return .root
                }
                return destination
            },
            set: { destination in
                openMore(destination)
            }
        )
    }

    private func sharedDestinationContent(
        _ destination: ClashClientUI.AppleClientDestination
    ) -> AnyView {
        if destination == .configuration {
            return secondaryContent(configurationDestination)
        }
        if let macDestination = ClashMacSecondaryDestination(
            sharedDestination: destination
        ) {
            return secondaryContent(macDestination)
        } else {
            return AnyView(sharedProductPage(for: destination.root))
        }
    }

    private func consumeNavigationRequest() {
        guard let requested = navigationRequest else { return }
        if requested.isConfigurationDestination {
            configurationDestination = requested
        }
        navigationState.navigate(to: requested.sharedDestination)
        navigationRequest = nil
    }

    private func navigate(for action: AppleClientAction) {
        let destination: ClashClientUI.AppleClientDestination?
        switch action {
        case .home(let command):
            if let requested =
                ClashMacSecondaryDestination(homeCommand: command)
            {
                configurationDestination = requested
                destination = .configuration
            } else {
                switch command {
                case .openProfiles:
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if chipIsTheAddDoor {
                        isPickingProfile = false
                         
                         
                         
                         
                         
                         
                        destination = .profiles
                    } else {
                        isPickingProfile = true
                        destination = nil
                    }
                case .openProxies:
                    destination = .proxies
                case .openRules:
                    destination = .rules
                case .performPrimaryAction, .showConnectionIssue,
                     .resetVPNProfile, .setCards, .setTrafficScope,
                     .refreshExternalIP, .refreshLANIP:
                    destination = nil
                case .openOnDemand:
                     
                     
                    destination = nil
                case .openRuntimeConfiguration:
                    destination = nil
                }
            }
        case .rules(.openActiveRules):
            destination = .activeRules
        case .rules(.openProxiesGroup):
            destination = .proxies
        case .dns(.openDNSQuery):
            destination = .dnsQuery
        default:
            destination = nil
        }
        if let destination {
            navigationState.navigate(to: destination)
        }
    }

    private func openUtility(_ destination: ClashUtilityDestination) {
        if destination == .root {
            navigationState.selectRoot(.utilities)
            return
        }
        navigationState.navigate(to: .utilities(destination))
        Task { @MainActor in
            try? await actions.perform(
                .openUtility(destination),
                allowedBy: snapshot
            )
        }
    }

    private func openMore(_ destination: ClashMoreDestination) {
        if destination == .root {
            navigationState.selectRoot(.more)
            return
        }
        navigationState.navigate(to: .more(destination))
        Task { @MainActor in
            try? await actions.perform(
                .openMore(destination),
                allowedBy: snapshot
            )
        }
    }
}

private extension ClashMacSecondaryDestination {
    var isConfigurationDestination: Bool {
        switch self {
        case .runtimeConfiguration, .configuration:
            true
        case .profiles, .proxies, .rules, .activeRules, .dnsQuery,
             .utility, .more:
            false
        }
    }

    var sharedDestination: ClashClientUI.AppleClientDestination {
        switch self {
        case .profiles:
            .profiles
        case .proxies:
            .proxies
        case .rules:
            .rules
        case .activeRules:
            .activeRules
        case .dnsQuery:
            .dnsQuery
        case .runtimeConfiguration, .configuration:
            .configuration
        case .utility(let destination):
            .utilities(destination)
        case .more(let destination):
            .more(destination)
        }
    }

    init?(
        sharedDestination destination: ClashClientUI.AppleClientDestination
    ) {
        switch destination {
        case .profiles, .profileImport, .profileDetail, .modules:
            self = .profiles
        case .proxies:
            self = .proxies
        case .rules:
            self = .rules
        case .activeRules:
            self = .activeRules
        case .dnsQuery:
            self = .dnsQuery
        case .configuration:
            self = .configuration
        case .utilities(let destination) where destination != .root:
            self = .utility(destination)
        case .more(let destination) where destination != .root:
            self = .more(destination)
        case .home, .utilities, .more:
            return nil
        }
    }
}

extension ClashMacRootView {
}

extension ClashMacRootView {
     
     
     
     
     
     
     
     
     
     
     
    fileprivate var chipIsTheAddDoor: Bool {
        snapshot.home.selectedProfileIsSystemFallback
            || snapshot.profiles.profiles.isEmpty
    }

     
     
     
     
    fileprivate func profilePickerPresentation(
        for symbol: ClashSymbol
    ) -> Binding<Bool> {
        guard symbol == .chevronDown, !chipIsTheAddDoor else {
            return .constant(false)
        }
        return $isPickingProfile
    }
}
