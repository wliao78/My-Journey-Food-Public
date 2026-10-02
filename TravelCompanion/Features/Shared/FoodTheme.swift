import SwiftUI

enum FoodTheme {
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.38)
    static let secondaryText = Color.white.opacity(0.68)
    static let panel = Color.white.opacity(0.11)
    static let border = Color.white.opacity(0.14)

    static var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.10, blue: 0.19),
                    Color(red: 0.08, green: 0.18, blue: 0.25),
                    Color(red: 0.035, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.12, green: 0.45, blue: 0.52).opacity(0.28))
                .frame(width: 420, height: 420)
                .blur(radius: 95)
                .offset(x: 190, y: -320)
            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: -210, y: 390)
        }
        .ignoresSafeArea()
    }
}

private struct FoodPanel: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(FoodTheme.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(FoodTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func foodPanel(cornerRadius: CGFloat = 22) -> some View {
        modifier(FoodPanel(cornerRadius: cornerRadius))
    }
}
