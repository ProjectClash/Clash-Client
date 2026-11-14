import SwiftUI

 
 
 
 
 
 
 
 
struct ClashGridRowMarker: View {
    let rows: Int
    let row: Int
    let id: AnyHashable

    var body: some View {
        GeometryReader { proxy in
            let band = proxy.size.height / CGFloat(max(rows, 1))
            VStack(spacing: 0) {
                Color.clear.frame(height: band * CGFloat(row))
                Color.clear.frame(height: band)
                    .id(id)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
