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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
            summary

            if duplicates.groups.isEmpty {
                emptyState(
                    icon: "checkmark.circle",
                    title: Strings.duplicatesEmptyTitle,
                    body: Strings.duplicatesEmptyBody
                )
            } else {
                ForEach(duplicates.visibleGroups.indices, id: \.self) { index in
                    groupCard(
                        index: index + 1,
                        group: duplicates.visibleGroups[index]
                    )
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
                ForEach(group.items, id: \.item.id) { row in
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
        dismiss()
        model.library.openViewer(items: items, id: item.id)
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
