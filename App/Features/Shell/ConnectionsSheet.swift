import MNGKit
import SwiftUI
import UIKit

/// Cloud connections sheet: cloud cards with WebDAV copy + health, plus the
/// read-only iCloud status row. Replaces the old cloud picker; selecting a
/// cloud dismisses the sheet.
struct ConnectionsSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var route: Route

    enum Route {
        case connections
        case icloud
    }

    init(model: ShellModel, initial: Route = .connections) {
        self.model = model
        _route = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .connections:
                    connections
                case .icloud:
                    ICloudDetail(model: model)
                }
            }
            .background(Palette.bgGrouped)
            .navigationTitle(
                route == .icloud ? Strings.icloudPhotos : Strings.connectionsTitle
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if route == .icloud {
                        Button {
                            withAnimation(Tokens.Motion.fade) {
                                route = .connections
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(Strings.back)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var connections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Strings.connectionsSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text3)

                if model.clouds.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(Strings.connecting)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.text3)
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.clouds, id: \.key) { cloud in
                            CloudConnectionCard(model: model, cloud: cloud) {
                                Task {
                                    await model.switchCloud(cloud.key)
                                    dismiss()
                                }
                            }
                        }
                    }
                }

                Text(Strings.connectionsNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)

                iCloudRow
            }
            .padding(16)
        }
    }

    private var iCloudRow: some View {
        Button {
            withAnimation(Tokens.Motion.fade) {
                route = .icloud
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.icloud)
                    .frame(width: 34, height: 34)
                    .background(Palette.icloud.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.icloudPhotos)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(model.icloud.row.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(model.icloud.row.value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text3)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text4)
            }
            .padding(12)
            .background(Palette.bgElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            if case .unknown = model.icloud.state {
                await model.icloud.load()
            }
        }
    }
}

private struct CloudConnectionCard: View {
    let model: ShellModel
    let cloud: CloudCard
    let onSelect: () -> Void

    private var isActive: Bool { cloud.key == model.activeCloud }

    private var label: String {
        let trimmed = cloud.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? cloud.key : trimmed
    }

    private var sub: String {
        if cloud.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cloud.username
        }
        return "\(cloud.username) · \(cloud.root)"
    }

    private var health: (PaletteDot, String) {
        guard let health = cloud.health else {
            return (.none, Strings.cloudHealthUnknown)
        }
        if health.ok {
            return (.ok, Strings.cloudHealth(ms: health.ms))
        }
        return (.bad, Strings.cloudHealthBad)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isActive ? Palette.accent : Palette.text3)
                        .frame(width: 34, height: 34)
                        .background(
                            isActive ? Palette.accentSoft : Palette.fill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        if !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.text3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(MNGFormat.count(cloud.counts.total)) mục")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.text3)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(health.0.color)
                                .frame(width: 7, height: 7)
                            Text(health.1)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.text3)
                                .lineLimit(1)
                        }
                    }

                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !cloud.webdav.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    Text(cloud.webdav)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button(Strings.webdavCopy) {
                        UIPasteboard.general.string = cloud.webdav
                        model.notify(Strings.webdavCopied)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Palette.fill)
            }
        }
        .background(Palette.bgElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isActive ? Palette.accent.opacity(0.55) : Palette.hairline,
                    lineWidth: isActive ? 1 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum PaletteDot {
    case none
    case ok
    case bad

    var color: Color {
        switch self {
        case .none: Palette.text4
        case .ok: Palette.green
        case .bad: Palette.danger
        }
    }
}

/// Read-only iCloud page. The importer controls are intentionally deferred to
/// P7; this only reports the server's real status.
private struct ICloudDetail: View {
    let model: ShellModel

    private var row: ICloudModel.Row { model.icloud.row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.icloud)
                        .frame(width: 46, height: 46)
                        .background(Palette.icloud.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.icloudPhotos)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        HStack(spacing: 6) {
                            dot
                            Text(row.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }

                infoCard {
                    infoRow(Strings.icloudStatusLabel, value: row.value)
                    if !model.icloud.appleID.isEmpty {
                        Divider().overlay(Palette.hairline)
                        infoRow(Strings.icloudAppleID, value: model.icloud.appleID)
                    }
                }

                Text(Strings.icloudNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Strings.icloudDeferred)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task { await model.icloud.load() }
                } label: {
                    HStack(spacing: 7) {
                        if model.icloud.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Text(Strings.retry)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.icloud.isLoading)
            }
            .padding(16)
        }
        .task {
            await model.icloud.load()
        }
    }

    private var dot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    private var dotColor: Color {
        switch row.dot {
        case .none: Palette.text4
        case .ok: Palette.green
        case .warn: Palette.orange
        case .bad: Palette.danger
        }
    }

    private func infoCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .background(Palette.bgElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.text3)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.trailing)
        }
    }
}
