import MNGKit
import SwiftUI

/// List of the owner's encrypted vaults with the PWA's copy and actions.
struct VaultListView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isCreating = false
    @State private var deleting: NativeVault?
    @State private var renaming: NativeVault?

    private var vault: VaultModel { model.vault }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !isCompact {
                    Text(Strings.vaultTitle)
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.02)
                        .foregroundStyle(Palette.text)
                }

                actions

                if !vault.notice.isEmpty {
                    noticeBar(
                        icon: "checkmark.circle.fill",
                        tint: Palette.green,
                        message: vault.notice
                    )
                }

                if !model.pendingVaultMove.isEmpty {
                    noticeBar(
                        icon: "lock.fill",
                        tint: Palette.accent,
                        message: Strings.vaultMoveWaiting(
                            model.pendingVaultMove.count
                        )
                    )
                }

                content

                noteBar(
                    icon: "shield.lefthalf.filled",
                    tint: Palette.text3,
                    message: Strings.vaultNoteServer
                )
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.top, isCompact ? 6 : 26)
            .padding(.bottom, isCompact ? 140 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg.ignoresSafeArea())
        .task {
            await vault.loadVaults()
        }
        .sheet(isPresented: $isCreating) {
            VaultCreateSheet(model: model)
        }
        .sheet(item: $deleting) { target in
            VaultDeleteSheet(model: model, vault: target)
        }
        .sheet(item: $renaming) { target in
            VaultRenameSheet(model: model, vault: target)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                isCreating = true
            } label: {
                Label(Strings.vaultCreate, systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(
                        Palette.accent,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Button {
                Task { await vault.loadVaults() }
            } label: {
                Label(Strings.vaultRefresh, systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text2)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(
                        Palette.fill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(vault.isLoadingList)
            .opacity(vault.isLoadingList ? 0.55 : 1)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vault.vaults.isEmpty {
            if vault.isLoadingList {
                emptyState(
                    icon: "lock",
                    title: Strings.vaultLoading,
                    body: "",
                    loading: true
                )
            } else if !vault.listError.isEmpty {
                emptyState(
                    icon: "exclamationmark.triangle",
                    title: Strings.vaultLoadFailed,
                    body: vault.listError,
                    loading: false
                )
            } else {
                emptyState(
                    icon: "lock",
                    title: Strings.vaultEmptyTitle,
                    body: Strings.vaultEmptyBody,
                    loading: false
                )
            }
        } else {
            VStack(spacing: 0) {
                ForEach(vault.vaults.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 0.5)
                    }
                    row(vault.vaults[index])
                }
            }
            .background(
                Palette.bgElevated,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
        }
    }

    private func row(_ vault: NativeVault) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    Palette.accent,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Button {
                self.vault.select(vault)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vault.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(meta(vault))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                deleting = vault
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.danger)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Strings.vaultDeleteTitle) \(vault.name)")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contextMenu {
            Button {
                renaming = vault
            } label: {
                Label(Strings.vaultRename, systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleting = vault
            } label: {
                Label(Strings.delete, systemImage: "trash")
            }
        }
    }

    private func meta(_ vault: NativeVault) -> String {
        guard vault.manifestReady else {
            return "#\(vault.id) • \(Strings.vaultNoIndex)"
        }
        return Strings.vaultMeta(id: vault.id, bytes: vault.bytes)
    }

    private func noteBar(icon: String, tint: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func noticeBar(icon: String, tint: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }

    private func emptyState(
        icon: String,
        title: String,
        body: String,
        loading: Bool
    ) -> some View {
        VStack(spacing: 8) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Palette.text4)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.text)
            if !body.isEmpty {
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, 46)
    }
}
