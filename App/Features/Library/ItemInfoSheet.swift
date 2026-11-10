import MNGKit
import SwiftUI
import UIKit

/// Item info sheet with the same rows and actions as `info_body()` in
/// `shell.rs`. Detail data replaces the tile snapshot as soon as `/items/{id}`
/// returns.
struct ItemInfoSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var copied = false

    private var library: LibraryModel { model.library }

    var body: some View {
        NavigationStack {
            Group {
                if let item = library.infoItem {
                    content(item)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.info)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.close) {
                        library.dismissInfo()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func content(_ item: Item) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                rows(item)
                actions(item)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func rows(_ item: Item) -> some View {
        VStack(spacing: 0) {
            infoRow(Strings.itemName, value: item.name, lineLimit: 2)
            divider
            infoRow(Strings.itemDate, value: dateText(item))
            if item.lat != 0 || item.lng != 0 {
                divider
                locationRow(item)
            }
            divider
            infoRow(Strings.itemKind, value: kindText(item))
            divider
            infoRow(Strings.itemSize, value: MNGFormat.bytes(item.size))
            if let resolution = MNGFormat.resolution(width: item.width, height: item.height) {
                divider
                infoRow(Strings.itemResolution, value: resolution)
            }
            if item.isVideo {
                divider
                infoRow(Strings.itemDuration, value: MNGFormat.duration(item.duration))
            }
            divider
            infoRow(Strings.itemCloud, value: model.cloudLabel(for: item.cloud))
            divider
            infoRow(Strings.itemFolder, value: item.parent)
            divider
            infoRow(Strings.itemAccount, value: item.username)
            divider
            webdavRow(item)
        }
        .background(Palette.bgElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            if library.isLoadingInfo {
                ProgressView()
                    .controlSize(.mini)
                    .padding(10)
            }
        }
    }

    private func actions(_ item: Item) -> some View {
        VStack(spacing: 8) {
            Button {
                library.dismissInfo()
                dismiss()
                library.download(item)
            } label: {
                actionLabel(Strings.download, icon: "arrow.down.to.line")
                    .foregroundStyle(Palette.accentInk)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                copyWebDAV(item.webdavURL)
            } label: {
                actionLabel(
                    copied ? Strings.copiedWebDAV : Strings.copyWebDAV,
                    icon: copied ? "checkmark" : "doc.on.doc"
                )
                .foregroundStyle(Palette.text)
                .background(Palette.fill2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                library.deleteFromInfo(item)
                dismiss()
            } label: {
                actionLabel(
                    Strings.deleteFrom(cloud: model.cloudLabel(for: item.cloud)),
                    icon: "trash"
                )
                .foregroundStyle(Palette.danger)
                .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .contentShape(Rectangle())
    }

    private func infoRow(_ label: String, value: String, lineLimit: Int = 1) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.text3)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func locationRow(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(Strings.itemLocation)
                .font(.system(size: 13))
                .foregroundStyle(Palette.text3)
                .frame(width: 96, alignment: .leading)

            Button {
                guard let url = URL(
                    string: "https://maps.apple.com/?ll=\(item.lat),\(item.lng)"
                ) else { return }
                openURL(url)
            } label: {
                Text(MNGFormat.coordinate(latitude: item.lat, longitude: item.lng))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func webdavRow(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(Strings.itemWebDAV)
                .font(.system(size: 13))
                .foregroundStyle(Palette.text3)
                .frame(width: 96, alignment: .leading)

            Text(item.webdavURL)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, 13)
    }

    private func dateText(_ item: Item) -> String {
        let date = MNGFormat.itemDate(item)
        let time = MNGFormat.time(takenAt: item.takenAt)
        return time.isEmpty ? date : "\(date) lúc \(time)"
    }

    private func kindText(_ item: Item) -> String {
        guard item.isVideo else { return Strings.kindPhoto }
        return item.live ? Strings.videoLivePhoto : Strings.kindVideo
    }

    private func copyWebDAV(_ value: String) {
        guard !value.isEmpty else {
            model.notify(Strings.copyFailed)
            return
        }
        UIPasteboard.general.string = value
        model.notify(Strings.copiedWebDAV)
        withAnimation(Tokens.Motion.fade) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(Tokens.Motion.fade) { copied = false }
        }
    }
}
