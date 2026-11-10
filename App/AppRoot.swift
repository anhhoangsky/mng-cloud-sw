import SwiftUI

/// Root of the application. Phase 0 only renders the boot screen; phase 2
/// replaces this with the session state machine (checking → login → ready).
struct AppRootView: View {
    var body: some View {
        BootScreen(state: .loading)
    }
}

#Preview {
    AppRootView()
}
