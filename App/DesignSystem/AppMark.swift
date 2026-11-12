import SwiftUI

/// The logo of the app.
///
/// The artwork carries its own rounded shape, so the mark is the logo
/// itself and not a drawn square. The asset is a `512x512` PNG with the
/// corners of the tile transparent.
struct AppMark: View {
    var size: CGFloat = 84

    var body: some View {
        Image("AppMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.26), radius: size * 0.14, y: size * 0.06)
            .accessibilityLabel(Strings.appName)
    }
}

#Preview {
    VStack(spacing: 24) {
        AppMark(size: 84)
        AppMark(size: 64)
    }
    .padding()
    .background(Palette.bg)
}
