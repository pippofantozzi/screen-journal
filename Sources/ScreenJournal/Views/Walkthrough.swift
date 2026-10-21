import SwiftUI

/// Shared chrome for step-by-step windows: a bouncing hero badge, sliding content, page dots.
struct Walkthrough<Content: View>: View {
    let symbol: String
    let tint: Color
    let index: Int
    let count: Int
    var height: CGFloat = 480
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 28) {
            HeroBadge(symbol: symbol, tint: tint, trigger: index)
            ZStack {
                content()
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            PageDots(count: count, current: index, tint: tint)
        }
        .padding(.horizontal, 44)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .frame(width: 520, height: height)
        .background(
            LinearGradient(colors: [tint.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
                .animation(.easeInOut(duration: 0.6), value: index)
        )
    }
}

struct HeroBadge: View {
    let symbol: String
    let tint: Color
    let trigger: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.gradient)
                .frame(width: 96, height: 96)
                .shadow(color: tint.opacity(0.45), radius: 18, y: 8)
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: trigger)
        }
        .animation(.spring(duration: 0.5, bounce: 0.35), value: trigger)
    }
}

struct PageDots: View {
    let count: Int
    let current: Int
    let tint: Color
    @Namespace private var dots

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? tint : Color.secondary.opacity(0.25))
                    .frame(width: i == current ? 24 : 8, height: 8)
                    .matchedGeometryEffect(id: i, in: dots)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: current)
    }
}
