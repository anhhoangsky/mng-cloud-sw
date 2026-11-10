import SwiftUI

/// Rounded cloud mark shared by the boot and login screens.
struct AppMark: View {
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.333, style: .continuous)
                .fill(Palette.accentSoft)
                .frame(width: size, height: size)
            Image(systemName: "cloud.fill")
                .font(Font.mng(size * 0.45, weight: .medium))
                .foregroundStyle(Palette.accent)
        }
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.333, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        }
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
