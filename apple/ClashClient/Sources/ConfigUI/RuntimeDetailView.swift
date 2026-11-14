import Clash
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum RuntimeMemoryPresentation {
    struct Row: Equatable {
        let title: String
        let value: ClashDisplayText
    }

     
     
     
     
    static func headline(
        footprintBytes: Int64?,
        residentBytes: Int64,
        isLive: Bool = true
    ) -> Row {
        let bytes = (footprintBytes ?? -1) > 0 ? footprintBytes! : residentBytes
        return Row(
            title: "Memory used",
            value: .verbatim(isLive && bytes > 0 ? megabytes(Double(bytes)) : "—")
        )
    }

     
     
     
    static func details(
        footprintBytes: Int64?,
        goHeapBytes: UInt64?,
        residentBytes: Int64,
        isLive: Bool = true
    ) -> [Row] {
        guard isLive else { return [] }
        var rows: [Row] = []
         
         
        if let goHeapBytes, goHeapBytes > 0 {
            rows.append(Row(
                title: "Go heap",
                value: .verbatim(megabytes(Double(goHeapBytes)))
            ))
        }
        if (footprintBytes ?? -1) > 0, residentBytes > 0 {
            rows.append(Row(
                title: "Resident memory",
                value: .verbatim(megabytes(Double(residentBytes)))
            ))
        }
        return rows
    }

    private static func megabytes(_ bytes: Double) -> String {
        String(format: "%.1f MB", bytes / 1_048_576)
    }
}

 
 
 
enum RuntimePathPresentation {
    static let title: ClashDisplayText = .copy("Current network supports")

    static func supports(v4: Bool, v6: Bool) -> ClashDisplayText {
        switch (v4, v6) {
        case (true, true): return .copy("IPv4 and IPv6")
        case (true, false): return .copy("IPv4 only")
        case (false, true): return .copy("IPv6 only")
        case (false, false): return .copy("No network")
        }
    }
}

 
 
 
struct RuntimeDetailView: View {
    @ObservedObject var command: ClashCommandClient
    @ObservedObject private var appCrashReport = AppGoCrashReportStore.shared
     
     
    @State private var memoryBytes: Int64
    let usesRegularDetailLayout: Bool
     
    var restart: (() -> Void)?

    init(command: ClashCommandClient, usesRegularDetailLayout: Bool, restart: (() -> Void)? = nil) {
        self.command = command
        self.usesRegularDetailLayout = usesRegularDetailLayout
        self.restart = restart
        _memoryBytes = State(initialValue: command.memoryBytes)
    }

    @State private var asksAboutRestart = false
    @State private var crashReportToShare: String?

    private func memoryRow(_ row: RuntimeMemoryPresentation.Row) -> some View {
        RuntimeMetricRow(
            title: .copy(row.title),
            value: row.value,
            symbol: .memorychip)
    }

    var body: some View {
         
         
        content.onReceive(command.$memoryBytes) { bytes in
            if bytes != memoryBytes { memoryBytes = bytes }
        }
    }

    private var content: some View {
        Form {
            Section {
                RuntimeMetricRow(
                    title: "Version",
                    value: .verbatim(
                        command.runtimeDiagnostics?.lowMemoryBuild == true
                        ? "\(ClashVersion()) · low-memory"
                        : ClashVersion()
                    ),
                    symbol: .cpu)
                memoryRow(RuntimeMemoryPresentation.headline(
                    footprintBytes: command.runtimeDiagnostics?
                        .extensionMemoryFootprintBytes,
                    residentBytes: memoryBytes,
                    isLive: command.isConnected
                ))
                let details = RuntimeMemoryPresentation.details(
                    footprintBytes: command.runtimeDiagnostics?
                        .extensionMemoryFootprintBytes,
                    goHeapBytes: command.runtimeDiagnostics?.goHeapInuseBytes,
                    residentBytes: memoryBytes,
                    isLive: command.isConnected
                )
                if !details.isEmpty {
                    DisclosureGroup {
                        ForEach(details, id: \.title) { row in
                            memoryRow(row)
                        }
                    } label: {
                        Text(clash: .copy("Technical details"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                     
                     
                     
                     
                    .clashRowDisclosure()
                    .accessibilityIdentifier("runtime.memory.details")
                }

                if let restart,
                   CoreRestartPolicy.isOffered(isConnected: command.isConnected) {
                    Button(role: .destructive) {
                        asksAboutRestart = true
                    } label: {
                        Label("Restart Core", systemImage: ClashSymbol.arrowClockwise.rawValue)
                    }
                    .accessibilityIdentifier("runtime.restart")
                    .confirmationDialog(
                        "Restart Core?",
                        isPresented: $asksAboutRestart,
                        titleVisibility: .visible
                    ) {
                        Button("Restart", role: .destructive, action: restart)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(clash: .copy(CoreRestartPolicy.confirmation))
                    }
                }
            } header: {
                Text(clash: .copy("Connection"))
            }

            if let d = command.runtimeDiagnostics {
                Section("Diagnostics") {
                    RuntimeMetricRow(
                        title: "Started",
                        value: .verbatim(
                            Date(timeIntervalSince1970: TimeInterval(d.startTimeUnix))
                            .formatted(date: .abbreviated, time: .standard)
                        ),
                        symbol: .clock)
                    RuntimeMetricRow(title: "Goroutines", value: .verbatim(String(d.goroutines)),
                                     symbol: .point3FilledConnectedTrianglepathDotted)
                    RuntimeMetricRow(
                        title: "In / Out / Connections",
                        value: .verbatim("\(d.inboundCount) / \(d.outboundCount) / \(d.connectionCount)"),
                        symbol: .arrowLeftArrowRight)
                    RuntimeMetricRow(
                        title: "Apple routes v4 / v6",
                        value: .verbatim("\(d.appleIPv4IncludedRouteCount) / \(d.appleIPv6IncludedRouteCount)"),
                        symbol: .arrowTriangleBranch)
                    RuntimeMetricRow(
                        title: RuntimePathPresentation.title,
                        value: RuntimePathPresentation.supports(v4: d.physicalPathSupportsIPv4, v6: d.physicalPathSupportsIPv6),
                        symbol: .network)
                    RuntimeMetricRow(
                        title: "NAT64 applied / failed",
                        value: .verbatim("\(d.nat64SynthesisApplied) / \(d.nat64SynthesisFailures)"),
                        symbol: .arrowTriangleSwap)
                    if d.extensionLogBatchesDropped > 0 {
                        RuntimeMetricRow(
                            title: "Log batches dropped",
                            value: .verbatim(String(d.extensionLogBatchesDropped)),
                            symbol: .exclamationmarkTriangle)
                    }
                }
            } else {
                Section {
                    ClashStatusMessage(
                        text: .copy("Connect Clash to read core diagnostics."),
                        kind: .information
                    )
                }
            }

            if let report = command.previousGoCrashReport {
                Section("Previous run ended unexpectedly") {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ClashStatusMessage(
                            text: "The core stopped on an internal error during its last run.",
                            kind: .error
                        )
                         
                         
                         
                        if #available(iOS 16.0, *) {
                            ShareLink(item: report) {
                                Label(
                                    "Export Technical Details",
                                    systemImage: ClashSymbol.squareAndArrowUp.name
                                )
                            }
                            .accessibilityIdentifier("runtime.crash-report.export")
                        } else {
                            Button {
                                crashReportToShare = report
                            } label: {
                                Label(
                                    "Export Technical Details",
                                    systemImage: ClashSymbol.squareAndArrowUp.name
                                )
                            }
                            .accessibilityIdentifier("runtime.crash-report.export")
                        }
                    }
                }
            }

             
             
            if let report = appCrashReport.content {
                Section("The App's last run") {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ClashStatusMessage(
                            text: report.appQuit
                                ? .copy("The App quit on an internal core error last time.")
                                : .format("The App caught %@ internal core errors and kept running.",
                                          [String(report.recoveredPanics)]),
                            kind: report.appQuit ? .error : .warning
                        )
                        if #available(iOS 16.0, *) {
                            ShareLink(item: report.text) {
                                Label("Export Technical Details", systemImage: ClashSymbol.squareAndArrowUp.name)
                            }
                            .accessibilityIdentifier("runtime.app-crash-report.export")
                        } else {
                            Button {
                                crashReportToShare = report.text
                            } label: {
                                Label("Export Technical Details", systemImage: ClashSymbol.squareAndArrowUp.name)
                            }
                            .accessibilityIdentifier("runtime.app-crash-report.export")
                        }
                    }
                }
            }

             
             
             
             
            if let diagnostics = command.runtimeDiagnostics,
               let triggers = diagnostics.memoryThresholdTriggerCount {
                let predicted = diagnostics.memoryThresholdPredictedCount ?? 0
                let shed = diagnostics.memoryThresholdShedCount ?? 0
                Section("Memory pressure") {
                    if triggers == 0, predicted == 0, shed == 0 {
                        RuntimeMetricRow(
                            title: "Pressure",
                            value: "None recorded",
                            symbol: .memorychip)
                    } else {
                        RuntimeMetricRow(
                            title: "State",
                            value: .verbatim(diagnostics.memoryThresholdState ?? "—"),
                            symbol: .memorychip)
                        RuntimeMetricRow(
                            title: "Triggers",
                            value: .verbatim("\(triggers)"),
                            symbol: .memorychip)
                        RuntimeMetricRow(
                            title: "Predicted",
                            value: .verbatim("\(predicted)"),
                            symbol: .memorychip)
                        RuntimeMetricRow(
                            title: "Connections shed",
                            value: .verbatim(
                                diagnostics.memoryThresholdShedEnabled == true
                                ? "\(shed)"
                                : "Reporting only"
                            ),
                            symbol: .memorychip)
                    }
                }
            }

            if let evidence = command.previousOOMEvidence {
                Section("Previous memory pressure") {
                    VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                        ClashStatusMessage(text: .copy(evidence.interpretation), kind: .warning)
                        Text(Date(timeIntervalSince1970: TimeInterval(evidence.recordedAtUnix))
                            .formatted(date: .abbreviated, time: .standard))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
         
         
         
#if !os(macOS)
        .sheet(isPresented: Binding(
            get: { crashReportToShare != nil },
            set: { if !$0 { crashReportToShare = nil } }
        )) {
            Group {
                if let crashReportToShare {
                    LogShareSheet(activityItems: [crashReportToShare])
                }
            }
            .clashModalPresentation(.page)
        }
#endif
        .clashPageTitle("Core Runtime")
    }
}
