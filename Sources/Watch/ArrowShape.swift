import SwiftUI

/// The direction arrow: a broad chevron with a notched tail, drawn to point up
/// at rotation zero.
///
/// Deliberately asymmetric front-to-back — a plain triangle reads as
/// ambiguous at a glance on a small screen, whereas a notched tail makes
/// "which end is the front" instant.
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + height * 0.82))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + height * 0.62))
        path.addLine(to: CGPoint(x: rect.minX + width, y: rect.minY + height * 0.82))
        path.closeSubpath()
        return path
    }
}

/// Tick marks around the edge, so rotation is legible even when the arrow is
/// pointing almost straight up.
struct CompassDial: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    let isCardinal = index % 3 == 0
                    Capsule()
                        .fill(Color.secondary.opacity(isCardinal ? 0.55 : 0.25))
                        .frame(width: isCardinal ? 2.5 : 1.5, height: isCardinal ? 9 : 5)
                        .offset(y: -size / 2 + 6)
                        .rotationEffect(.degrees(Double(index) * 30))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
