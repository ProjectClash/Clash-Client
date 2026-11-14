import SwiftUI

 
 
 
 
 
 
 
 
 
struct ClashGroupRefusalLine: View {
    let group: String
    let refusal: ClashGroupActionRefusal
    @State private var showsDetail = false

     
    var text: ClashDisplayText { refusal.result }

     
    var detail: String? { refusal.coreSentence }

    var body: some View {
        let line = Text(clash: text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let detail {
            Button {
                showsDetail = true
            } label: {
                HStack(spacing: ClashTheme.Spacing.compact) {
                    line
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("proxies.refusal.\(group)")
            .modifier(ClashGroupRefusalDetailOpening(
                isPresented: $showsDetail, group: group, refusal: refusal, detail: detail
            ))
        } else {
            line.accessibilityIdentifier("proxies.refusal.\(group)")
        }
    }
}

private struct ClashGroupRefusalDetailOpening: ViewModifier {
    @Binding var isPresented: Bool
    let group: String
    let refusal: ClashGroupActionRefusal
    let detail: String

    func body(content: Content) -> some View {
#if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ClashGroupRefusalDetailCard(group: group, title: refusal.result, detail: detail)
        }
#else
        content.clashSheet(isPresented: $isPresented) {
            ClashGroupRefusalDetailView(detail: ClashGroupRefusalDetail(group: group, refusal: refusal))
                .clashModalPresentation(.form)
        }
#endif
    }
}

 
 
struct ClashGroupRefusalDetailCard: View {
    let group: String
    let title: ClashDisplayText
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            Text(clash: title)
                .font(.headline)
            Text(verbatim: group)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: detail)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .clashTextSelectionEnabled()
                .accessibilityIdentifier("proxies.refusal.detail.\(group)")
        }
        .padding()
        .frame(width: 360, alignment: .leading)
    }
}
