import SwiftUI

#if os(macOS)
 
 
 
 
 
private struct ClashRegularDetailNavigationLayout: Layout {
    let maximumContentWidth: CGFloat
    let horizontalInset: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else {
            return CGSize(
                width: proposal.width ?? 0,
                height: proposal.height ?? 0
            )
        }
         
         
         
         
         
         
         
        if let width = proposal.width, let height = proposal.height {
            return CGSize(width: width, height: height)
        }
        let measured = subview.sizeThatFits(proposal)
        return CGSize(
            width: proposal.width ?? measured.width,
            height: proposal.height ?? measured.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }

        let availableWidth = max(
            0,
            bounds.width - (horizontalInset * 2)
        )
        let contentWidth = min(
            maximumContentWidth,
            availableWidth
        )
        subview.place(
            at: CGPoint(
                x: bounds.midX - (contentWidth / 2),
                y: bounds.minY
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: contentWidth,
                height: bounds.height
            )
        )
    }
}
#endif

 
 
 
 
 
 
public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashRegularContentEnvelope() -> some View {
        accessibilityElement(children: .contain)
            .accessibilityIdentifier(ClashRegularContentEnvelope.identifier)
    }
}

 
 
public enum ClashRegularContentEnvelope {
    public static let identifier = "regular.content.envelope"
}

 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashInsideDetailPageLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var clashInsideDetailPageLayout: Bool {
        get { self[ClashInsideDetailPageLayoutKey.self] }
        set { self[ClashInsideDetailPageLayoutKey.self] = newValue }
    }
}

 
 
 
 
 
 
public struct ClashSetterRoutedBack: ViewModifier {
    @Environment(\.clashPopRoute) private var popRoute
    @Environment(\.clashNavigationDepth) private var depth
     
     
     
     
    @Environment(\.clashDeparturePage) private var departurePage
     
     
     
    @Environment(\.clashRootDepartureGuard) private var departureGuard

    public init() {}

     
     
     
     
     
    private var canGoBack: Bool {
        guard popRoute != nil || ClashNavigationHooks.pop != nil else {
            return false
        }
         
         
        guard let depth else { return true }
        return depth > 0
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
#if os(macOS)
        if canGoBack {
            content
                .navigationBarBackButtonHidden(true)
                 
                 
                 
                 
                 
                .clashToolbarUnlessInPanel {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            ClashNavigationTransaction.resignCurrentField()
                            let leave: () -> Void = {
                                if let popRoute {
                                    popRoute(ClashPopToken())
                                } else {
                                    ClashNavigationHooks.pop?()
                                }
                            }
                             
                             
                             
                             
                             
                             
                             
                            ClashDeparture.requestBack(
                                departureGuard,
                                from: departurePage,
                                leave: leave
                            )
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                         
                         
                        .accessibilityIdentifier("chevron.backward")
                        .accessibilityLabel(Text(ClashCopy.key("Back")))
                    }
                }
        } else {
            content
        }
#else
        content
#endif
    }
}

 
public struct ClashPopToken: Hashable {
    public init() {}
}

public extension View {
     
     
     
     
     
     
    @ViewBuilder
    func clashRegularStackCanvas(_ canvas: Color) -> some View {
#if os(macOS)
        environment(\.clashDetailCanvas, canvas)
#else
        self
#endif
    }
}

 
 
 
 
public enum ClashRegularDetailCanvasFallback {
    nonisolated(unsafe) public static var color: Color?
}

 
 
 
 
 
 
 
 
 
 
 
 
struct ClashRegularDetailFullBleedPreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct ClashRegularDetailBleedMarginKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
     
     
    var clashRegularDetailBleedMargin: CGFloat? {
        get { self[ClashRegularDetailBleedMarginKey.self] }
        set { self[ClashRegularDetailBleedMarginKey.self] = newValue }
    }
}

extension View {
     
    func clashRegularDetailBleedAligned() -> some View {
        modifier(ClashRegularDetailBleedAligned())
    }
}

private struct ClashRegularDetailBleedAligned: ViewModifier {
    @Environment(\.clashRegularDetailBleedMargin) private var margin
    func body(content: Content) -> some View {
        content.padding(.horizontal, margin ?? 0)
    }
}

extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashRegularStripPage<Strip: View>(
        @ViewBuilder strip: @escaping () -> Strip
    ) -> some View {
        modifier(ClashRegularStripRowsMargin())
            .clashPinnedTopBar {
                strip()
                    .clashRegularDetailBleedAligned()
                    .modifier(ClashRegularStripGround())
            }
            .modifier(ClashRegularStripBleed())
    }
}

 
 
 
 
private struct ClashRegularStripRowsMargin: ViewModifier {
    @Environment(\.clashRegularDetailBleedMargin) private var margin
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 17.0, *) {
            content.safeAreaPadding(.horizontal, margin ?? 0)
        } else {
            content
        }
#else
        content
#endif
    }
}

 
private struct ClashRegularStripGround: ViewModifier {
    @Environment(\.clashRegularDetailBleedMargin) private var margin
    @Environment(\.clashDetailCanvas) private var canvas
    func body(content: Content) -> some View {
        content.background(margin != nil ? (canvas ?? .clear) : .clear)
    }
}

 
 
private struct ClashRegularStripBleed: ViewModifier {
    @Environment(\.clashRegularDetailBleedMargin) private var margin
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectHidden(margin != nil, for: .top)
                .preference(key: ClashRegularDetailFullBleedPreferenceKey.self, value: true)
        } else if #available(iOS 17.0, *) {
            content.preference(key: ClashRegularDetailFullBleedPreferenceKey.self, value: true)
        } else {
            content
        }
#else
        content
#endif
    }
}

public struct ClashRegularDetailNavigationFrame<Content: View>: View {
    private let background: Color
    private let content: Content
    @State private var fullBleed = false

    public init(
        background: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.background = background
        self.content = content()
    }

    public var body: some View {
        contentColumn
            .clashRegularContentEnvelope()
            .environment(\.clashInsideDetailPageLayout, true)
            .background(background.ignoresSafeArea())
            .environment(
                \.defaultMinListRowHeight,
                ClashTheme.Regular.Detail.destinationRowMinHeight
            )
            .environment(\.clashDetailCanvas, background)
            .modifier(ClashRegularDetailSurfacePolicy())
            .modifier(ClashRegularDetailTitleScale())
    }

    @ViewBuilder
    private var contentColumn: some View {
#if os(macOS)
        ClashRegularDetailNavigationLayout(
            maximumContentWidth: ClashTheme.Regular.Detail.maximumContentWidth,
            horizontalInset: ClashTheme.Regular.Detail.horizontalInset
        ) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
         
         
         
        GeometryReader { proxy in
            let inset = ClashTheme.Regular.Detail.horizontalInset
            let spare = proxy.size.width - 2 * inset
                - ClashTheme.Regular.Detail.maximumContentWidth
            content
                 
                 
                 
                 
                 
                 
                .frame(
                    maxWidth: fullBleed ? .infinity : ClashTheme.Regular.Detail.maximumContentWidth,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, fullBleed ? 0 : inset)
                .environment(\.clashRegularDetailBleedMargin, fullBleed ? inset + max(0, spare / 2) : nil)
        }
        .onPreferenceChange(ClashRegularDetailFullBleedPreferenceKey.self) { fullBleed = $0 }
#endif
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashRegularDetailTitleScale: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 17.0, *) {
            content.toolbarTitleDisplayMode(.inline)
        } else {
            content.navigationBarTitleDisplayMode(.inline)
        }
#else
        content
#endif
    }
}

 
 
public struct ClashRegularDetailPageLayout<Content: View>: View {
    @Environment(\.clashInsideDetailPageLayout) private var alreadyPlaced

    private let background: Color
    private let maximumContentWidth: CGFloat
    private let content: Content

    public init(
        background: Color,
        maximumContentWidth: CGFloat = ClashTheme.Regular.Detail.maximumContentWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.background = background
        self.maximumContentWidth = maximumContentWidth
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        if alreadyPlaced {
             
             
             
            content
        } else {
            pageLayout
                .clashRegularContentEnvelope()
                .environment(\.clashInsideDetailPageLayout, true)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    private var contentColumn: some View {
        content
            .frame(
                maxWidth: maximumContentWidth,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            .padding(
                .horizontal,
                ClashTheme.Regular.Detail.horizontalInset
            )
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private var pageLayout: some View {
        contentColumn
            .background(background.ignoresSafeArea())
            .environment(
                \.defaultMinListRowHeight,
                ClashTheme.Regular.Detail.destinationRowMinHeight
            )
            .environment(\.clashDetailCanvas, background)
            .modifier(ClashRegularDetailSurfacePolicy())
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashRegularDetailSurfacePolicy: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content
            .formStyle(.grouped)
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
#else
        content
#endif
    }
}

 
 
 
 
 
 
 
private struct ClashDetailCanvasKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

public extension EnvironmentValues {
    var clashDetailCanvas: Color? {
        get { self[ClashDetailCanvasKey.self] }
        set { self[ClashDetailCanvasKey.self] = newValue }
    }
}

public extension View {
     
     
     
     
     
     
     
     
     
    func clashPushedDetailPage() -> some View {
        modifier(ClashPushedDetailPageModifier())
    }
}

extension View {
     
     
     
     
     
     
    func clashPushedTopAccessory(background: Color) -> some View {
        modifier(ClashPushedTopAccessory(background: background))
    }
}

private struct ClashPushedTopAccessory: ViewModifier {
    let background: Color
#if os(macOS)
    @Environment(\.clashDetailTopAccessory) private var accessory
    @Environment(\.clashDetailTopAccessoryPlaced) private var placed
#endif

     
     
     
     
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        let draws = accessory != nil && !placed
        VStack(spacing: 0) {
            if draws, let accessory { accessory }
            content.environment(\.clashDetailTopAccessoryPlaced, true)
        }
        .background {
            if draws { background.ignoresSafeArea() }
        }
#else
        content
#endif
    }
}

private struct ClashPushedDetailPageModifier: ViewModifier {
#if os(macOS)
    private var isRegular: Bool { true }
    private var fallbackCanvas: Color {
         
         
         
         
         
         
         
         
         
         
        ClashRegularDetailCanvasFallback.color
            ?? Color(nsColor: .underPageBackgroundColor)
    }
#elseif os(tvOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var fallbackCanvas: Color {
        Color(uiColor: .black)
    }
#else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var fallbackCanvas: Color {
        Color(uiColor: .systemGroupedBackground)
    }
#endif
    @Environment(\.clashDetailCanvas) private var canvas
    @Environment(\.clashInsideModalPresentation)
    private var insideNativeModal
    @Environment(\.clashInsideProductModalPresentation)
    private var insideProductModal
#if os(macOS)
    @Environment(\.clashNavigationDepth) private var inheritedDepth
#endif

    func body(content: Content) -> some View {
        Group {
#if os(macOS)
        if insideProductModal || insideNativeModal {
             
             
             
             
             
            content
        } else {
            ClashRegularDetailPageLayout(background: canvas ?? fallbackCanvas) {
                content
            }
             
             
             
             
             
            .navigationBarBackButtonHidden(true)
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            .environment(\.clashNavigationDepth, (inheritedDepth ?? 0) + 1)
             
            .clashPushedTopAccessory(background: canvas ?? fallbackCanvas)
        }
#else
        if isRegular {
            ClashRegularDetailPageLayout(background: canvas ?? fallbackCanvas) {
                content
            }
        } else {
            content
        }
#endif
        }
         
         
        .onAppear { ClashPushClock.arrived() }
    }
}
