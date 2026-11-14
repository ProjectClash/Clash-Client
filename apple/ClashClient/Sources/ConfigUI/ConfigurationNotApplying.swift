import Foundation
import ClashClientKit
import ClashClientUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

 
 
 
 
 
 

 
struct ConfigurationNotApplyingItem: Identifiable, Equatable {
    let id: String
    let title: String
    let decision: ConfigurationPlatformDecision?
    var field: ConfigurationField? = nil
}

extension ConfigurationSectionLayout {
     
    var notApplying: [ConfigurationNotApplyingItem] {
        platformDecided.map { .init(id: $0.id, title: $0.path.joined(separator: "."), decision: $0.field?.platformDecision, field: $0.field) }
    }
}

extension ProxyNodeCatalogLayout {
     
    var notApplying: [ConfigurationNotApplyingItem] {
        platformDecided.map { .init(id: $0.id, title: $0.path.joined(separator: "."), decision: $0.field?.platformDecision, field: $0.field) }
    }

     
     
     
     
     
     
     
     
     
     
     
    func splittingOffThePlatformsRows(in entry: OrderedJSON? = nil) -> ProxyNodeCatalogLayout {
        var platform: [Row] = []
        let kept = groups.compactMap { group -> Group? in
            let rows = group.rows.filter { row in
                guard let decision = row.field?.platformDecision, decision.overridesTheFile else { return true }
                if let entry, !decision.applies(to: entry.node(at: Array(row.path.dropLast())) ?? .object([])) {
                    return true
                }
                platform.append(row)
                return false
            }
            return rows.isEmpty ? nil : Group(id: group.id, title: group.title, rows: rows, catalogPath: group.catalogPath)
        }
        return ProxyNodeCatalogLayout(groups: kept, platformDecided: platform)
    }
}

 
enum ConfigurationDevice {
    static var name: String {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
#else
        "Mac"
#endif
    }
}

 
struct ConfigurationNotApplyingLabel: View {
    let count: Int
    @Environment(\.locale) private var locale

    var body: some View {
        Text(clash: ConfigurationValueWords.notApplyingRow(count: count, device: ConfigurationDevice.name, locale: locale))
            .foregroundStyle(.secondary)
    }
}

 
 
 
 
 
struct ConfigurationSettingsNotApplyingView: View {
    let items: [ConfigurationNotApplyingItem]
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                         
                         
                        Text(verbatim: fieldCopy.title(for: item.field, key: item.title, locale: locale))
                        Text(clash: ConfigurationValueWords.categoryLine(for: item.decision, device: ConfigurationDevice.name))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let words = fieldCopy.platformWords(for: item.field, locale: locale) {
                            Text(verbatim: words).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("configuration-editor.not-applying.\(item.id)")
                }
            } footer: {
                Text(clash: ConfigurationValueWords.notApplyingFooter(device: ConfigurationDevice.name))
            }
        }
        .navigationTitle(Text(clash: ConfigurationValueWords.notApplyingTitle))
    }
}
