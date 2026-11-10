import MNGKit
import SwiftUI

/// Root of the application: the same `checking → login → ready` machine as the
/// PWA `App` component.
struct AppRootView: View {
    @State private var store = SessionStore()

    var body: some View {
        Group {
            switch store.phase {
            case .checking:
                BootScreen(
                    state: store.bootError.map(BootState.failed) ?? .loading
                ) {
                    Task { await store.retry() }
                }
            case .login:
                LoginView(store: store)
            case .ready:
                SessionReadyView(store: store)
            }
        }
        .task {
            await store.start()
        }
    }
}

#Preview {
    AppRootView()
}
