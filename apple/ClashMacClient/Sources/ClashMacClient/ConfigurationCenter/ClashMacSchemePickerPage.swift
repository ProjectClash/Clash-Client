import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
public struct ClashMacSchemePickerRows: Equatable {
    public struct Row: Equatable, Identifiable {
         
        public let id: String
         
         
        public let detailID: String
        public let name: String
         
        public let detail: String
        public let isCurrent: Bool

        public init(id: String, detailID: String, name: String, detail: String, isCurrent: Bool) {
            self.id = id; self.detailID = detailID; self.name = name; self.detail = detail; self.isCurrent = isCurrent
        }
    }

     
    public struct Original: Equatable {
        public let isAvailable: Bool
        public let isCurrent: Bool
        public let reason: String?

        public init(isAvailable: Bool, isCurrent: Bool, reason: String?) {
            self.isAvailable = isAvailable; self.isCurrent = isCurrent; self.reason = reason
        }
    }

     
    public enum Choice: Hashable {
        case scheme(String)
        case original
    }

    public let builtin: [Row]
    public let mine: [Row]
    public let linked: [Row]
    public let files: [Row]
     
    public let original: Original?

    public init(builtin: [Row], mine: [Row], linked: [Row], files: [Row], original: Original?) {
        self.builtin = builtin; self.mine = mine; self.linked = linked; self.files = files; self.original = original
    }

     
    public var current: Choice? {
        if original?.isCurrent == true { return .original }
        return (builtin + mine + linked + files).first(where: \.isCurrent).map { .scheme($0.id) }
    }
}

 
 
 
 
 
 
 
public struct ClashMacSchemePickerPage: View {
    public typealias Choice = ClashMacSchemePickerRows.Choice

     
    static let title = "Rule Schemes of “%@”"
    static let changeNote = "Takes effect at once; custom rules and the override script are kept."
    static let addNote = "Added schemes are used for “%@” right away."

    let configurationName: String
     
    let snapshot: ClashMacSchemePickerRows?
    let busy: Bool
    let failure: String?
    let choose: @MainActor (Choice) -> Void
     
    let openDetails: @MainActor (String) -> AnyView
     
     
     
     
    let revealDetails: (@MainActor (String) -> Void)?
     
     
    let addCard: AnyView?
    let manageInLibrary: @MainActor () -> Void

    public init(configurationName: String, snapshot: ClashMacSchemePickerRows?, busy: Bool = false, failure: String? = nil,
                choose: @escaping @MainActor (Choice) -> Void,
                openDetails: @escaping @MainActor (String) -> AnyView,
                revealDetails: (@MainActor (String) -> Void)? = nil,
                addCard: AnyView? = nil,
                manageInLibrary: @escaping @MainActor () -> Void) {
        self.configurationName = configurationName; self.snapshot = snapshot; self.busy = busy; self.failure = failure
        self.choose = choose; self.openDetails = openDetails; self.revealDetails = revealDetails
        self.addCard = addCard; self.manageInLibrary = manageInLibrary
    }

     
    struct Group: Identifiable {
        let header: String
        let rows: [ClashMacSchemePickerRows.Row]
        var id: String { header }
    }

     
    static func groups(_ snapshot: ClashMacSchemePickerRows) -> [Group] {
        [Group(header: "Built-in Rule Schemes", rows: snapshot.builtin),
         Group(header: "My Rule Schemes", rows: snapshot.mine),
         Group(header: "From Profile URLs", rows: snapshot.linked),
         Group(header: "From Files", rows: snapshot.files)].filter { !$0.rows.isEmpty }
    }

     
    static func canChoose(_ choice: Choice, in snapshot: ClashMacSchemePickerRows) -> Bool {
        switch choice {
        case .scheme: return true
        case .original: return snapshot.original?.isAvailable == true
        }
    }

     
     
    static func pick(_ choice: Choice, in snapshot: ClashMacSchemePickerRows, choose: (Choice) -> Void) {
        guard choice != snapshot.current, canChoose(choice, in: snapshot) else { return }
        choose(choice)
    }

     
     
     
     
     
     
     
     
    @MainActor
    public static func write(_ choice: Choice, runsOriginal: Bool, isRecipe: Bool,
                             setOriginalUse: (Bool) -> Void, leaveOriginal: (String) -> Void, setScheme: (String) -> Void) {
        switch choice {
        case .original:
            setOriginalUse(true)
        case .scheme(let id):
            if runsOriginal, isRecipe { leaveOriginal(id) } else { setScheme(id) }
        }
    }

     
    static func originalLine(_ original: ClashMacSchemePickerRows.Original) -> ClashDisplayText {
        original.reason.map(ClashDisplayText.verbatim) ?? .copy("Runs the imported file as it is")
    }

    public var body: some View {
        Form {
            if let snapshot {
                ForEach(Self.groups(snapshot)) { group in
                    Section {
                        ForEach(group.rows) { row in schemeRow(row, in: snapshot) }
                    } header: {
                        Text(clash: .copy(group.header))
                    }
                }
                if let original = snapshot.original {
                    Section {
                        originalRow(original, in: snapshot)
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clash: .copy(Self.changeNote))
                        if let failure {
                            Text(verbatim: failure).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.scheme-picker.failure")
                        }
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
             
             
            if let addCard {
                addCard
                Section {
                    EmptyView()
                } footer: {
                    Text(clash: .format(Self.addNote, [configurationName]))
                        .accessibilityIdentifier("configuration-center.scheme-picker.add-note")
                }
            }
            Section {
                Button(action: manageInLibrary) {
                    Label { Text(clash: .copy("Manage Rule Schemes")) } icon: { Image(systemName: "books.vertical") }
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("configuration-center.scheme-picker.manage")
            }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .accessibilityIdentifier("configuration-center.scheme-picker")
    }

    private func schemeRow(_ row: ClashMacSchemePickerRows.Row, in snapshot: ClashMacSchemePickerRows) -> some View {
        HStack(spacing: 8) {
            Button {
                Self.pick(.scheme(row.id), in: snapshot, choose: choose)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").opacity(row.isCurrent ? 1 : 0)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(!row.isCurrent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.name)
                        Text(verbatim: row.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
            .accessibilityIdentifier("configuration-center.scheme-picker.row")
            SwiftUI.Group {
                if let revealDetails {
                    Button { revealDetails(row.detailID) } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                } else {
                    ClashRoutedViewLink(showsDisclosureIndicator: false) { openDetails(row.detailID) } label: { Image(systemName: "info.circle") }
                }
            }
            .help(Text(clash: .copy("View Details")))
            .accessibilityLabel(Text(clash: .copy("View Details")))
            .accessibilityIdentifier("configuration-center.scheme-picker.info")
        }
    }

    private func originalRow(_ original: ClashMacSchemePickerRows.Original,
                             in snapshot: ClashMacSchemePickerRows) -> some View {
        Button {
            Self.pick(.original, in: snapshot, choose: choose)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").opacity(original.isCurrent ? 1 : 0)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(!original.isCurrent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clash: .copy("Original Configuration (Rule Scheme)"))
                    Text(clash: Self.originalLine(original)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!original.isAvailable)
        .accessibilityAddTraits(original.isCurrent ? .isSelected : [])
         
        .accessibilityIdentifier("configuration-center.configuration.original")
    }
}

 
 
 
public struct ClashMacSchemePickerHost: View {
    @ObservedObject var library: ClashMacConfigurationLibraryModel
    let configurationName: String
     
    let rows: @MainActor (ConfigurationLibrarySnapshot) -> ClashMacSchemePickerRows?
    let choose: @MainActor (ClashMacSchemePickerRows.Choice) -> Void
    let openDetails: @MainActor (String) -> AnyView
    let revealDetails: (@MainActor (String) -> Void)?
    let addCard: AnyView?
    let manageInLibrary: @MainActor () -> Void

    public init(library: ClashMacConfigurationLibraryModel, configurationName: String,
                rows: @escaping @MainActor (ConfigurationLibrarySnapshot) -> ClashMacSchemePickerRows?,
                choose: @escaping @MainActor (ClashMacSchemePickerRows.Choice) -> Void,
                openDetails: @escaping @MainActor (String) -> AnyView,
                revealDetails: (@MainActor (String) -> Void)? = nil,
                addCard: AnyView? = nil,
                manageInLibrary: @escaping @MainActor () -> Void) {
        self.library = library; self.configurationName = configurationName; self.rows = rows; self.choose = choose
        self.openDetails = openDetails; self.revealDetails = revealDetails; self.addCard = addCard; self.manageInLibrary = manageInLibrary
    }

    public var body: some View {
        ClashMacSchemePickerPage(configurationName: configurationName, snapshot: rows(library.snapshot),
                                 choose: choose, openDetails: openDetails, revealDetails: revealDetails, addCard: addCard,
                                 manageInLibrary: manageInLibrary)
            .navigationTitle(Text(clash: .format(ClashMacSchemePickerPage.title, [configurationName])))
    }
}
