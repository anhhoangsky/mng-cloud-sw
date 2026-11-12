import SwiftUI

/// The floating material used by the dock, the header buttons and every
/// selection control.
///
/// iOS liquid glass is not a flat translucent panel: it is a clear material
/// with a strong specular rim on the lit edge, a darker reflected edge at the
/// bottom and a very light tint that lets the photo underneath show through.
/// SwiftUI's `.ultraThinMaterial` supplies the blur and the adaptive
/// background; the layers here add the rim, the sheen and the depth so the
/// result follows the system glass language on every iOS version supported by
/// the app.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26.0, *) {
            nativeGlass
        } else {
            layeredGlass
        }
    }

    /// Real Liquid Glass on iOS 26. The system owns the refraction, the
    /// adaptive tint, the specular edge and the shadow; drawing our own
    /// approximation underneath would only muddy it.
    @available(iOS 26.0, *)
    private var nativeGlass: some View {
        shape
            .fill(.clear)
            .glassEffect(.regular, in: shape)
    }

    private var layeredGlass: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(Palette.bgElevated.opacity(0.96))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(tint)
                shape.fill(sheen)
            }

            // The lit edge. The gradient is brighter at the top-left and
            // settles into a soft reflection at the bottom-right, the way a
            // pane of glass catches a window.
            shape
                .inset(by: 0.5)
                .strokeBorder(rim, lineWidth: 1)

            // A thin inner bevel just below the rim.
            shape
                .inset(by: 1.4)
                .strokeBorder(innerBevel, lineWidth: 0.8)
                .blur(radius: 0.4)

            // The lower edge catches the dark side of the room. Blurring the
            // inset stroke keeps it from reading as a second border.
            shape
                .inset(by: 1)
                .strokeBorder(bottomBevel, lineWidth: 1.4)
                .blur(radius: 1.1)
        }
        .compositingGroup()
        .shadow(
            color: .black.opacity(scheme == .dark ? 0.32 : 0.10),
            radius: 22,
            y: 12
        )
        .shadow(
            color: .black.opacity(scheme == .dark ? 0.20 : 0.05),
            radius: 3,
            y: 1
        )
    }

    /// A light neutral tint, not a solid panel. The material already supplies
    /// most of the body; this only anchors the control over bright photos.
    private var tint: Color {
        if scheme == .dark {
            return Palette.bgElevated.opacity(0.34)
        }
        return Color.white.opacity(0.32)
    }

    private var sheen: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: .white.opacity(scheme == .dark ? 0.15 : 0.34),
                    location: 0
                ),
                .init(
                    color: .white.opacity(scheme == .dark ? 0.03 : 0.10),
                    location: 0.38
                ),
                .init(color: .clear, location: 0.66),
                .init(
                    color: .white.opacity(scheme == .dark ? 0.05 : 0.14),
                    location: 1
                ),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rim: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: .white.opacity(scheme == .dark ? 0.52 : 0.92),
                    location: 0
                ),
                .init(
                    color: .white.opacity(scheme == .dark ? 0.16 : 0.46),
                    location: 0.30
                ),
                .init(
                    color: .white.opacity(scheme == .dark ? 0.07 : 0.24),
                    location: 0.64
                ),
                .init(
                    color: .white.opacity(scheme == .dark ? 0.26 : 0.62),
                    location: 1
                ),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerBevel: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(scheme == .dark ? 0.20 : 0.54),
                .white.opacity(scheme == .dark ? 0.02 : 0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var bottomBevel: LinearGradient {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(scheme == .dark ? 0.36 : 0.08),
            ],
            startPoint: .center,
            endPoint: .bottom
        )
    }
}

/// The web's `:active { transform: scale(0.95) }` on the glass controls.
/// The release uses the same spring as the system, so the control settles
/// instead of snapping back.
struct GlassPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(
                .spring(response: 0.26, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}
