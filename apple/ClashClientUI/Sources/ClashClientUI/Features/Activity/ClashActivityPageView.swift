import SwiftUI

 
 
 
 
 
 
 
 
public enum ClashActivityLens: String, CaseIterable, Hashable, Sendable {
    case connections
    case requests
    case logs

     
     
     
     
     
     
    public var destination: ClashUtilitiesDestination {
        switch self {
        case .connections: .connections
        case .requests: .requests
        case .logs: .logs
        }
    }

    public var title: String { destination.title }

     
     
    var searchPrompt: LocalizedStringKey {
        switch self {
        case .connections, .requests: "Destination, route, or rule"
        case .logs: "Search logs"
        }
    }

     
     
     
     
     
     
     
    public init?(destination: ClashUtilitiesDestination) {
        switch destination {
        case .connections: self = .connections
        case .requests: self = .requests
        case .logs: self = .logs
        default: return nil
        }
    }
}

 
 
 
 
 
 
public enum ClashActivitySearchFieldStyle: Sendable {
     
     
     
     
     
    case phoneBottomBar
     
    case standard
}

 
 
 
 
 
 
 
 
 
 
 
public struct ClashActivityPageView<
    Connections: View,
    Requests: View,
    Logs: View
>: View {
    @Binding private var lens: ClashActivityLens
    private let palette: ClashProductPalette
    private let searchFieldStyle: ClashActivitySearchFieldStyle
    private let connections: (String, Bool) -> Connections
    private let requests: (String, Bool) -> Requests
    private let logs: (String, Bool) -> Logs
     
     
     
     
    private let showsLensStrip: Bool

     
     
     
     
     
     
     
     
     
     
    @State private var query = ""
#if os(macOS)
     
     
     
     
     
    @State private var shownLens: ClashActivityLens
#endif


    @Environment(\.locale) private var locale

     
     
     
     
     
     
     
     
     
     
     
     
     
    @State private var options:
        [ClashFullWidthSegmentedOption<ClashActivityLens>] = []

    public init(
        lens: Binding<ClashActivityLens>,
        palette: ClashProductPalette,
        searchFieldStyle: ClashActivitySearchFieldStyle = .standard,
        showsLensStrip: Bool = true,
        @ViewBuilder connections: @escaping (String, Bool) -> Connections,
        @ViewBuilder requests: @escaping (String, Bool) -> Requests,
        @ViewBuilder logs: @escaping (String, Bool) -> Logs
    ) {
        _lens = lens
#if os(macOS)
        _shownLens = State(initialValue: lens.wrappedValue)
#endif
        self.palette = palette
        self.searchFieldStyle = searchFieldStyle
        self.showsLensStrip = showsLensStrip
        self.connections = connections
        self.requests = requests
        self.logs = logs
    }

    public var body: some View {
        searchField(
            lensContent
                .clashRegularStripPage {
                    if showsLensStrip { strip }
                }
        )
            .task(id: locale) { options = Self.options(in: locale) }
             
             
             
             
             
            .clashRootHeading("Activity", watchAs: "activity.\(lens.rawValue)")
         
         
         
         
         
         
         
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var lensContent: some View {
#if os(macOS)
        ZStack {
            resident(connections(query, shownLens == .connections), shown: shownLens == .connections)
            resident(requests(query, shownLens == .requests), shown: shownLens == .requests)
            if shownLens == .logs { logs(query, true) }
        }
        .onChange(of: lens) { next in
            DispatchQueue.main.async { shownLens = next }
        }
#else
        switch lens {
        case .connections: connections(query, true)
        case .requests: requests(query, true)
        case .logs: logs(query, true)
        }
#endif
    }

#if os(macOS)
    private func resident<Lens: View>(_ content: Lens, shown: Bool) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .zIndex(shown ? 1 : 0)
    }
#endif

     
     
     
     
     
     
     
    @ViewBuilder
    private func searchField<Content: View>(_ content: Content) -> some View {
        switch searchFieldStyle {
        case .phoneBottomBar:
            #if os(iOS)
            if #available(iOS 26, *) {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                content.searchable(text: $query, placement: .toolbar, prompt: lens.searchPrompt)
                    .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                    .toolbar(.hidden, for: .tabBar)
            } else {
                content.searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: lens.searchPrompt
                )
            }
            #else
            content.searchable(text: $query, prompt: lens.searchPrompt)
            #endif
        case .standard:
            content.searchable(text: $query, prompt: lens.searchPrompt)
        }
    }

     
     
     
     
    private var strip: some View {
        ClashFullWidthSegmentedPicker(
            selection: $lens,
            options: options,
            role: .pageStrip,
            underlineSeparator: palette.separator
        )
         
         
         
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClashTheme.Spacing.standard)
    }

     
     
     
     
    private static func options(
        in locale: Locale
    ) -> [ClashFullWidthSegmentedOption<ClashActivityLens>] {
        ClashActivityLens.allCases.map { candidate in
            ClashFullWidthSegmentedOption(
                selection: candidate,
                title: ClashCopy.string(candidate.title, locale: locale),
                accessibilityIdentifier:
                    "activity.lens.\(candidate.rawValue)"
            )
        }
    }
}


 
 
 
 
 
 
 
private struct ClashActivityLensToolbar<Items: ToolbarContent>: ViewModifier {
    let active: Bool
    let items: () -> Items

    func body(content: Content) -> some View {
        if #available(iOS 16, macOS 13, tvOS 16, *) {
            content.clashToolbarUnlessInPanel { if active { items() } }
        } else {
            content.clashToolbarUnlessInPanel { items() }
        }
    }
}

extension View {
    func clashActivityLensToolbar<Items: ToolbarContent>(
        active: Bool,
        @ToolbarContentBuilder _ items: @escaping () -> Items
    ) -> some View {
        modifier(ClashActivityLensToolbar(active: active, items: items))
    }
}
