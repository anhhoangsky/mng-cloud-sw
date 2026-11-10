import MNGKit
import SwiftUI

/// Search tab: debounced file-name search, five type chips, four album hints
/// and a 300-result grid. Results open the shared viewer with the whole result
/// list, exactly like `open_viewer()` in `shell.rs`.
struct SearchView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var fieldFocused: Bool

    private var search: SearchModel { model.search }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                    .padding(.bottom, 14)

                chips
                    .padding(.bottom, 2)

                if let meta = search.metaText {
                    Text(meta)
                        .font(.mng(13))
                        .foregroundStyle(Palette.text3)
                        .padding(.top, 10)
                        .padding(.bottom, 14)
                        .padding(.horizontal, 2)
                }

                results
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.top, isCompact ? 6 : 26)
            .padding(.bottom, isCompact ? 154 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.mng(17, weight: .medium))
                .foregroundStyle(Palette.text3)
                .accessibilityHidden(true)

            TextField(Strings.searchPlaceholder, text: queryBinding)
                .font(.mng(17))
                .foregroundStyle(Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .onSubmit {
                    search.submit()
                    fieldFocused = false
                }
                .accessibilityLabel(Strings.searchFieldLabel)

            if !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    search.clear()
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.mng(11, weight: .bold))
                        .foregroundStyle(Palette.text3)
                        .frame(width: 30, height: 30)
                        .background(Palette.fill2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.searchClear)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 48)
        .background(
            fieldFocused ? Palette.bgElevated : Palette.fill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(fieldFocused ? Palette.accentSoft : Color.clear, lineWidth: 4)
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { search.query },
            set: { search.updateQuery($0) }
        )
    }

    // MARK: - Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(SearchFilter.allCases, id: \.rawValue) { filter in
                    chip(filter)
                }
            }
            .padding(2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.searchFiltersLabel)
    }

    private func chip(_ filter: SearchFilter) -> some View {
        let active = search.filter == filter
        return Button {
            search.selectFilter(filter)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chipIcon(filter))
                    .font(.mng(12, weight: .semibold))
                Text(filter.label)
                    .font(.mng(13, weight: .semibold))
            }
            .foregroundStyle(active ? Palette.bg : Palette.text2)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(active ? Palette.text : Palette.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func chipIcon(_ filter: SearchFilter) -> String {
        switch filter {
        case .all: "square.grid.2x2"
        case .photo: "photo"
        case .video: "video"
        case .live: "livephoto"
        case .favorite: "heart"
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if search.showsHints {
            hints
        } else if search.isLoading {
            skeleton
        } else if let message = search.errorMessage {
            SearchEmptyState(
                icon: "exclamationmark.triangle",
                title: Strings.searchErrorTitle,
                message: message
            )
        } else if search.isReady, search.isEmpty {
            SearchEmptyState(
                icon: "magnifyingglass",
                title: Strings.searchEmptyTitle,
                message: Strings.searchEmptyBody
            )
        } else if !search.results.isEmpty {
            grid
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SearchHint.all) { hint in
                Button {
                    model.openAlbum(hint.album)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: hint.icon)
                            .font(.mng(16, weight: .medium))
                            .foregroundStyle(Palette.text3)
                            .frame(width: 18)
                        Text(hint.label)
                            .font(.mng(14))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        Palette.bgGrouped,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 26)
    }

    private var skeleton: some View {
        LazyVGrid(columns: gridColumns, spacing: gridGap) {
            ForEach(0..<12, id: \.self) { _ in
                ShimmerTile()
                    .aspectRatio(1, contentMode: .fill)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: gridGap) {
            ForEach(search.results) { item in
                TileView(model: model, item: item) {
                    model.library.openViewer(items: search.results, id: item.id)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        if isCompact {
            return Array(
                repeating: GridItem(.flexible(), spacing: Tokens.Layout.gridGap),
                count: 3
            )
        }
        return [GridItem(.adaptive(minimum: 150), spacing: 3)]
    }

    private var gridGap: CGFloat {
        isCompact ? Tokens.Layout.gridGap : 3
    }
}

private struct SearchEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.fill)
                    .frame(width: 68, height: 68)
                Image(systemName: icon)
                    .font(.mng(28, weight: .regular))
                    .foregroundStyle(Palette.text3)
            }
            .padding(.bottom, 6)

            Text(title)
                .font(.mng(18, weight: .semibold))
                .foregroundStyle(Palette.text2)

            Text(message)
                .font(.mng(13))
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 70)
    }
}
