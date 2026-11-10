import MNGKit
import SwiftUI

/// Create one encrypted vault. The password never leaves the device: it only
/// derives the PBKDF2 key that encrypts the verifier and the manifest.
struct VaultCreateSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var focused: Field?

    private enum Field {
        case name
        case password
        case confirmation
    }

    private var state: VaultModel { model.vault }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Strings.vaultCreateBody)
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)

                    field(
                        Strings.vaultName,
                        text: $name,
                        placeholder: Strings.vaultNamePlaceholder,
                        isSecure: false,
                        field: .name
                    )

                    field(
                        Strings.vaultPassword,
                        text: $password,
                        placeholder: Strings.vaultPasswordPlaceholder,
                        isSecure: true,
                        field: .password
                    )

                    field(
                        Strings.vaultConfirmPassword,
                        text: $confirmation,
                        placeholder: Strings.vaultPasswordPlaceholder,
                        isSecure: true,
                        field: .confirmation
                    )

                    if !state.unlockError.isEmpty {
                        Text(state.unlockError)
                            .font(Font.mng(12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await create() }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isUnlocking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                                    .font(Font.mng(14, weight: .semibold))
                            }
                            Text(state.isUnlocking ? Strings.vaultCreating : Strings.vaultCreate)
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

                    Text(Strings.vaultCreateHint)
                        .font(Font.mng(11))
                        .foregroundStyle(Palette.text4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.vaultCreateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        isSecure: Bool,
        field target: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Font.mng(12, weight: .semibold))
                .foregroundStyle(Palette.text2)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .textContentType(.newPassword)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .focused($focused, equals: target)
            .submitLabel(.next)
            .onSubmit { focusNext(target) }
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
    }

    private func focusNext(_ target: Field) {
        switch target {
        case .name: focused = .password
        case .password: focused = .confirmation
        case .confirmation: focused = nil
        }
    }

    private func create() async {
        let created = await state.createVault(
            name: name,
            password: password,
            confirmation: confirmation
        )
        if created {
            password = ""
            confirmation = ""
            dismiss()
        }
    }
}
