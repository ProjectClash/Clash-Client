import ClashClientUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

 
 
 
 
 
 
let clashAppleRuntimeProfile: ClashAppleRuntimeProfile = {
    guard let profile = ClashAppleRuntimeProfile(rawValue: clashAppleRuntimeProfileName) else {
         
         
         
         
        preconditionFailure("no ClashAppleRuntimeProfile for \(clashAppleRuntimeProfileName)")
    }
    return profile
}()

extension View {
    @ViewBuilder
    func clashStackNavigationViewStyle() -> some View {
#if os(macOS)
        self
#else
        navigationViewStyle(.stack)
#endif
    }

    @ViewBuilder
    func clashInsetGroupedListStyle() -> some View {
#if os(macOS)
         
         
         
         
         
         
        listStyle(.inset)
            .scrollDismissesKeyboard(.immediately)
#else
        listStyle(.insetGrouped)
#endif
    }

    @ViewBuilder
    func clashCapsuleButtonBorderShape() -> some View {
#if os(macOS)
        if #available(macOS 14.0, *) {
            buttonBorderShape(.capsule)
        } else {
            self
        }
#else
        buttonBorderShape(.capsule)
#endif
    }
}

extension ToolbarItemPlacement {
    static var clashNavigationTrailing: ToolbarItemPlacement {
#if os(macOS)
        .primaryAction
#else
        .navigationBarTrailing
#endif
    }
}

struct ClashEditButton: View {
    var body: some View {
#if os(macOS)
        EmptyView()
#else
        EditButton()
#endif
    }
}

#if os(iOS)
 
 
 
 
 
@MainActor
enum ClashUIKitTextFieldAlert {
    static func install() {
        ClashTextFieldAlertHost.present = { present($0) }
    }

     
    final class Answers: NSObject {
        nonisolated(unsafe) static var key: UInt8 = 0
        let request: ClashTextFieldAlertRequest
        weak var field: UITextField?
        weak var confirmAction: UIAlertAction?

        init(_ request: ClashTextFieldAlertRequest) { self.request = request }

        @objc func edited(_ field: UITextField) {
            let text = field.text ?? ""
            request.textChanged(text)
            confirmAction?.isEnabled = request.isConfirmEnabled(text)
        }

        func confirmed() { request.confirm(field?.text ?? request.text) }
        func cancelled() { request.cancel() }

         
         
         
         
        func once(_ alert: UIAlertController?, gone answer: @escaping () -> Void) {
            guard let coordinator = alert?.transitionCoordinator,
                  coordinator.animate(alongsideTransition: nil, completion: { _ in answer() })
            else { return answer() }
        }
    }

    static func answers(of alert: UIAlertController) -> Answers? {
        objc_getAssociatedObject(alert, &Answers.key) as? Answers
    }

    static func make(_ request: ClashTextFieldAlertRequest) -> UIAlertController {
        let alert = UIAlertController(title: request.title, message: nil, preferredStyle: .alert)
        let answers = Answers(request)
        objc_setAssociatedObject(alert, &Answers.key, answers, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        alert.addTextField { field in
            field.text = request.text
            field.placeholder = request.placeholder
            field.accessibilityIdentifier = request.identifier
            if request.kind == .url {
                field.keyboardType = .URL
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            field.addTarget(answers, action: #selector(Answers.edited(_:)), for: .editingChanged)
            answers.field = field
        }
        alert.addAction(UIAlertAction(title: request.cancelTitle, style: .cancel) { [weak alert] _ in
            answers.once(alert) { answers.cancelled() }
        })
        let confirm = UIAlertAction(title: request.confirmTitle, style: .default) { [weak alert] _ in
             
            let text = answers.field?.text ?? request.text
            answers.once(alert) { request.confirm(text) }
        }
        confirm.isEnabled = request.isConfirmEnabled(request.text)
        answers.confirmAction = confirm
        alert.addAction(confirm)
        alert.preferredAction = confirm
        return alert
    }

     
     
     
     
     
    static func present(_ request: ClashTextFieldAlertRequest,
                        front: @escaping @MainActor () -> UIViewController? = frontController,
                        tries: Int = 10, interval: UInt64 = 300_000_000) -> () -> Void {
        let alert = make(request)
        let state = Withdrawal()
        Task { @MainActor in
            for _ in 0..<tries {
                if state.withdrawn || alert.presentingViewController != nil { return }
                front()?.present(alert, animated: true)
                try? await Task.sleep(nanoseconds: interval)
            }
            if !state.withdrawn, alert.presentingViewController == nil { request.cancel() }
        }
        return {
            state.withdrawn = true
            if alert.presentingViewController != nil, !alert.isBeingDismissed { alert.dismiss(animated: true) }
        }
    }

    private final class Withdrawal { var withdrawn = false }

     
     
    static func frontController() -> UIViewController? {
        guard var front = ShellPresentationProbe.rootViewController() else { return nil }
        while let next = front.presentedViewController, !next.isBeingDismissed { front = next }
        return front
    }
}
#endif
