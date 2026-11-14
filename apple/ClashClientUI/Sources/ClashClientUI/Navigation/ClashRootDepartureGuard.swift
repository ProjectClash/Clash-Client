import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashDeparturePageKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var clashDeparturePage: UUID? {
        get { self[ClashDeparturePageKey.self] }
        set { self[ClashDeparturePageKey.self] = newValue }
    }
}

extension View {
     
    func clashDeparturePage() -> some View {
        modifier(ClashDeparturePageModifier())
    }
}

private struct ClashDeparturePageModifier: ViewModifier {
    @State private var page = UUID()

    func body(content: Content) -> some View {
        content.environment(\.clashDeparturePage, page)
    }
}

 
 
 
 
 
 
 
 
 
 
public enum ClashDepartureSaveAnswer: Equatable {
    case saved
    case refused(ClashDisplayText?)

     
    public static let incomplete: ClashDisplayText = .copy("Finish filling in this page before saving it.")

     
     
    static func bare(_ saved: Bool) -> ClashDepartureSaveAnswer {
        saved ? .saved : .refused(nil)
    }
}

 
 
 
@MainActor
final class ClashRootDepartureGuard: ObservableObject {
    private struct Registration {
         
         
         
         
         
         
         
        let id: UUID
        let isDirty: Bool
         
         
         
        let currentlyDirty: (() -> Bool)?
        let isBusy: Bool
         
        let page: UUID?
         
         
        let whySaveIsBlocked: (() -> ClashDisplayText?)?
        let save: (@escaping (ClashDepartureSaveAnswer) -> Void) -> Void
        let discard: () -> Void

        var isDirtyNow: Bool { currentlyDirty?() ?? isDirty }
    }

    @Published private(set) var isPromptPresented = false
    @Published private(set) var isBusy = false
     
     
     
     
     
    @Published private(set) var refusal: ClashDisplayText?
    private var refusalOwner: UUID?
     
     
     
    private var question = UUID()
     
     
     
     
     
     
     
    @Published private(set) var saveBlock: ClashDisplayText?

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var registrations: [Registration] = []
     
     
     
     
     
     
    private var answeringID: UUID?
    private var registration: Registration? {
        if let answeringID, let entry = registrations.last(where: { $0.id == answeringID }) { return entry }
        return registrations.last
    }
     
     
    var hasDirtyRegistration: Bool { registrations.last?.isDirtyNow == true }

     
     
     
     
     
    private var renderedDirty: Bool { registrations.last?.isDirty == true }
    private var pendingDeparture: (() -> Void)?
    private var isSaving = false

    func register(
        id: UUID,
        isDirty: Bool,
        isBusy: Bool,
        save: @escaping (@escaping (Bool) -> Void) -> Void,
        discard: @escaping () -> Void
    ) {
        register(
            id: id,
            isDirty: isDirty,
            currentlyDirty: nil,
            isBusy: isBusy,
            page: nil,
            whySaveIsBlocked: nil,
            saveAnswering: { answer in save { answer(.bare($0)) } },
            discard: discard
        )
    }

    func register(
        id: UUID,
        isDirty: Bool,
        currentlyDirty: (() -> Bool)?,
        isBusy: Bool,
        page: UUID?,
        whySaveIsBlocked: (() -> ClashDisplayText?)? = nil,
        saveAnswering save: @escaping (@escaping (ClashDepartureSaveAnswer) -> Void) -> Void,
        discard: @escaping () -> Void
    ) {
        let entry = Registration(
            id: id,
            isDirty: isDirty,
            currentlyDirty: currentlyDirty,
            isBusy: isBusy,
            page: page,
            whySaveIsBlocked: whySaveIsBlocked,
            save: save,
            discard: discard
        )
        let wasDirty = renderedDirty
        if let existing = registrations.firstIndex(where: { $0.id == id }) {
            registrations[existing] = entry
        } else {
            registrations.append(entry)
        }
        if wasDirty != renderedDirty {
            dirtyRegistrationDidChange?()
        }
        refreshBusyState()
    }

    private func refreshBusyState() {
         
         
         
         
         
         
        let next = isSaving || registration?.isBusy == true
        if isBusy != next { isBusy = next }
    }

     
     
     
     
     
     
     
     
     
     
    func unregister(id: UUID) {
        let wasDirty = renderedDirty
        registrations.removeAll { $0.id == id }
        if answeringID == id { answeringID = nil }
        if refusalOwner == id { refusal = nil; refusalOwner = nil }
        if waitingOwner == id { endQuestion() }
        refreshBusyState()
        if wasDirty != renderedDirty {
            dirtyRegistrationDidChange?()
        }
    }

     
     
     
     
     
    var dirtyRegistrationDidChange: (() -> Void)?

    func requestDeparture(_ departure: @escaping () -> Void) {
        guard let registration else {
            leave(departure, releasing: nil)
            return
        }
        guard !isBusy else { return }
        guard registration.isDirtyNow else {
            let answered = registration.id
             
             
             
             
             
             
            let oneStepBack = answeringID != nil
            answeringID = nil
             
             
             
             
             
             
             
            registrations.removeAll { $0.id == answered }
            refreshBusyState()
            leave(departure, releasing: oneStepBack ? [answered] : nil)
            return
        }
        pendingDeparture = departure
        saveBlock = registration.whySaveIsBlocked?()
         
         
        refusal = nil
        refusalOwner = nil
        endQuestion()
        isPromptPresented = true
    }

     
     
     
     
     
     
    func requestBack(from page: UUID?, _ departure: @escaping () -> Void) {
        guard let page, registrations.last != nil else {
            requestDeparture(departure)
            return
        }
        guard let mine = registrations.last(where: { $0.page == page }) else {
             
             
             
             
             
             
             
            endQuestion()
            departure()
            return
        }
         
         
        guard !isBusy else { return }
        answeringID = mine.id
        requestDeparture(departure)
    }

     
     
    static let afterAnAlertHasGone: TimeInterval = 0.4

     
     
     
     
     
     
     
    private func leave(_ departure: () -> Void, releasing released: [UUID]?) {
        if let owner = refusalOwner, released?.contains(owner) ?? true {
            refusal = nil
            refusalOwner = nil
        }
        if let owner = waitingOwner, released?.contains(owner) ?? true { endQuestion() }
        departure()
    }
     
     
     
    private var waitingOwner: UUID?

    private func endQuestion() {
        question = UUID()
        waitingOwner = nil
    }

     
    func acknowledgeRefusal() {
        refusal = nil
        refusalOwner = nil
    }

     
     
     
     
    @discardableResult
    private func releaseAnswered() -> [UUID]? {
        if let answeringID {
            registrations.removeAll { $0.id == answeringID }
            self.answeringID = nil
            return [answeringID]
        }
        registrations.removeAll()
        return nil
    }

    func saveAndLeave() {
        guard let registration, pendingDeparture != nil else { return }
         
        guard saveBlock == nil else { return }
        isPromptPresented = false
         
         
         
         
        isSaving = true
        refreshBusyState()
        let answering = registration.id
        let asked = question
        registration.save { [weak self] answer in
            guard let self else { return }
            isSaving = false
            guard answer == .saved else {
                pendingDeparture = nil
                answeringID = nil
                refreshBusyState()
                 
                 
                 
                if case .refused(let reason?) = answer {
                     
                     
                     
                     
                     
                     
                    waitingOwner = answering
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterAnAlertHasGone) { [weak self] in
                        guard let self, question == asked else { return }
                        waitingOwner = nil
                        guard registrations.contains(where: { $0.id == answering }) else { return }
                        refusal = reason
                        refusalOwner = answering
                    }
                }
                return
            }
            let departure = pendingDeparture
            pendingDeparture = nil
            let released = releaseAnswered()
            refreshBusyState()
            if let departure { leave(departure, releasing: released) }
        }
    }

    func discardAndLeave() {
        guard let registration else { return }
        isPromptPresented = false
        saveBlock = nil
        let departure = pendingDeparture
        pendingDeparture = nil
        registration.discard()
        var released: [UUID]?
        if answeringID != nil {
            released = releaseAnswered()
            isSaving = false
            refreshBusyState()
        } else {
            clearRegistration()
        }
        if let departure { leave(departure, releasing: released) }
    }

    func keepEditing() {
        isPromptPresented = false
        saveBlock = nil
        pendingDeparture = nil
        answeringID = nil
        endQuestion()
    }

     
     
     
    private func clearRegistration() {
        registrations.removeAll()
        answeringID = nil
        refusal = nil
        refusalOwner = nil
        isSaving = false
        refreshBusyState()
        isPromptPresented = false
        saveBlock = nil
    }
}

private struct ClashRootDepartureGuardKey: EnvironmentKey {
    static let defaultValue: ClashRootDepartureGuard? = nil
}

extension EnvironmentValues {
    var clashRootDepartureGuard: ClashRootDepartureGuard? {
        get { self[ClashRootDepartureGuardKey.self] }
        set { self[ClashRootDepartureGuardKey.self] = newValue }
    }
}

 
 
 
 
 
 
struct ClashDepartureRefusalAlert: View {
    @ObservedObject var departureGuard: ClashRootDepartureGuard

    var body: some View {
        Color.clear
            .alert(
                ClashCopy.key("Could Not Save"),
                isPresented: Binding(
                    get: { departureGuard.refusal != nil },
                    set: { if !$0 { departureGuard.acknowledgeRefusal() } }
                )
            ) {
                Button("OK", role: .cancel) { departureGuard.acknowledgeRefusal() }
            } message: {
                Text(clash: departureGuard.refusal ?? .verbatim(""))
            }
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum ClashDeparture {
    @MainActor
    static func request(
        _ departureGuard: ClashRootDepartureGuard?,
        leave: @escaping () -> Void
    ) {
        guard let departureGuard else {
            leave()
            return
        }
        departureGuard.requestDeparture(leave)
    }

     
    @MainActor
    static func requestBack(
        _ departureGuard: ClashRootDepartureGuard?,
        from page: UUID?,
        leave: @escaping () -> Void
    ) {
        guard let departureGuard else {
            leave()
            return
        }
        departureGuard.requestBack(from: page, leave)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public extension View {
    func clashRegistersDeparture(
        isDirty: Bool,
        isBusy: Bool = false,
        whySaveIsBlocked: (() -> ClashDisplayText?)? = nil,
        save: @escaping (@escaping (Bool) -> Void) -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        modifier(
            ClashDepartureRegistration(
                isDirty: isDirty,
                currentlyDirty: nil,
                isBusy: isBusy,
                whySaveIsBlocked: whySaveIsBlocked,
                 
                 
                 
                 
                save: { answer in save { answer(.bare($0)) } },
                discard: discard
            )
        )
    }

     
     
     
     
     
     
     
    func clashRegistersDeparture(
        isDirty: Bool,
        currentlyDirty: (() -> Bool)? = nil,
        isBusy: Bool = false,
        whySaveIsBlocked: (() -> ClashDisplayText?)? = nil,
        saveAnswering save: @escaping (@escaping (ClashDepartureSaveAnswer) -> Void) -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        modifier(
            ClashDepartureRegistration(
                isDirty: isDirty,
                currentlyDirty: currentlyDirty,
                isBusy: isBusy,
                whySaveIsBlocked: whySaveIsBlocked,
                save: save,
                discard: discard
            )
        )
    }
}

private struct ClashDepartureRegistration: ViewModifier {
     
     
     
     
     
    @State private var id = UUID()
    @Environment(\.clashRootDepartureGuard) private var guardObject
     
     
    @Environment(\.clashDeparturePage) private var departurePage
    let isDirty: Bool
    let currentlyDirty: (() -> Bool)?
    let isBusy: Bool
    let whySaveIsBlocked: (() -> ClashDisplayText?)?
    let save: (@escaping (ClashDepartureSaveAnswer) -> Void) -> Void
    let discard: () -> Void

    func body(content: Content) -> some View {
         
         
         
         
         
         
         
         
         
         
         
        register()
        return content
            .onAppear { register() }
             
             
             
             
            .onDisappear { guardObject?.unregister(id: id) }
    }

    private func register() {
        guardObject?.register(
            id: id,
            isDirty: isDirty,
            currentlyDirty: currentlyDirty,
            isBusy: isBusy,
            page: departurePage,
            whySaveIsBlocked: whySaveIsBlocked,
            saveAnswering: save,
            discard: discard
        )
    }
}
