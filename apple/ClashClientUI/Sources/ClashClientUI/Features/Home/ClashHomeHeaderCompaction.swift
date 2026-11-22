import Combine
import Foundation

enum ClashHomeHeaderCompaction {
    static func progress(distance: CGFloat, range: CGFloat) -> CGFloat {
        guard range > 0 else { return 0 }
        return min(max(distance / range, 0), 1)
    }

    static func value(
        expanded: CGFloat,
        compact: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        let progress = min(max(progress, 0), 1)
        return expanded + (compact - expanded) * progress
    }

     
     
     
     
    static func stagedValue(
        expanded: CGFloat,
        compact: CGFloat,
        distance: CGFloat,
        after precedingReduction: CGFloat
    ) -> CGFloat {
        let reduction = max(expanded - compact, 0)
        let applied = min(max(distance - precedingReduction, 0), reduction)
        return expanded - applied
    }

     
     
     
     
     
     
     
     
     
     
    static func statusSlotHeight(oneLine: CGFloat, measured: CGFloat, wraps: Bool, lines: Int) -> CGFloat {
        guard wraps else { return oneLine }
        return min(max(measured, oneLine), oneLine * CGFloat(max(lines, 1)) * 1.5)
    }
}

 
struct ClashHomeMeasuredLine: Equatable {
    var id = ""
    var height: CGFloat = 0

     
    func height(of id: String?) -> CGFloat {
        id == self.id ? height : 0
    }

     
     
    func differs(from other: ClashHomeMeasuredLine) -> Bool {
        id != other.id || abs(height - other.height) > 0.5
    }
}

final class ClashHomeHeaderCompactionState: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    func update(distance: CGFloat, range: CGFloat, enabled: Bool) {
        let next = enabled
            ? ClashHomeHeaderCompaction.progress(
                distance: distance,
                range: range
            )
            : 0
        guard abs(next - progress) > 0.001 else { return }
        progress = next
    }

    func reset() {
        guard progress != 0 else { return }
        progress = 0
    }
}
