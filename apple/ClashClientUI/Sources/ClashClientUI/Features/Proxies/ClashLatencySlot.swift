import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
struct ClashLatencySlotFace: Equatable {
     
    let face: ClashProxyLatencyState
    let isTesting: Bool

     
     
    init(shown: ClashProxyLatencyState, settled: ClashProxyLatencyState?) {
        if shown == .testing {
            face = settled.flatMap { $0 == .testing ? nil : $0 } ?? .untested
            isTesting = true
        } else {
            face = shown
            isTesting = false
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    static func liveReading(testingPulse batch: ClashLatencyPulse, key: String, tapped: Bool) -> ClashProxyLatencyState? {
        if let reading = ClashLatencyKey.reading(key, in: batch.results),
           !tapped || ClashLatencyKey.isNamed(key, in: batch.landed) {
            return reading
        }
        return ClashLatencyKey.isNamed(key, in: batch.testing) ? .testing : nil
    }

     
     
     
     
    static func settled(
        writing value: ClashProxyLatencyState?,
        over shown: ClashProxyLatencyState,
        kept: ClashProxyLatencyState?
    ) -> ClashProxyLatencyState? {
        value == .testing && shown != .testing ? shown : kept
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashLatencySpinner: View {
     
     
    var isSpinning = true
    var diameter: CGFloat = 11

     
    static let period: TimeInterval = 0.9

    static func angle(at date: Date) -> Angle {
        .degrees(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360)
    }

    var body: some View {
         
         
         
         
         
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isSpinning)) { context in
            Circle()
                .trim(from: 0.12, to: 0.84)
                .stroke(style: StrokeStyle(lineWidth: max(1.5, diameter / 7), lineCap: .round))
                .foregroundStyle(.secondary)
                .rotationEffect(Self.angle(at: context.date))
        }
        .id(isSpinning)
        .frame(width: diameter, height: diameter)
        .opacity(isSpinning ? 1 : 0)
        .accessibilityLabel("Testing latency")
        .accessibilityHidden(!isSpinning)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashLatencyGroupFace: Equatable {
    var live: ClashProxyGroupHeaderRow.LiveLatency?
    var isTesting: Bool?

     
     
     
     
    static func reading(
        _ batch: ClashLatencyPulse, group: ClashProxyGroupSnapshot,
        memberKeys: () -> Set<String>, kept: Self
    ) -> Self {
        var next = kept
        if batch.isTesting, !batch.testing.isEmpty {
            let keys = memberKeys()
            next.isTesting = batch.testing.contains { keys.contains($0) }
        } else {
            next.isTesting = false
        }
        guard !group.isEmpty, let terminal = batch.groupTerminals[group.name] else {
            if !batch.isTesting { next.live = nil }
            return next
        }
         
        let key = batch.groupTerminalKeys[group.name] ?? terminal
        if let landed = ClashLatencyKey.reading(key, in: batch.results) {
            next.live = .init(terminal: terminal, state: landed)
        } else if ClashLatencyKey.isTesting(key, in: batch.testing) || batch.testing.contains(terminal) {
            next.live = .init(terminal: terminal, state: .testing)
        } else if !batch.isTesting {
             
             
             
            next.live = .init(terminal: terminal, state: .untested)
        }
        return next
    }

    static func memberKeys(of group: ClashProxyGroupSnapshot) -> Set<String> {
        var keys = Set<String>()
        for member in group.members {
            keys.insert(member.latencyKey)
            if let node = ClashLatencyKey.nodeName(ofRecordKey: member.latencyKey) { keys.insert(node) }
        }
        return keys
    }

    func latency(of group: ClashProxyGroupSnapshot, initial: ClashProxyLatencyState) -> ClashProxyLatencyState {
        ClashProxyGroupHeaderRow.displayedLatency(
            live: live, route: group.resolvedRuntimeRoute ?? group.runtimeSelection, initial: initial)
    }
}

 
 
 
final class ClashLatencyMemberKeys {
    private var members: [ClashProxyMemberSnapshot]?
    private var keys: Set<String> = []

    func of(_ group: ClashProxyGroupSnapshot) -> Set<String> {
        if members != group.members {
            members = group.members
            keys = ClashLatencyGroupFace.memberKeys(of: group)
        }
        return keys
    }
}
