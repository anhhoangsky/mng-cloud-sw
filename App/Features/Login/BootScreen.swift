import SwiftUI

enum BootState: Equatable {
    case loading
    case failed(String)
}

/// Static boot screen matching the PWA shell: logo mark, app name, spinner and
/// the Vietnamese status copy. Phase 2 wires it to `GET /api/v1/auth/me`.
struct BootScreen: View {
    let state: BootState
    var onRetry: () -> Void = {}

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: Tokens.Spacing.l) {
                AppMark(size: 84)

                Text(Strings.appName)
                    .font(.mng(22, weight: .semibold))
                    .foregroundStyle(Palette.text)

                content
            }
            .padding(Tokens.Spacing.xl)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: Tokens.Spacing.s) {
                ProgressView()
                    .tint(Palette.accent)
                Text(Strings.bootLoading)
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }
        case .failed(let message):
            VStack(spacing: Tokens.Spacing.m) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
                Button(Strings.bootRetry, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
        }
    }
}

#Preview("Loading") {
    BootScreen(state: .loading)
}

#Preview("Failed") {
    BootScreen(state: .failed("Không kết nối được máy chủ."))
}
