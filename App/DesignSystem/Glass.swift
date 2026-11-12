import SwiftUI

/// The PWA's liquid-glass recipe.
///
/// Every floating control in `app.css` is built from the same layers: a
/// `blur(24px) saturate(185%)` backdrop, a 78 % elevated fill, a diagonal
/// sheen, an inset rim light and a long soft shadow. SwiftUI's material
/// covers the blur; this view adds the other four so the dock, the header
/// buttons and the selection bar read as one material.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(fill)
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(scheme == .dark ? 0.10 : 0.30), location: 0),
                        .init(color: .white.opacity(scheme == .dark ? 0.04 : 0.12), location: 0.36),
                        .init(color: .clear, location: 0.64),
                        .init(color: .white.opacity(scheme == .dark ? 0.06 : 0.16), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape
                .inset(by: 0.75)
                .strokeBorder(rim, lineWidth: 1.1)
        }
        .compositingGroup()
        .shadow(
            color: .black.opacity(scheme == .dark ? 0.34 : 0.08),
            radius: 18,
            y: 9
        )
        .shadow(
            color: .black.opacity(scheme == .dark ? 0.26 : 0.05),
            radius: 4,
            y: 2
        )
    }

    private var fill: Color {
        scheme == .dark
            ? Palette.bgElevated.opacity(0.78)
            : Color.white.opacity(0.72)
    }

    private var rim: Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.46)
    }
}

/// The web's `:active { transform: scale(0.95) }` on the glass controls.
struct GlassPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
