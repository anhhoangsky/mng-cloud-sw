import SwiftUI

/// Floating multi-select bar matching the PWA's `.selection-bar`.
struct SelectionBar: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var library: LibraryModel { model.library }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: 4) {
            Text(Strings.selectedCount(library.selection.count))
                .font(Font.mng(isCompact ? 13 : 14, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize()
                .padding(.leading, isCompact ? 14 : 16)
                .padding(.trailing, isCompact ? 2 : 6)

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

            // Leaving selection must never depend on having picked a photo:
            // the web keeps its close button active when the set is empty.
            iconButton(
                icon: "xmark",
                label: Strings.deselect,
                action: library.exitSelection,
                enabledWhenEmpty: true
            )
        }
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background { GlassSurface(shape: Capsule()) }
        .animation(Tokens.Motion.fade, value: library.selection)
    }

    private func iconButton(
        icon: String,
        label: String,
        tint: Color = Palette.text2,
        action: @escaping () -> Void,
        enabledWhenEmpty: Bool = false
    ) -> some View {
        let enabled = enabledWhenEmpty || !library.selection.isEmpty
        return Button(action: action) {
            Image(systemName: icon)
                .font(Font.mng(20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: isCompact ? 38 : 40, height: isCompact ? 38 : 40)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.92))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.32)
        .accessibilityLabel(label)
    }
}
