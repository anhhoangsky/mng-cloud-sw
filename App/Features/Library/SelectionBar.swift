import SwiftUI

/// Floating multi-select bar matching the PWA's `.selection-bar`.
struct SelectionBar: View {
    let model: ShellModel

    private var library: LibraryModel { model.library }

    var body: some View {
        HStack(spacing: 2) {
            Text(Strings.selectedCount(library.selection.count))
                .font(.mng(13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize()
                .padding(.leading, 8)
                .padding(.trailing, 4)

            iconButton(
                icon: "heart",
                label: Strings.favorite,
                action: library.favoriteSelection
            )

            iconButton(
                icon: "arrow.down.to.line",
                label: Strings.download,
                action: library.downloadSelection
            )

            iconButton(
                icon: "lock",
                label: Strings.moveToVault,
                action: { model.requestVaultMove(Array(library.selection)) }
            )

            iconButton(
                icon: "trash",
                label: Strings.delete,
                tint: Palette.danger,
                action: library.deleteSelection
            )

            iconButton(
                icon: "xmark",
                label: Strings.deselect,
                action: library.exitSelection
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Palette.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
        .opacity(library.selection.isEmpty ? 0.92 : 1)
        .animation(Tokens.Motion.fade, value: library.selection)
    }

    private func iconButton(
        icon: String,
        label: String,
        tint: Color = Palette.text2,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.mng(18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(library.selection.isEmpty)
        .opacity(library.selection.isEmpty ? 0.32 : 1)
        .accessibilityLabel(label)
    }
}
