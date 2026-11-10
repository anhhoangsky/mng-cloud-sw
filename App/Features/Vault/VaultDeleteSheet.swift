import MNGKit
import SwiftUI

/// Delete one vault. The password only re-derives the key to prove ownership;
/// it is never sent to the server.
struct VaultDeleteSheet: View {
    let model: ShellModel
    let vault: NativeVault

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @FocusState private var isFocused: Bool

    private var state: VaultModel { model.vault }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Strings.vaultDeleteBody(vault.name))
                        .font(.mng(13))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(Strings.vaultPassword)
                            .font(.mng(12, weight: .semibold))
                            .foregroundStyle(Palette.text2)

                        SecureField(
                            Strings.vaultPasswordPlaceholder,
                            text: $password
                        )
                        .textContentType(.password)
                        .focused($isFocused)
                        .submitLabel(.go)
                        .onSubmit { Task { await remove() } }
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

                    if !state.operationError.isEmpty {
                        Text(state.operationError)
                            .font(.mng(12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button(Strings.cancel) { dismiss() }
                            .font(.mng(15, weight: .semibold))
                            .foregroundStyle(Palette.text2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                Palette.fill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .buttonStyle(.plain)

                        Button {
                            Task { await remove() }
                        } label: {
                            HStack(spacing: 8) {
                                if state.isWorking {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "trash")
                                        .font(.mng(13, weight: .semibold))
                                }
                                Text(state.isWorking ? Strings.vaultDeleting : Strings.delete)
                                    .font(.mng(15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                Palette.danger,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isWorking)
                        .opacity(state.isWorking ? 0.7 : 1)
                    }

                    Text(Strings.vaultDeleteHint)
                        .font(.mng(11))
                        .foregroundStyle(Palette.text4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.vaultDeleteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            isFocused = true
        }
    }

    private func remove() async {
        let secret = password
        password = ""
        isFocused = false
        let deleted = await state.deleteVault(vault, password: secret)
        if deleted {
            dismiss()
        }
    }
}
