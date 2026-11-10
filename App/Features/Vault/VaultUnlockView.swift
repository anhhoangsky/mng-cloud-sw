import MNGKit
import SwiftUI

/// Unlock screen for one vault. The password only derives a PBKDF2 key on the
/// device; it never reaches the server.
struct VaultUnlockView: View {
    let model: ShellModel
    let vault: NativeVault

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var password = ""
    @FocusState private var isFocused: Bool

    private var state: VaultModel { model.vault }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if vault.manifestReady {
                    form
                } else {
                    missingIndex
                }

                noteBar
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.top, isCompact ? 6 : 26)
            .padding(.bottom, isCompact ? 140 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg.ignoresSafeArea())
        .onAppear {
            isFocused = true
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.fill")
                .font(Font.mng(20, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 46, height: 46)
                .background(
                    Palette.accentSoft,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(vault.name)
                    .font(Font.mng(20, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text(Strings.vaultUnlockBody)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.vaultPassword)
                    .font(Font.mng(12, weight: .semibold))
                    .foregroundStyle(Palette.text2)

                SecureField(
                    Strings.vaultPasswordPlaceholder,
                    text: $password
                )
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFocused)
                .onSubmit { Task { await unlock() } }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    Palette.bgElevated,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 0.5)
                }
            }

            if !state.unlockError.isEmpty {
                Text(state.unlockError)
                    .font(Font.mng(12, weight: .medium))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await unlock() }
            } label: {
                HStack(spacing: 8) {
                    if state.isUnlocking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "lock.open")
                            .font(Font.mng(14, weight: .semibold))
                    }
                    Text(state.isUnlocking ? Strings.vaultUnlocking : Strings.vaultUnlock)
                        .font(Font.mng(15, weight: .semibold))
                }
                .foregroundStyle(Palette.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Palette.accent,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(state.isUnlocking)
            .opacity(state.isUnlocking ? 0.7 : 1)

            backButton
        }
    }

    private var missingIndex: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(Font.mng(24, weight: .regular))
                    .foregroundStyle(Palette.text4)
                Text(Strings.vaultNoIndexTitle)
                    .font(Font.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(Strings.vaultNoIndexBody)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 30)

            backButton
        }
    }

    private var backButton: some View {
        Button {
            state.backToList()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(Font.mng(12, weight: .semibold))
                Text(Strings.vaultBackToList)
                    .font(Font.mng(14, weight: .semibold))
            }
            .foregroundStyle(Palette.accent)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var noteBar: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "shield.lefthalf.filled")
                .font(Font.mng(13, weight: .semibold))
                .foregroundStyle(Palette.text3)
            Text(Strings.vaultNoteServer)
                .font(Font.mng(12))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func unlock() async {
        let secret = password
        password = ""
        isFocused = false
        await state.unlock(vault: vault, password: secret)
    }
}
