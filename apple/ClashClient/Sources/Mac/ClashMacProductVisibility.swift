import AppKit
import Combine
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashMacProductVisibility {
    struct Window: Equatable {
         
         
        var shown: Bool
        var miniaturized: Bool
        var occluded: Bool
         
        var keyBeforeOcclusionReport: Bool

        init(shown: Bool = true, miniaturized: Bool = false, occluded: Bool, keyBeforeOcclusionReport: Bool = false) {
            self.shown = shown
            self.miniaturized = miniaturized
            self.occluded = occluded
            self.keyBeforeOcclusionReport = keyBeforeOcclusionReport
        }
    }

     
     
     
    static func isVisible(
        appHidden: Bool,
        windows: [Window],
        everHadWindow: Bool = false
    ) -> Bool {
        if appHidden { return false }
        let present = windows.filter { $0.shown || $0.miniaturized }
        guard !present.isEmpty else { return !everHadWindow }
        return present.contains {
            !$0.miniaturized && (!$0.occluded || $0.keyBeforeOcclusionReport)
        }
    }

     
     
     
    static func settle(current: Bool, read: Bool, mayHide: Bool, appHidden: Bool) -> Bool {
        if read { return true }
        return (mayHide || appHidden) ? false : current
    }
}

 
 
 
 
 
@MainActor
final class ClashMacSnapshotGate<Value> {
    private let deliver: (Value) -> Void
    private(set) var isVisible = true
    private(set) var isMenuTracking = false
    private(set) var held: Value?
    private(set) var latest: Value?

    init(deliver: @escaping (Value) -> Void) {
        self.deliver = deliver
    }

    var isOpen: Bool { isVisible && !isMenuTracking }

    func send(_ value: Value) {
        latest = value
        if isOpen {
            deliver(value)
        } else {
            held = value
        }
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        flush()
    }

    func setMenuTracking(_ tracking: Bool) {
        guard tracking != isMenuTracking else { return }
        isMenuTracking = tracking
        flush()
    }

    private func flush() {
        guard isOpen, let value = held else { return }
        held = nil
        deliver(value)
    }
}

 
 
@MainActor
final class ClashMacProductVisibilityObserver {
    private(set) var isVisible = true
    private var everHadWindow = false
    private var cancellables: Set<AnyCancellable> = []
    private let onChange: (Bool) -> Void
     
     
     
    var trace: ((String) -> Void)?
     
     
    private var occlusionReported: Set<ObjectIdentifier> = []

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSApplication.didBecomeActiveNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] note in
                    let window = note.object as? NSWindow
                    if let window {
                        if name == NSWindow.didChangeOcclusionStateNotification {
                            self?.occlusionReported.insert(ObjectIdentifier(window))
                        } else if name == NSWindow.willCloseNotification {
                            self?.occlusionReported.remove(ObjectIdentifier(window))
                        }
                    }
                    let closing = name == NSWindow.willCloseNotification ? window : nil
                    self?.recompute(closing: closing, trigger: name.rawValue)
                }
                .store(in: &cancellables)
        }
    }

     
     
    static func ordinaryWindows(
        _ windows: [NSWindow], closing: NSWindow? = nil
    ) -> [NSWindow] {
        windows.filter {
            $0 !== closing && $0.level == .normal && $0.canBecomeKey
        }
    }

     
    func state(of window: NSWindow) -> ClashMacProductVisibility.Window {
        ClashMacProductVisibility.Window(
            shown: window.isVisible,
            miniaturized: window.isMiniaturized,
            occluded: !window.occlusionState.contains(.visible),
            keyBeforeOcclusionReport: window.isKeyWindow
                && !occlusionReported.contains(ObjectIdentifier(window))
        )
    }

     
     
     
     
     
     
     
     
     
    func windowContentDidAppear() {
        recompute(trigger: "contentDidAppear", traceUnchanged: true, mayHide: false)
        DispatchQueue.main.async { [weak self] in
            self?.recompute(trigger: "contentDidAppear+1", traceUnchanged: true, mayHide: false)
        }
    }

    func recompute(
        closing: NSWindow? = nil,
        trigger: String = "",
        traceUnchanged: Bool = false,
        mayHide: Bool = true
    ) {
        let all = NSApplication.shared.windows
        let ordinary = Self.ordinaryWindows(all, closing: closing)
        let states = ordinary.map(state(of:))
        if states.contains(where: { $0.shown || $0.miniaturized }) {
            everHadWindow = true
        }
        let appHidden = NSApplication.shared.isHidden
        let read = ClashMacProductVisibility.isVisible(
            appHidden: appHidden, windows: states, everHadWindow: everHadWindow
        )
        let next = ClashMacProductVisibility.settle(
            current: isVisible, read: read, mayHide: mayHide, appHidden: appHidden
        )
        let changed = next != isVisible
        if changed || traceUnchanged, let trace {
            trace("window.visibility trigger=\(trigger) visible=\(isVisible)->\(next) read=\(read) appHidden=\(appHidden) active=\(NSApplication.shared.isActive) everHadWindow=\(everHadWindow) windows=[\(all.map { self.describe($0, in: all) }.joined(separator: " "))]")
        }
        guard changed else { return }
        isVisible = next
        onChange(next)
    }

     
     
    private func describe(_ w: NSWindow, in windows: [NSWindow]) -> String {
        let index = windows.firstIndex { $0 === w } ?? -1
        return "#\(index){\(type(of: w)) level=\(w.level.rawValue) canKey=\(w.canBecomeKey) shown=\(w.isVisible) key=\(w.isKeyWindow) main=\(w.isMainWindow) mini=\(w.isMiniaturized) occlusionVisible=\(w.occlusionState.contains(.visible)) occlusionReported=\(occlusionReported.contains(ObjectIdentifier(w))) title=\(w.title)}"
    }
}

 
 
 
 
struct ClashMacWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReadingView {
        let view = ReadingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ReadingView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class ReadingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

         
         
         
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            guard let window else { return }
            onWindow?(window)
             
             
             
             
            center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                               name: NSWindow.didBecomeKeyNotification, object: window)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            if let window { onWindow?(window) }
        }
    }
}
