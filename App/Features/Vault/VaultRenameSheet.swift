import MNGKit
import SwiftUI

/// Rename one vault. The new name is stored in the clear on the server, just
/// like the web client.
struct VaultRenameSheet: View {
    let model: ShellModel
    let vault: NativeVault

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var state: VaultModel { model.vault }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Strings.vaultName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.text2)

                        TextField(
                            Strings.vaultNamePlaceholder,
                            text: $name
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit { Task { await rename() } }
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await rename() }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text(Strings.vaultRename)
                                .font(.system(size: 15, weight: .semibold))
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
                    .disabled(state.isWorking)
                    .opacity(state.isWorking ? 0.7 : 1)
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.vaultRenameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = vault.name
            isFocused = true
        }
    }

    private func rename() async {
        if await state.rename(vault, name: name) {
            dismiss()
        }
    }
}
