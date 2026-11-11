import MNGKit
import Photos
import SwiftUI

/// The automatic backup section of the settings.
///
/// The backup runs in the background, so this section only has to say what it
/// is doing: whether it is on, what is still queued and when it ran last.
struct BackupSettingsSection: View {
    let engine: PhotoBackupEngine

    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.backupSection.uppercased())
                .font(Font.mng(11, weight: .semibold))
                .tracking(0.06)
                .foregroundStyle(Palette.text4)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                toggleRow

                divider

                statusRow

                if engine.isEnabled {
                    divider

                    wifiRow

                    divider

                    videosRow

                    divider

                    runRow
                }
            }
            .padding(.horizontal, 14)
            .background(
                Palette.bgElevated,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }

            Text(Strings.backupNote)
                .font(Font.mng(12))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var toggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(Font.mng(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    Palette.accent,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.backupAutoTitle)
                    .font(Font.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(Strings.backupToggleBody)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { engine.isEnabled },
                set: { newValue in
                    engine.setEnabled(newValue)
                    if newValue {
                        Task { await requestPermissionAndRun() }
                    }
                }
            ))
            .labelsHidden()
            .tint(Palette.accent)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(Font.mng(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    statusTint,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.backupStatus)
                    .font(Font.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(statusText)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var wifiRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(Font.mng(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    Palette.text3,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.backupWifiOnly)
                    .font(Font.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(Strings.backupWifiOnlyBody)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { engine.wifiOnly },
                set: { engine.setWifiOnly($0) }
            ))
            .labelsHidden()
            .tint(Palette.accent)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var videosRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "video")
                .font(Font.mng(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    Palette.text3,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.backupVideos)
                    .font(Font.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(Strings.backupVideosBody)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { engine.includeVideos },
                set: { engine.setIncludeVideos($0) }
            ))
            .labelsHidden()
            .tint(Palette.accent)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var runRow: some View {
        Button {
            Task { await runNow() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(Font.mng(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(
                        Palette.green,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.backupRunNow)
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(Strings.backupRunNowBody)
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(Font.mng(11, weight: .semibold))
                    .foregroundStyle(Palette.text4)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    // MARK: - Actions

    private func requestPermissionAndRun() async {
        let status = await engine.requestAuthorization()
        guard status == .authorized || status == .limited else { return }
        await runNow()
    }

    private func runNow() async {
        isWorking = true
        await engine.run()
        isWorking = false
    }

    // MARK: - Status

    private var statusText: String {
        switch engine.status {
        case .off:
            return Strings.backupStatusOff
        case .waitingForPermission:
            return Strings.backupStatusPermission
        case .idle:
            return summary
        case .scanning:
            return Strings.backupStatusScanning
        case .uploading(let done, let total):
            return Strings.backupProgress(done, total)
        case .failed(let message):
            return message
        }
    }

    private var summary: String {
        var parts = [
            Strings.backupSummary(
                uploaded: engine.uploaded,
                skipped: engine.skipped,
                failed: engine.failed
            )
        ]
        if engine.pendingCount > 0 {
            parts.append(Strings.backupPending(engine.pendingCount))
        }
        if let last = engine.lastRun {
            parts.append(Strings.backupLastRun(last))
        }
        return parts.joined(separator: " · ")
    }

    private var statusIcon: String {
        switch engine.status {
        case .off: return "pause.circle"
        case .waitingForPermission: return "exclamationmark.triangle"
        case .idle: return "checkmark.circle"
        case .scanning: return "magnifyingglass"
        case .uploading: return "arrow.up.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusTint: Color {
        switch engine.status {
        case .failed, .waitingForPermission: return Palette.orange
        case .off: return Palette.text3
        default: return Palette.green
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
    }
}
