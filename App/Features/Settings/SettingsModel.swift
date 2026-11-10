import Foundation
import MNGKit
import Observation

/// Settings mutations (cloud probe, scan, thumbnail retry, temp cleanup).
/// Each row has its own busy flag so a slow action never blocks the others,
/// matching the PWA's per-row `RwSignal<bool>`.
@MainActor
@Observable
final class SettingsModel {
    let client: MNGAPIClient

    private(set) var scanBusy = false
    private(set) var thumbsBusy = false
    private(set) var tmpBusy = false
    private(set) var testingClouds: Set<String> = []

    var onToast: ((String) -> Void)?
    var onRefresh: (() async -> Void)?
    var onUnauthorized: (() -> Void)?

    init(client: MNGAPIClient) {
        self.client = client
    }

    func isTesting(_ key: String) -> Bool {
        testingClouds.contains(key)
    }

    /// `CloudSettingRow`: probe WebDAV and show the server's latency/reason.
    func testCloud(_ cloud: CloudCard) async {
        let key = cloud.key
        guard !testingClouds.contains(key) else { return }
        testingClouds.insert(key)
        do {
            let response = try await client.testCloud(key)
            testingClouds.remove(key)
            let message: String
            if response.ok {
                message = response.ms > 0
                    ? Strings.cloudHealth(ms: response.ms)
                    : Strings.cloudTestGood
            } else {
                let reason = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
                message = reason.isEmpty ? Strings.cloudHealthBad : reason
            }
            onToast?(message)
            await onRefresh?()
        } catch {
            testingClouds.remove(key)
            report(error, fallback: Strings.testCloudFailed)
        }
    }

    /// `POST /scans` with `cloud = "all"`.
    func scanAll() async {
        guard !scanBusy else { return }
        scanBusy = true
        do {
            let response = try await client.scanAll()
            scanBusy = false
            onToast?(response.queued ? Strings.scanQueued : Strings.scanAlreadyQueued)
            await onRefresh?()
        } catch {
            scanBusy = false
            report(error, fallback: Strings.scanFailed)
        }
    }

    /// Requeue items whose thumbnail state is failed.
    func retryThumbs() async {
        guard !thumbsBusy else { return }
        thumbsBusy = true
        do {
            let response = try await client.retryThumbs()
            thumbsBusy = false
            onToast?(response.queued ? Strings.thumbsQueued : Strings.thumbsAlreadyQueued)
            await onRefresh?()
        } catch {
            thumbsBusy = false
            report(error, fallback: Strings.thumbsFailed)
        }
    }

    /// Clear temporary downloads/cache on the server.
    func clearTmp() async {
        guard !tmpBusy else { return }
        tmpBusy = true
        do {
            let response = try await client.clearTmp()
            tmpBusy = false
            onToast?(
                response.removed > 0
                    ? Strings.tmpCleared(response.removed)
                    : Strings.tmpEmpty
            )
            await onRefresh?()
        } catch {
            tmpBusy = false
            report(error, fallback: Strings.tmpFailed)
        }
    }

    private func report(_ error: Error, fallback: String) {
        let api = (error as? APIError) ?? .network()
        if api.status == 401 {
            onUnauthorized?()
            return
        }
        onToast?(APIMessages.settingsAction(api, fallback: fallback))
    }
}
