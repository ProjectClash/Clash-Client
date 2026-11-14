import SwiftUI
import UniformTypeIdentifiers

 
 
public enum ClashPlatformLayout {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static var collectionLeadsWithEmptyState: Bool { true }

     
     
     
     
    public static var tunnelRunsBoundedDefaults: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

     
     
     
     
     
    public static var proxiesSweepLivesInToolbar: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

     
     
     
     
     
    public static var proxiesDisplayOptionsUseListAxes: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

     
     
     
     
     
     
     
     
     
     
     
    public static var installsCompensatingInlineRootTitle: Bool {
#if os(macOS)
        false
#else
        true
#endif
    }

     
     
     
     
     
     
     
     
    public static var proxiesKeepsOneGroupOpen: Bool {
#if os(macOS)
        false
#else
        true
#endif
    }

    public static var pageUsesSystemSettingsIdiom: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    public static var regularShellKeepsContainer: Bool {
        pageUsesSystemSettingsIdiom
            || !ProcessInfo.processInfo.arguments.contains("--clash-rekey-container")
    }

     
     
     
     
     
     
     
     
     
     
     
    public static var primaryPageCardUsesLiquidGlass: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func touchCardWearsSystemMaterial(
        onSystemMajorVersion major: Int
    ) -> Bool {
        major < 27
    }

    public static var touchCardWearsSystemMaterial: Bool {
        touchCardWearsSystemMaterial(
            onSystemMajorVersion: ProcessInfo.processInfo
                .operatingSystemVersion.majorVersion
        )
    }


     
     
     
    public static var modalEditorUsesGroupedForm: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

     
     
     
    public static var sidebarFooterConsumesOwnLayoutSpace: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

     
     
     
     
     
     
    public static var sidebarStacksLabelsAtAccessibilitySizes: Bool {
#if os(macOS)
        false
#else
        true
#endif
    }

     
     
     
     
     
    public static var immediateDisplayOptionsUseMenu: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

     
     
     
     
    public static var profileReorderingUsesDedicatedTask: Bool {
#if os(macOS)
        false
#else
        true
#endif
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static var columnStableSliceLength: Int? {
#if os(macOS)
        60
#else
        nil
#endif
    }

     
     
     
     
     
     
    public static var displayChangeSwapsToPlaceholder: Bool {
#if os(macOS)
        false
#else
        true
#endif
    }


    public static var dataPagesDeferContentOneTurn: Bool {
#if os(iOS) || os(macOS)
        true
#else
        false
#endif
    }
}

enum ClashReorderDropEdge: Equatable {
    case before
    case after
}

struct ClashReorderDropTarget: Equatable {
    let id: String
    let edge: ClashReorderDropEdge
}

 
 
 
 
 
public struct ClashModalEditorBody<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
#if os(macOS)
        Form {
            content
        }
        .formStyle(.grouped)
#else
        List {
            content
        }
#endif
    }
}

public extension View {
     
     
     
     
    @ViewBuilder
    func clashExplicitReorderMode() -> some View {
#if os(iOS)
        environment(\.editMode, .constant(.active))
#else
        self
#endif
    }

     
     
     
     
    internal func clashDirectReorderRow(
        id: String,
        label: String,
        enabled: Bool,
        draggedID: Binding<String?>,
        dropTarget: Binding<ClashReorderDropTarget?>,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMove: @escaping (
            _ sourceID: String,
            _ destinationID: String,
            _ edge: ClashReorderDropEdge
        ) -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void
    ) -> some View {
        modifier(ClashDirectReorderRowModifier(
            id: id,
            label: label,
            enabled: enabled,
            draggedID: draggedID,
            dropTarget: dropTarget,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMove: onMove,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown
        ))
    }

     
     
    func clashModalEditorToolbar(
        confirmTitle: LocalizedStringKey,
        confirmationIdentifier: String,
        confirmationDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            ClashModalEditorToolbarModifier(
                confirmTitle: confirmTitle,
                confirmationIdentifier: confirmationIdentifier,
                confirmationDisabled: confirmationDisabled,
                onCancel: onCancel,
                onConfirm: onConfirm
            )
        )
    }
}

private struct ClashDirectReorderRowModifier: ViewModifier {
    let id: String
    let label: String
    let enabled: Bool
    @Binding var draggedID: String?
    @Binding var dropTarget: ClashReorderDropTarget?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (String, String, ClashReorderDropEdge) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if enabled {
            content
                .onDrag {
                    draggedID = id
                    return NSItemProvider(object: id as NSString)
                } preview: {
                    Text(label)
                        .font(.body)
                        .lineLimit(1)
                        .padding(.horizontal, ClashTheme.Spacing.standard)
                        .padding(.vertical, ClashTheme.Spacing.row)
                        .background(.regularMaterial)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: ClashTheme.Radius.control,
                                style: .continuous
                            )
                        )
                }
                .onDrop(
                    of: [UTType.utf8PlainText.identifier],
                    delegate: ClashDirectReorderDropDelegate(
                        id: id,
                        draggedID: $draggedID,
                        dropTarget: $dropTarget,
                        onMove: onMove
                    )
                )
                .overlay(alignment: .top) {
                    insertionLine(.before)
                }
                .overlay(alignment: .bottom) {
                    insertionLine(.after)
                }
                .contextMenu {
                    Button("Move Up", action: onMoveUp)
                        .disabled(!canMoveUp)
                    Button("Move Down", action: onMoveDown)
                        .disabled(!canMoveDown)
                }
                .accessibilityAction(named: "Move Up", onMoveUp)
                .accessibilityAction(named: "Move Down", onMoveDown)
        } else {
            content
        }
#else
        content
#endif
    }

    @ViewBuilder
    private func insertionLine(_ edge: ClashReorderDropEdge) -> some View {
        if dropTarget == ClashReorderDropTarget(id: id, edge: edge) {
            Capsule()
                .fill(.tint)
                .frame(height: 2)
                .padding(.horizontal, ClashTheme.Spacing.standard)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#if os(macOS)
private struct ClashDirectReorderDropDelegate: DropDelegate {
    let id: String
    @Binding var draggedID: String?
    @Binding var dropTarget: ClashReorderDropTarget?
    let onMove: (String, String, ClashReorderDropEdge) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil && draggedID != id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedID != nil, draggedID != id else {
            return DropProposal(operation: .forbidden)
        }
        let midpoint = ClashTheme.Regular.Detail.destinationRowMinHeight / 2
        let edge: ClashReorderDropEdge = info.location.y < midpoint
            ? .before
            : .after
        let next = ClashReorderDropTarget(id: id, edge: edge)
        if dropTarget != next {
            DispatchQueue.main.async {
                dropTarget = next
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard dropTarget?.id == id else { return }
        DispatchQueue.main.async {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedID,
              sourceID != id else {
            draggedID = nil
            dropTarget = nil
            return false
        }
        let edge = dropTarget?.id == id
            ? dropTarget?.edge ?? .before
            : .before
        onMove(sourceID, id, edge)
        draggedID = nil
        dropTarget = nil
        return true
    }
}
#endif

private struct ClashModalEditorToolbarModifier: ViewModifier {
    let confirmTitle: LocalizedStringKey
    let confirmationIdentifier: String
    let confirmationDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content.clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle, action: onConfirm)
                    .disabled(confirmationDisabled)
                    .accessibilityIdentifier(confirmationIdentifier)
            }
        }
#endif
    }
}
