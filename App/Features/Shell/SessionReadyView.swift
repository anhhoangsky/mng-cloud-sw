import MNGKit
import SwiftUI

/// Temporary authenticated screen for phase 2. Phase 3 replaces the content
/// with the real shell and library while keeping this session wiring.
struct SessionReadyView: View {
    let store: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bgGrouped.ignoresSafeArea()

                VStack(spacing: Tokens.Spacing.l) {
                    AppMark(size: 72)

                    Text(store.session?.me.label ?? "")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.text)

                    Text(Strings.sessionReady)
                        .font(.subheadline)
                        .foregroundStyle(Palette.green)

                    Text(Strings.sessionReadyHint)
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .padding(Tokens.Spacing.xl)
            }
            .navigationTitle(Strings.navLibrary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isLoggingOut ? Strings.signingOut : Strings.logout) {
                        Task { await store.logout() }
                    }
                    .disabled(store.isLoggingOut)
                }
            }
            .alert(
                Strings.logout,
                isPresented: Binding(
                    get: { store.logoutError != nil },
                    set: { presented in
                        if !presented { store.clearLogoutError() }
                    }
                )
            ) {
                Button(Strings.close, role: .cancel) {
                    store.clearLogoutError()
                }
            } message: {
                Text(store.logoutError ?? "")
            }
        }
    }
}

#Preview {
    SessionReadyView(store: SessionStore())
}
