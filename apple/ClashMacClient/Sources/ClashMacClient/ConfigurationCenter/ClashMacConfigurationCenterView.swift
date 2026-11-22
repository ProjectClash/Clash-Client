import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
public enum ClashMacConfigurationCenterSegment: Int, CaseIterable, Identifiable, Sendable {
    case configurations, nodes, rules, scripts

    public var id: Int { rawValue }

     
    public var title: String {
        switch self {
        case .configurations: "Configuration Library"
        case .nodes: "Node Library"
        case .rules: "Rule Library"
        case .scripts: "Override Library"
        }
    }

    public var identifier: String {
        switch self {
        case .configurations: "configurations"
        case .nodes: "nodes"
        case .rules: "rules"
        case .scripts: "scripts"
        }
    }
}

 
 
 
 
 
public struct ClashMacConfigurationCenterView<Configurations: View, Nodes: View, Rules: View, Scripts: View>: View {
    @Binding private var segment: ClashMacConfigurationCenterSegment
    private let configurations: () -> Configurations
    private let nodes: () -> Nodes
    private let rules: () -> Rules
    private let scripts: () -> Scripts

    public init(
        segment: Binding<ClashMacConfigurationCenterSegment>,
        @ViewBuilder configurations: @escaping () -> Configurations,
        @ViewBuilder nodes: @escaping () -> Nodes,
        @ViewBuilder rules: @escaping () -> Rules,
        @ViewBuilder scripts: @escaping () -> Scripts
    ) {
        _segment = segment
        self.configurations = configurations
        self.nodes = nodes
        self.rules = rules
        self.scripts = scripts
    }

    public var body: some View {
        Group {
            switch segment {
            case .configurations: configurations()
            case .nodes: nodes()
            case .rules: rules()
            case .scripts: scripts()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(selection: $segment) {
                    ForEach(ClashMacConfigurationCenterSegment.allCases) { item in
                        Text(clash: .copy(item.title)).tag(item)
                    }
                } label: {
                    Text(clash: .copy("Profile Center"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("configuration-center.segment")
            }
        }
    }
}
