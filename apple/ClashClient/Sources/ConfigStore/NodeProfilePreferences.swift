import Foundation

struct ActiveNodeProfileState: Equatable {
    let profileID: String
    let selectedMap: [String: String]
    let currentGroupName: String?
    let unfoldedGroups: Set<String>?
     
    var globalPickedByReader = false
}

 
 
 
 
final class NodeProfilePreferencesStore {
    private let profileStore: ProfileStore
    private let activeProfileID: () -> String?
     
     
     
    let latencyResults: NodeLatencyResultStore?

    init(
        profileStore: ProfileStore,
        latencyResults: NodeLatencyResultStore? = nil,
        activeProfileID: @escaping () -> String?
    ) {
        self.profileStore = profileStore
        self.latencyResults = latencyResults
        self.activeProfileID = activeProfileID
    }

     
    func activeProfileKey() -> String? {
        activeProfileID()
    }

    static func live() -> NodeProfilePreferencesStore? {
        guard let container = ClashAppIdentifiers.appGroupContainer else { return nil }
        let working = container.appendingPathComponent("working")
        let profiles = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        return NodeProfilePreferencesStore(
            profileStore: profiles,
            latencyResults: NodeLatencyResultStore.live()
        ) {
            if let configStore = try? ConfigResourceStore(containerURL: container),
               let activeProfileID = (try? configStore.activeIdentity())?.profileID {
                return activeProfileID
            }
            let stored = profiles.load()
            return ProfileCenterPolicy.automaticSelectionID(
                profiles: stored,
                activeProfileID: nil
            )
        }
    }

    func load() -> ActiveNodeProfileState? {
        guard let id = activeProfileID(),
              let profile = profileStore.load().first(where: { $0.id == id }) else { return nil }
        return ActiveNodeProfileState(
            profileID: id,
            selectedMap: profile.selectedMap,
            currentGroupName: profile.currentGroupName,
            unfoldedGroups: profile.unfoldedGroups,
            globalPickedByReader: profile.globalPickedByReader ?? false
        )
    }

     
    func saveSelection(group: String, proxy: String) {
        updateActive { profile in
            profile.noteReaderPick(group: group, member: proxy)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func clearSelection(group: String) -> Bool {
        updateActive { profile in
            profile.selectedMap.removeValue(forKey: group)
            if group == Self.globalGroupName { profile.globalPickedByReader = nil }
        }
    }

     
     
    static let globalGroupName = #"GLOBAL"#

     
     
     
     
     
    @discardableResult
    func restoreSelection(group: String, proxy: String) -> Bool {
        updateActive { profile in
            profile.selectedMap[group] = proxy
        }
    }

    func savePresentation(currentGroup: String?, unfoldedGroups: Set<String>) {
        updateActive { profile in
            profile.currentGroupName = currentGroup
            profile.unfoldedGroups = unfoldedGroups
        }
    }

    @discardableResult
    private func updateActive(_ mutate: (inout Profile) -> Void) -> Bool {
        guard let id = activeProfileID() else { return false }
        do {
             
             
            guard try profileStore.updateIfPresent(id: id, mutate) != nil else { return false }
             
             
             
             
             
             
            NotificationCenter.default.post(
                name: .clashProfileSelectionDidChange,
                object: nil,
                userInfo: ["profileID": id]
            )
            return true
        } catch {
            return false
        }
    }
}

extension Notification.Name {
     
     
     
    static let clashProfileSelectionDidChange = Notification.Name("ClashProfileSelectionDidChange")
}

extension Profile {
     
     
     
     
     
     
    mutating func noteReaderPick(group: String, member: String) {
        selectedMap[group] = member
        if GlobalProxySelectionPolicy.remembers(group: group) {
            currentGroupName = group
            globalPickedByReader = nil
        } else {
            globalPickedByReader = true
        }
    }
}
