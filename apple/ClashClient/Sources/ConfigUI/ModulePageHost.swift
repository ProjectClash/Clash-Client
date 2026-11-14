#if os(iOS) || os(macOS)
import ClashClientUI
import SwiftUI
#if os(macOS)
import ClashMacClient
#endif

 
 
 
 
 
 
 
 
struct ModulePageHost: View {
    @ObservedObject var model: ModulePageModel
    @ObservedObject private var addRequest: ModuleAddRequest
     
     
    private let noticePlaces: ClashModulesNoticePlaces?
     
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
     
    @Environment(\.clashFeedback) private var feedback

     
    static let pollInterval: UInt64 = 5_000_000_000

    init(model: ModulePageModel, noticePlaces: ClashModulesNoticePlaces? = nil) {
        self.model = model
        addRequest = model.addRequest
        self.noticePlaces = noticePlaces
    }

     
     
     
     
    static func offers(_ place: ClashModulesSnapshot.NoticePlace, activeProfileID: String?, exists: (String) -> Bool) -> Bool {
        switch place {
        case .snifferSettings(let id): return id == activeProfileID && exists(id)
        }
    }

     
     
     
     
     
     
    static func detailResultPlace(_ center: ClashFeedbackCenter?) -> ((String) -> AnyView)? {
#if os(macOS)
        guard let center else { return nil }
        return { id in AnyView(ModuleDetailResultPlace(center: center, operations: detailResultOperations(of: id))) }
#else
        return nil
#endif
    }

     
    static func detailResultOperations(of id: String) -> [String] {
        [ModulePageModel.updateOperation(of: id)]
    }

    var body: some View {
        ClashClientUI.ClashModulesView(
            snapshot: model.snapshot,
            writes: model.writes,
            perform: { model.perform($0, feedback: feedback) },
            detail: { model.details[$0] },
            opensAddModule: addRequest.link != nil && isVisible && scenePhase == .active,
             
            pullToUpdate: { await model.refreshAll(feedback: feedback) },
             
             
            noticePlaces: noticePlaces,
            detailResultPlace: Self.detailResultPlace(feedback),
            quickAdd: { open in
                ModuleQuickAddCard(
                    isAdding: model.isAdding,
                    refusal: model.addRefusal,
                    add: { input in Task { _ = await model.add(input) } },
                    create: {
                        model.addRefusal = nil
                        open(.manual)
                    }
                )
            }
        ) { mode, dismiss in
            ModuleAddModuleSheet(
                mode: mode,
                isAdding: model.isAdding,
                refusal: model.addRefusal,
                offeredLink: addRequest.link,
                add: { input, name in
                    Task { if await model.add(input, name: name) { dismiss() } }
                },
                cancel: {
                    model.addRefusal = nil
                    dismiss()
                },
                edited: { model.addRefusal = nil }
            )
             
            .onDisappear { addRequest.settle() }
        }
        .onAppear { ModuleTextPlatform.installIfNeeded() }
         
         
         
         
        .clashOnScreen { onScreen in
            isVisible = onScreen
            if onScreen {
                addRequest.pageAppeared()
            } else {
                addRequest.pageDisappeared()
            }
        }
        .task {
            model.locale = locale
             
             
            model.sceneIsActive = scenePhase == .active
            await model.reload()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                 
                 
                guard !Task.isCancelled, model.sceneIsActive else { continue }
                await model.refreshRuntime()
            }
        }
        .onChange(of: scenePhase) { phase in
            model.sceneIsActive = phase == .active
            guard phase == .active else { return }
            Task { await model.reload() }
        }
        .onChange(of: locale) { newLocale in
            model.locale = newLocale
            Task { await model.reload() }
        }
    }
}
#if os(macOS)
 
 
private struct ModuleDetailResultPlace: View {
    @ObservedObject var center: ClashFeedbackCenter
    let operations: [String]

    var body: some View {
        let saying = operations.contains { center.result(for: $0) != nil }
        ClashMacFeedbackSlot(center: center, operations: operations)
            .padding(.horizontal, saying ? 20 : 0)
            .padding(.top, saying ? 8 : 0)
            .environment(\.clashFeedback, center)
    }
}
#endif
#endif
