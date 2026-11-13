import MNGKit
import SwiftUI

/// Read-only duplicate browser from Settings. Groups reveal 30 at a time and
/// each thumbnail opens the shared viewer seeded with that group's items.
struct DuplicatesView: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss

    private var duplicates: DuplicatesModel { model.duplicates }

    private let columns = [
        GridItem(.adaptive(minimum: 128), spacing: 10, alignment: .top)
    ]

    /// A stable row for the list. The old index-based `ForEach` could read a
    /// group that had already been replaced when the model started its
    /// second load, which is what crashed the sheet on a re-open.
    private struct GroupRow: Identifiable {
        let index: Int
        let group: DuplicateGroup

        var id: String {
            let first = group.items.first?.item.id ?? 0
            return "\(index)-\(first)-\(group.date)"
        }
    }

    private var rows: [GroupRow] {
        duplicates.visibleGroups.enumerated().map { offset, group in
            GroupRow(index: offset + 1, group: group)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // A group card can hold dozens of thumbnails. Building all
                // thirty cards at once kept every thumbnail request (and its
                // decoded image) alive, which made the second open much
                // heavier than the first.
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(Strings.duplicatesSubtitle)
                        .font(Font.mng(13))
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)

                    content
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.duplicatesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await duplicates.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if duplicates.groups.isEmpty {
            switch duplicates.state {
            case .idle, .loading:
                emptyState(
                    icon: "magnifyingglass",
                    title: Strings.duplicatesLoadingTitle,
                    body: Strings.duplicatesLoadingBody
                )
            case .failed(let message):
                emptyState(
                    icon: "exclamationmark.triangle",
                    title: Strings.duplicatesErrorTitle,
                    body: message
                )
            case .ready:
                summaryRow
                emptyState(
                    icon: "checkmark.circle",
                    title: Strings.duplicatesEmptyTitle,
                    body: Strings.duplicatesEmptyBody
                )
            }
        } else {
            summaryRow

            if let message = duplicates.errorMessage {
                // The previous result stays readable while a refresh fails.
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Font.mng(15))
                        .foregroundStyle(Palette.danger)
                    Text(message)
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button(Strings.retry) {
                        Task { await duplicates.load() }
                    }
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    Palette.dangerSoft,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            ForEach(rows) { row in
                groupCard(index: row.index, group: row.group)
            }

            if duplicates.remaining > 0 {
                Button {
                    duplicates.expand()
                } label: {
                    Text(Strings.duplicateMore(duplicates.remaining))
                        .font(Font.mng(13, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            Palette.accentSoft,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summary
            if duplicates.state == .loading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.text3)
            }
            Spacer(minLength: 0)
        }
    }

    private var summary: Text {
        let hashed = max(0, duplicates.stats.hashed)
        let total = max(0, duplicates.stats.total)
        let base = Text("\(MNGFormat.number(hashed))/\(MNGFormat.number(total))")
            .fontWeight(.semibold)
            + Text(Strings.duplicatesAnalyzedSuffix)
            + Text(MNGFormat.number(Int64(duplicates.groups.count)))
            .fontWeight(.semibold)
            + Text(Strings.duplicatesGroupSuffix)
        if hashed < total {
            return base + Text(Strings.duplicatesPendingHashes)
        }
        return base
    }

    private func groupCard(index: Int, group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Strings.duplicateGroupTitle(index))
                    .font(Font.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text(
                    Strings.duplicateGroupMeta(
                        count: group.items.count,
                        similarity: group.similarity
                    )
                )
                .font(Font.mng(12))
                .foregroundStyle(Palette.text3)
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(uniqueItems(of: group), id: \.item.id) { row in
                    duplicateThumb(item: row.item, group: group)
                }
            }
        }
        .padding(12)
        .background(
            Palette.bgElevated.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }

    /// A group should never list the same row twice, but the server is the
    /// source of truth for the hash clusters. Collapse a repeated id here so
    /// the grid never receives two identical identities.
    private func uniqueItems(of group: DuplicateGroup) -> [DuplicateItem] {
        var seen = Set<Int64>()
        return group.items.filter { seen.insert($0.item.id).inserted }
    }

    private func duplicateThumb(item: Item, group: DuplicateGroup) -> some View {
        Button {
            open(item, in: group)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Palette.fill)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ThumbnailView(
                            client: model.client,
                            path: item.thumbnailPath(size: 360)
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.5)
                    }

                Text(meta(item))
                    .font(Font.mng(11))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
    }

    private func meta(_ item: Item) -> String {
        var text = ""
        if item.width > 0, item.height > 0 {
            text = "\(item.width)x\(item.height)"
        }
        if item.size > 0 {
            text += " · " + MNGFormat.bytes(item.size)
        }
        return text
    }

    private func open(_ item: Item, in group: DuplicateGroup) {
        let items = group.items.map(\.item)
        guard !items.isEmpty else { return }
        // The viewer is an overlay of the shell, not a presentation of this
        // sheet. Asking the shell to open it after `onDismiss` avoids racing
        // a dismissal animation, which is the other half of the second-open
        // failure.
        model.deferViewerOpen(items: items, id: item.id)
        dismiss()
    }

    private func emptyState(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(Font.mng(28, weight: .regular))
                .foregroundStyle(Palette.text4)
                .padding(.bottom, 2)
            Text(title)
                .font(Font.mng(14, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text(body)
                .font(Font.mng(12))
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 40)
    }
}
