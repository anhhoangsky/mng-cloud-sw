import MNGKit
import SwiftUI

/// Create one folder inside the unlocked vault.
struct VaultFolderSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var state: VaultModel { model.vault }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Strings.vaultFolderPath(state.folderPath(state.folder)))
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(Strings.vaultFolderName)
                            .font(Font.mng(12, weight: .semibold))
                            .foregroundStyle(Palette.text2)

                        TextField(
                            Strings.vaultFolderPlaceholder,
                            text: $name
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit { Task { await create() } }
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
                            .font(Font.mng(12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await create() }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "folder.badge.plus")
                                    .font(Font.mng(14, weight: .semibold))
                            }
                            Text(
                                state.isWorking
                                    ? Strings.vaultFolderCreating
                                    : Strings.vaultCreateFolder
                            )
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
                    .disabled(state.isWorking)
                    .opacity(state.isWorking ? 0.7 : 1)
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.vaultCreateFolder)
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
            isFocused = true
        }
    }

    private func create() async {
        let created = await state.createFolder(name: name)
        if created {
            name = ""
            dismiss()
        }
    }
}
