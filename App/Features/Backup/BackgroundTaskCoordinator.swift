import BackgroundTasks
import Foundation
import UIKit

/// Schedules the automatic backup.
///
/// Two kinds of background work are used together:
///
/// * A `BGProcessingTask` runs when the device is idle and has a network. It
///   gets a generous budget, so a large backlog can drain. This is the part
///   that beats the Seafile client, which only uses the short refresh window.
/// * A `BGAppRefreshTask` is the safety net: it tops the queue up when the
///   processing task was refused because the device was busy.
///
/// The identifiers have to be registered before the app finishes launching,
/// which is why the registration lives in the app delegate.
final class BackgroundTaskCoordinator: @unchecked Sendable {
    static let shared = BackgroundTaskCoordinator()

    static let processingIdentifier = "com.mngcloud.app.backup.process"
    static let refreshIdentifier = "com.mngcloud.app.backup.refresh"

    private var registered = false

    private init() {}

    /// Register the background tasks. iOS refuses an app that registers a
    /// task too late, and a second registration of the same identifier is a
    /// crash, so it only happens once.
    func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            self.handle(task)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handle(task)
        }
    }

    /// Ask for the next background run.
    func schedule() {
        scheduleProcessing()
        scheduleRefresh()
    }

    private func scheduleProcessing() {
        let request = BGProcessingTaskRequest(
            identifier: Self.processingIdentifier
        )
        // The backup needs the network, but it should not keep the device
        // awake on a charger-free trip.
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        submit(request)
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: Self.refreshIdentifier
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        submit(request)
    }

    private func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The system refuses a duplicate request while the previous one is
            // still running. The run itself schedules the next one.
        }
    }

    private func handle(_ task: BGTask) {
        let completion = TaskCompletion(task: task)
        let work = Task { @MainActor in
            let engine = PhotoBackupEngine.shared
            await engine.run()
            completion.complete(success: true)
            // The next run is requested once this one is done: the system
            // refuses a second request with the same identifier.
            self.schedule()
        }
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
            self.schedule()
        }
    }
}

/// Reports the result of a background task exactly once.
///
/// The expiration handler and the task itself can both fire, and iOS only
/// accepts one `setTaskCompleted`.
private final class TaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        guard first else { return }
        task.setTaskCompleted(success: success)
    }
}

/// The application delegate.
///
/// The only thing it has to do is register the background tasks before the
/// app finishes launching, and forward the background session events to the
/// session so the app can be woken up to handle them.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundTaskCoordinator.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundTaskCoordinator.shared.schedule()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // The app came back to the front: pick up whatever the library gained
        // while it was away.
        let engine = PhotoBackupEngine.shared
        engine.startObserving()
        Task { @MainActor in
            await engine.run()
        }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundUploadSession.shared.setBackgroundCompletionHandler(
            completionHandler,
            for: identifier
        )
    }
}
