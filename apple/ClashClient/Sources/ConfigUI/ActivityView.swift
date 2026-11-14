import ClashClientUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ActivityView: View, Equatable {
    let command: ClashCommandClient
    let connections: ConnectionsModel
    @Binding var lens: ClashActivityLens
    let loadsPersistedLogs: Bool
     
     
     
     
    private let lensWhenMade: ClashActivityLens
    #if os(macOS)
     
     
     
     
    @State private var segmentTitles: [(lens: ClashActivityLens, title: String)] = []
    @Environment(\.locale) private var locale
    #endif

    init(command: ClashCommandClient, connections: ConnectionsModel, lens: Binding<ClashActivityLens>,
         loadsPersistedLogs: Bool) {
        self.command = command
        self.connections = connections
        _lens = lens
        self.loadsPersistedLogs = loadsPersistedLogs
        lensWhenMade = lens.wrappedValue
    }

    static func == (lhs: ActivityView, rhs: ActivityView) -> Bool {
        lhs.command === rhs.command
            && lhs.connections === rhs.connections
            && lhs.lensWhenMade == rhs.lensWhenMade
            && lhs.loadsPersistedLogs == rhs.loadsPersistedLogs
    }

     
     
    private static var searchFieldStyle: ClashActivitySearchFieldStyle {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .phoneBottomBar : .standard
        #else
        .standard
        #endif
    }

     
     
     
    private static var showsLensStrip: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    var body: some View {
         
         
        let _ = ClashLogTextPlatform.installIfNeeded()
        #if os(iOS)
         
        let _ = ClashActivityScrollProbe.installIfNeeded()
        #endif
        page
            #if os(iOS)
             
             
            .background {
                if #available(iOS 26, *), Self.searchFieldStyle == .phoneBottomBar { ClashTabBarFollowsThePush() }
            }
            #endif
            #if os(macOS)
             
             
            .clashToolbarUnlessInPanel {
                ToolbarItem(placement: .principal) {
                    Picker(selection: $lens) {
                        ForEach(segmentTitles, id: \.lens) { segment in
                            Text(verbatim: segment.title).tag(segment.lens)
                        }
                    } label: {
                        Text(clash: .copy("Activity"))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("activity.lens.segment")
                }
            }
            .task(id: locale) {
                segmentTitles = ClashActivityLens.allCases.map { ($0, ClashCopy.string($0.title, locale: locale)) }
            }
            #endif
    }

    private var page: some View {
        ClashActivityPageView(
            lens: $lens,
            palette: ClashActivityIOSAdapter.palette,
            searchFieldStyle: Self.searchFieldStyle,
            showsLensStrip: Self.showsLensStrip
        ) { query, isShown in
             
             
             
            ConnectionsView(
                model: connections,
                command: command,
                autoStart: false,
                query: query,
                isShown: isShown
            )
        } requests: { query, isShown in
            RequestsView(model: connections, command: command, query: query, isShown: isShown)
        } logs: { query, isShown in
            LogsDestinationView(
                command: command,
                loadsPersistedLogs: loadsPersistedLogs,
                query: query,
                isShown: isShown
            )
        }
    }
}

#if os(iOS)
 
 
 
 
 
 
 
 
 
 
 
 
 
@available(iOS 26, *)
struct ClashTabBarFollowsThePush: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {}

    final class Probe: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isHidden = true
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setTabBarHidden(true, animated: animated)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setTabBarHidden(false, animated: animated)
        }

        private func setTabBarHidden(_ hidden: Bool, animated: Bool) {
            guard let tabs = tabBarController, tabs.isTabBarHidden != hidden else { return }
            tabs.setTabBarHidden(hidden, animated: animated)
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashActivityScrollProbe {
    @MainActor
    static func installIfNeeded() {
        guard ClashActivityScrollReading.rowProbe == nil else { return }
        ClashActivityScrollReading.rowProbe = { reading in
            AnyView(ClashActivityScrollProbeView(reading: reading).accessibilityHidden(true))
        }
    }

     
     
     
     
     
     
     
     
     
    @MainActor
    static func isReaderScrolling(_ scrollView: UIScrollView) -> Bool {
        guard scrollView.window != nil else { return false }
        if isFingerOnList(scrollView) || scrollView.isDecelerating { return true }
        if #available(iOS 17.4, *), !takesThePathBeforeIOS17_4 { return scrollView.isScrollAnimating }
        return ClashActivityScrollMotion.of(scrollView)?.isMoving ?? false
    }

     
     
    @MainActor static var takesThePathBeforeIOS17_4 = false

     
    @MainActor
    static func isFingerOnList(_ scrollView: UIScrollView) -> Bool {
        scrollView.window != nil && (scrollView.isTracking || scrollView.isDragging)
    }

     
     
     
     
    @MainActor
    static func scrollToTop(_ scrollView: UIScrollView) {
        guard !isReaderScrolling(scrollView) else { return }
        let motion = ClashActivityScrollMotion.of(scrollView)
        motion?.isOwnMove = true
        defer { motion?.isOwnMove = false }
        scrollView.layoutIfNeeded()
        let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
        if scrollView.contentOffset != top { scrollView.setContentOffset(top, animated: false) }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashActivityScrollMotion {
     
    static let frame: CFTimeInterval = 0.004
    static let window: CFTimeInterval = 0.1

    private var observations: [NSKeyValueObservation] = []
     
    private var moves: [CFTimeInterval] = []
    private var laidOut: CFTimeInterval = -.infinity
     
    var isOwnMove = false
    private let clock: () -> CFTimeInterval

    init(observing scrollView: UIScrollView, clock: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.clock = clock
        observations = [
            scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                MainActor.assumeIsolated { self?.offsetChanged(from: change.oldValue, to: change.newValue) }
            },
            scrollView.observe(\.contentSize, options: [.old, .new]) { [weak self] _, change in
                MainActor.assumeIsolated { self?.contentSizeChanged(from: change.oldValue, to: change.newValue) }
            },
        ]
    }

    func offsetChanged(from old: CGPoint?, to new: CGPoint?) {
        guard !isOwnMove, old != new else { return }
        let now = clock()
         
        guard now - laidOut >= Self.frame else { return }
        if let latest = moves.last, now - latest < Self.frame { return }
        moves = Array((moves + [now]).suffix(2))
    }

    func contentSizeChanged(from old: CGSize?, to new: CGSize?) {
        guard old != new else { return }
        let now = clock()
        laidOut = now
         
        if let latest = moves.last, now - latest < Self.frame { moves.removeLast() }
    }

    var isMoving: Bool {
        guard moves.count == 2 else { return false }
        return clock() - moves[1] < Self.window && moves[1] - moves[0] < Self.window
    }

    private static var key = 0

     
    static func of(_ scrollView: UIScrollView) -> ClashActivityScrollMotion? {
        objc_getAssociatedObject(scrollView, &key) as? ClashActivityScrollMotion
    }

     
    static func watch(_ scrollView: UIScrollView) {
        guard of(scrollView) == nil else { return }
        objc_setAssociatedObject(
            scrollView, &key, ClashActivityScrollMotion(observing: scrollView), .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

 
 
 
 
final class ClashActivityListTouchLatch: UIGestureRecognizer {
    weak var reading: ClashActivityScrollReading?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        reading?.fingerTouched()
        state = .failed
    }

     
    @MainActor
    static func install(on scrollView: UIScrollView, for reading: ClashActivityScrollReading) {
        if let latch = scrollView.gestureRecognizers?.lazy.compactMap({ $0 as? ClashActivityListTouchLatch }).first {
            latch.reading = reading
            return
        }
        let latch = ClashActivityListTouchLatch(target: nil, action: nil)
        latch.cancelsTouchesInView = false
        latch.delaysTouchesBegan = false
        latch.delaysTouchesEnded = false
        latch.reading = reading
        scrollView.addGestureRecognizer(latch)
    }
}

private struct ClashActivityScrollProbeView: UIViewRepresentable {
    let reading: ClashActivityScrollReading

    func makeUIView(context: Context) -> ClashActivityScrollProbeUIView {
        let view = ClashActivityScrollProbeUIView()
        view.reading = reading
        return view
    }

    func updateUIView(_ view: ClashActivityScrollProbeUIView, context: Context) {
        guard view.reading !== reading else { return }
        view.reading = reading
        view.attach()
    }
}

final class ClashActivityScrollProbeUIView: UIView {
    weak var reading: ClashActivityScrollReading?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

     
     
    func attach() {
        guard window != nil, let reading else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scrollView = ancestor as? UIScrollView else { return }
        ClashActivityScrollMotion.watch(scrollView)
        ClashActivityListTouchLatch.install(on: scrollView, for: reading)
        reading.isReaderScrolling = { [weak scrollView] in
            scrollView.map { ClashActivityScrollProbe.isReaderScrolling($0) } ?? false
        }
        reading.isFingerOnList = { [weak scrollView] in
            scrollView.map(ClashActivityScrollProbe.isFingerOnList) ?? false
        }
        reading.scrollToTop = { [weak scrollView] in
            scrollView.map(ClashActivityScrollProbe.scrollToTop)
        }
    }
}
#endif
