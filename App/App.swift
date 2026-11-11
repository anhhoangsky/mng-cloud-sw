import SwiftUI
import UIKit

@main
struct MNGCloudApp: App {
    /// The delegate registers the background tasks before the app finishes
    /// launching, which iOS requires.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
