import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 

 

 
public struct ClashWidgetSlots {
     
    public var power: AnyView
     
     
    public var mode: (ClashWidgetMode, AnyView) -> AnyView
     
    public var member: (String, AnyView) -> AnyView
     
    public var refresh: (AnyView) -> AnyView
     
     
    public var accent: (AnyView) -> AnyView
     
     
     
    public var needsSetup: Bool

    public init(
        power: AnyView,
        mode: @escaping (ClashWidgetMode, AnyView) -> AnyView,
        member: @escaping (String, AnyView) -> AnyView,
        refresh: @escaping (AnyView) -> AnyView = { $0 },
        accent: @escaping (AnyView) -> AnyView = { $0 },
        needsSetup: Bool = false
    ) {
        self.power = power
        self.mode = mode
        self.member = member
        self.refresh = refresh
        self.accent = accent
        self.needsSetup = needsSetup
    }
}

 
public enum ClashWidgetSize {
    case small
    case medium
    case large
}

 

 
public struct ClashWidgetMainModel: Equatable {
    public let title: String
    public let node: String?
    public let phase: ClashWidgetPhase
    public let mode: ClashWidgetMode?
     
    public let since: Date?
     
    public let updatedAt: Date?
    public let down: String
    public let up: String
    public let connections: String
     
     
    public let cells: [ClashWidgetStatsModel.Cell]

     
     
    public var headline: String { node ?? title }
     
    public var subtitle: String? { node == nil ? nil : title }

     
     
     
     
     
     
    public init(
        snapshot: ClashWidgetSnapshot?, facts: ClashWidgetAppFacts?, now: Date, locale: Locale,
        configuredMode: ClashWidgetMode? = nil, countsWiredByDefault: Bool = false,
        throughputUnit: ClashThroughputUnit = .bits
    ) {
        let fresh = snapshot.flatMap { $0.isFresh(now: now) ? $0 : nil }
        title = snapshot?.profile ?? facts?.profile ?? ClashCopy.string("No Profile", locale: locale)
        phase = fresh?.phase ?? .disconnected
        let connected = fresh?.phase == .connected
         
         
         
         
         
        let firstGroup = facts?.firstGroup
        let resting = firstGroup.flatMap { facts?.selections[$0] }
            ?? (snapshot?.group?.name == firstGroup ? snapshot?.group?.now : nil)
        node = connected ? fresh?.egress : (firstGroup == nil ? nil : resting)
        mode = connected ? fresh?.mode : (configuredMode ?? facts?.mode)
        since = connected ? fresh?.startedAt : nil
        updatedAt = fresh?.at
         
         
         
         
         
        let idle = snapshot.map { $0.phase == .disconnected } ?? true
        let sum: (ClashWidgetBytes?) -> Int64? = { $0.map { $0.up + $0.down } }
        down = ClashWidgetFormat.rate(idle ? 0 : fresh?.downRate, unit: throughputUnit)
        up = ClashWidgetFormat.rate(idle ? 0 : fresh?.upRate, unit: throughputUnit)
        connections = ClashWidgetFormat.count(idle ? 0 : fresh?.connections?.opened, locale: locale)
         
         
        let wired = idle
            ? (facts?.countsWired ?? countsWiredByDefault)
            : (fresh?.cellular == nil && fresh?.wired != nil)
        cells = [
            .init(key: "Wi-Fi", symbol: "wifi", value: ClashWidgetFormat.bytes(idle ? 0 : sum(fresh?.wifi))),
            wired
                ? .init(key: "Wired", symbol: "cable.connector", value: ClashWidgetFormat.bytes(idle ? 0 : sum(fresh?.wired)))
                : .init(key: "Cellular", symbol: "cellularbars", value: ClashWidgetFormat.bytes(idle ? 0 : sum(fresh?.cellular))),
            .init(key: "Connections", symbol: "checkmark", value: connections),
            .init(key: "Download", symbol: "arrow.down", value: down),
            .init(key: "Upload", symbol: "arrow.up", value: up),
            .init(key: "Rejected", symbol: "xmark", value: ClashWidgetFormat.count(idle ? 0 : fresh?.rejectCount, locale: locale)),
        ]
    }


     
    public static func hintKey(needsSetup: Bool) -> String {
        needsSetup ? "Open Clash to finish setting up the VPN." : "Tap the power button to connect."
    }

     
    public var statusKey: String {
        switch phase {
        case .connected: return "Connected"
        case .connecting, .reasserting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Not Connected"
        }
    }
}

 
public struct ClashWidgetGroupModel: Equatable {
    public static let rowLimit = 4
    public static let wideRowLimit = 8
    public static let largeRowLimit = 12
     
     
    public static let maxMembers = ClashWidgetMailbox.groupMemberLimit

    public let header: String
    public let rows: [String]
    public let current: String?

    public init(snapshot: ClashWidgetSnapshot?, facts: ClashWidgetAppFacts?, group: String?, now: Date, rowLimit: Int = ClashWidgetGroupModel.rowLimit) {
        let wanted = group ?? facts?.firstGroup ?? snapshot?.group?.name ?? ""
        header = wanted
        let fresh = snapshot.flatMap { $0.isFresh(now: now) ? $0 : nil }
        if let slice = fresh?.group, slice.name == wanted {
            rows = Array(slice.all.prefix(rowLimit))
            current = slice.now
        } else if let members = facts?.members[wanted] {
             
             
            rows = Array(members.prefix(rowLimit))
            current = facts?.selections[wanted]
        } else {
            rows = []
            current = nil
        }
    }
}

 
public struct ClashWidgetStatsModel: Equatable {
    public struct Cell: Equatable {
        public let key: String
        public let symbol: String
        public let value: String
    }

    public let cells: [Cell]
    public let updatedAt: Date?
     
     
    public let hasData: Bool

    private func value(_ key: String) -> String { cells.first { $0.key == key }?.value ?? ClashWidgetFormat.unknown }
    public var wifi: String { value("Wi-Fi") }
    public var cellular: String { cells.first { $0.key == "Cellular" || $0.key == "Wired" }?.value ?? ClashWidgetFormat.unknown }
    public var proxy: String { value("Proxy") }
    public var direct: String { value("Direct") }
    public var reject: String { value("Rejected") }

    public init(
        snapshot: ClashWidgetSnapshot?, now: Date, locale: Locale, extended: Bool = false,
        throughputUnit: ClashThroughputUnit = .bits
    ) {
        let fresh = snapshot.flatMap { $0.isFresh(now: now) ? $0 : nil }
        let sum: (ClashWidgetBytes?) -> Int64? = { $0.map { $0.up + $0.down } }
         
         
         
        let totals: [Cell] = extended ? [
            Cell(key: "Download", symbol: "arrow.down", value: ClashWidgetFormat.rate(fresh?.downRate, unit: throughputUnit)),
            Cell(key: "Upload", symbol: "arrow.up", value: ClashWidgetFormat.rate(fresh?.upRate, unit: throughputUnit)),
        ] : []
         
         
         
        let second: Cell = fresh?.cellular == nil && fresh?.wired != nil
            ? Cell(key: "Wired", symbol: "cable.connector", value: ClashWidgetFormat.bytes(sum(fresh?.wired)))
            : Cell(key: "Cellular", symbol: "cellularbars", value: ClashWidgetFormat.bytes(sum(fresh?.cellular)))
        cells = totals + [
            Cell(key: "Wi-Fi", symbol: "wifi", value: ClashWidgetFormat.bytes(sum(fresh?.wifi))),
            second,
            Cell(key: "Proxy", symbol: "arrow.triangle.branch", value: ClashWidgetFormat.bytes(sum(fresh?.proxy))),
            Cell(key: "Direct", symbol: "arrow.right", value: ClashWidgetFormat.bytes(sum(fresh?.direct))),
            Cell(key: "Rejected", symbol: "nosign", value: ClashWidgetFormat.count(fresh?.rejectCount, locale: locale)),
            Cell(key: "Connections", symbol: "link",
                 value: ClashWidgetFormat.count(fresh?.connections?.opened, locale: locale)),
        ]
        updatedAt = fresh?.at
        hasData = fresh?.phase == .connected
    }
}

 

 
 
 
 
private struct ClashWidgetPlaceholder: View {
    let symbol: String
    let key: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(clash: .copy(key))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

 
 
 
private struct ClashWidgetFreshness: View {
    let at: Date?

    var body: some View {
        if let at {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text(at, style: .time)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

 
 
private struct ClashWidgetModeRow: View {
    let current: ClashWidgetMode?
    let slots: ClashWidgetSlots

    var body: some View {
         
         
         
         
        HStack(alignment: .top, spacing: 0) {
            ForEach(ClashWidgetMode.allCases, id: \.rawValue) { mode in
                let isCurrent = mode == current
                if mode != ClashWidgetMode.allCases.first {
                    Spacer(minLength: 4).frame(maxWidth: 20)
                }
                slots.mode(mode, AnyView(
                    VStack(spacing: 1) {
                        Text(clash: .copy(ClashWidgetFormat.modeKey(mode)))
                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                        slots.accent(AnyView(
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: 7))
                                 
                                .foregroundStyle(.tint)
                                .opacity(isCurrent ? 1 : 0)
                        ))
                    }
                    .fixedSize()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 5)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                ))
            }
        }
    }
}

private struct ClashWidgetStatCell: View {
    let cell: ClashWidgetStatsModel.Cell
     
     
     
     
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 2 : 1) {
            HStack(spacing: 4) {
                Image(systemName: cell.symbol)
                Text(clash: .copy(cell.key))
            }
            .font(large ? .caption : .caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Text(clash: .verbatim(cell.value))
                .font((large ? Font.title3 : Font.subheadline).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(clash: .copy(cell.key)))
        .accessibilityValue(Text(clash: .verbatim(cell.value)))
    }
}

 

public struct ClashWidgetMainView: View {
    private let model: ClashWidgetMainModel
    private let stats: ClashWidgetStatsModel
    private let size: ClashWidgetSize
    private let slots: ClashWidgetSlots
     
     
    private let notice: String?

    public init(
        snapshot: ClashWidgetSnapshot?, facts: ClashWidgetAppFacts?, now: Date, locale: Locale,
        size: ClashWidgetSize, slots: ClashWidgetSlots, configuredMode: ClashWidgetMode? = nil,
        countsWiredByDefault: Bool = false, throughputUnit: ClashThroughputUnit = .bits,
        notice: String? = nil
    ) {
        self.notice = notice
        model = ClashWidgetMainModel(
            snapshot: snapshot, facts: facts, now: now, locale: locale,
            configuredMode: configuredMode, countsWiredByDefault: countsWiredByDefault,
            throughputUnit: throughputUnit
        )
        stats = ClashWidgetStatsModel(
            snapshot: snapshot, now: now, locale: locale, extended: true, throughputUnit: throughputUnit
        )
        self.size = size
        self.slots = slots
    }

    public var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

     
     
    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                ClashRegionalFlag.label(model.headline, pointSize: 17, relativeTo: .headline)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                 
                 
                if size != .small { refresh }
            }
            if let notice {
                 
                 
                Text(clash: .copy(notice))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(size == .small ? 4 : 2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                secondLine
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

     
     
    private var refresh: some View {
        slots.refresh(AnyView(
            Image(systemName: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                 
                 
                .frame(width: 24, height: 24, alignment: size == .small ? .leading : .center)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(clash: .copy("Refresh")))
        ))
    }

    @ViewBuilder
    private var secondLine: some View {
        switch model.phase {
        case .connecting, .reasserting, .disconnecting:
            Text(clash: .copy(model.statusKey))
        case .connected, .disconnected:
            if slots.needsSetup {
                Text(clash: .copy(ClashWidgetMainModel.hintKey(needsSetup: true)))
            } else if let subtitle = model.subtitle {
                ClashRegionalFlag.label(subtitle, pointSize: 12, relativeTo: .caption)
            } else {
                Text(clash: .copy(model.statusKey))
            }
        }
    }

     
     
     
     
     
     
    private static let numberRowHeight: CGFloat = 16
    private static let numberRowSpacing: CGFloat = 6

    private func number(_ cell: ClashWidgetStatsModel.Cell) -> some View {
        HStack(spacing: 6) {
            Image(systemName: cell.symbol)
                .font(.caption.weight(.medium))
                .frame(width: 15)
            Text(clash: .verbatim(cell.value))
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .frame(height: Self.numberRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(clash: .copy(cell.key)))
        .accessibilityValue(Text(clash: .verbatim(cell.value)))
    }

    private func numberColumn(_ cells: [ClashWidgetStatsModel.Cell]) -> some View {
        VStack(alignment: .leading, spacing: Self.numberRowSpacing) {
            ForEach(cells, id: \.key) { number($0) }
        }
    }

    private var hairlines: some View {
        VStack(spacing: Self.numberRowSpacing) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: 11)
                    .frame(height: Self.numberRowHeight)
            }
        }
    }

     
    private var numbers: some View {
        let c = model.cells
        return HStack(alignment: .top, spacing: 7) {
            numberColumn([c[0], c[3]])
            hairlines
            numberColumn([c[1], c[4]])
            hairlines
            numberColumn([c[2], c[5]])
            Spacer(minLength: 0)
        }
    }

     
     
     
     
    private func speedLine(_ font: Font) -> some View {
        HStack(spacing: 8) {
            ForEach([model.cells[3], model.cells[4]], id: \.key) { cell in
                HStack(spacing: 3) {
                    Image(systemName: cell.symbol).font(font.weight(.medium))
                    Text(clash: .verbatim(cell.value)).font(font).monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(clash: .copy(cell.key)))
                .accessibilityValue(Text(clash: .verbatim(cell.value)))
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private var smallSpeeds: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            ViewThatFits(in: .horizontal) {
                speedLine(.caption2)
                speedLine(.system(size: 9))
                Color.clear.frame(width: 0, height: 0)
            }
        } else {
            speedLine(.caption2).minimumScaleFactor(0.8)
        }
    }

     
    private var foot: some View {
        HStack(alignment: .center, spacing: 8) {
             
             
            ClashWidgetModeRow(current: model.mode, slots: slots)
                .padding(.leading, -5)
            Spacer(minLength: 0)
            slots.power
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Spacer(minLength: 4)
            numbers
            Spacer(minLength: 4)
            foot
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

     
     
     
    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            head
            VStack(spacing: 0) {
                ForEach(Array(stride(from: 0, to: largeCells.count, by: 2)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(largeCells[start..<min(start + 2, largeCells.count)], id: \.key) { cell in
                            ClashWidgetStatCell(cell: cell, large: true)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            foot
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

     
     
    private var largeCells: [ClashWidgetStatsModel.Cell] {
        let extra = model.phase == .connected
            ? stats.cells.filter { $0.key == "Proxy" || $0.key == "Direct" }
            : [
                .init(key: "Proxy", symbol: "arrow.triangle.branch", value: model.cells[0].value),
                .init(key: "Direct", symbol: "arrow.right", value: model.cells[0].value),
            ]
         
         
        let c = model.cells
        return [c[0], c[1], c[3], c[4], c[2], c[5]] + extra
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Spacer(minLength: 4)
            smallSpeeds
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 4) {
                refresh
                Spacer(minLength: 0)
                slots.power
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

 

public struct ClashWidgetGroupView: View {
    private let model: ClashWidgetGroupModel
    private let size: ClashWidgetSize
    private let slots: ClashWidgetSlots

    public init(snapshot: ClashWidgetSnapshot?, facts: ClashWidgetAppFacts?, group: String?, now: Date, size: ClashWidgetSize, slots: ClashWidgetSlots) {
        let limit: Int
        switch size {
        case .small: limit = ClashWidgetGroupModel.rowLimit
        case .medium: limit = ClashWidgetGroupModel.wideRowLimit
        case .large: limit = ClashWidgetGroupModel.largeRowLimit
        }
        model = ClashWidgetGroupModel(snapshot: snapshot, facts: facts, group: group, now: now, rowLimit: limit)
        self.size = size
        self.slots = slots
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClashWidgetGroupHeader(name: model.header)
            if model.rows.isEmpty {
                ClashWidgetPlaceholder(symbol: "network", key: "Connect to see the nodes.")
            } else if size == .medium, model.rows.count > ClashWidgetGroupModel.rowLimit {
                HStack(alignment: .top, spacing: 12) {
                    column(Array(model.rows.prefix(ClashWidgetGroupModel.rowLimit)))
                    column(Array(model.rows.dropFirst(ClashWidgetGroupModel.rowLimit)))
                }
            } else {
                column(model.rows)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ rows: [String]) -> some View {
        ClashWidgetGroupRows(model: model, rows: rows, slots: slots)
    }
}

private struct ClashWidgetGroupHeader: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "network")
            ClashRegionalFlag.label(name, pointSize: 12, relativeTo: .caption)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

 
private struct ClashWidgetGroupRows: View {
    let model: ClashWidgetGroupModel
    var rows: [String]?
    let slots: ClashWidgetSlots

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows ?? model.rows, id: \.self) { name in
                slots.member(name, AnyView(row(name)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ name: String) -> some View {
        HStack(spacing: 6) {
            ClashRegionalFlag.label(name, pointSize: 15, relativeTo: .subheadline)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if name == model.current {
                slots.accent(AnyView(
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                ))
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

 

public struct ClashWidgetStatsView: View {
    private let model: ClashWidgetStatsModel
    private let size: ClashWidgetSize

    public init(
        snapshot: ClashWidgetSnapshot?, now: Date, locale: Locale, size: ClashWidgetSize,
        throughputUnit: ClashThroughputUnit = .bits
    ) {
        model = ClashWidgetStatsModel(
            snapshot: snapshot, now: now, locale: locale, extended: size == .large, throughputUnit: throughputUnit
        )
        self.size = size
    }

    public var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: size == .medium ? 3 : 2)
        VStack(alignment: .leading, spacing: 8) {
            if model.hasData {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(model.cells, id: \.key) { cell in
                        ClashWidgetStatCell(cell: cell)
                    }
                }
                Spacer(minLength: 0)
                ClashWidgetFreshness(at: model.updatedAt)
            } else {
                ClashWidgetPlaceholder(symbol: "chart.bar.xaxis", key: "Connect to see traffic.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
