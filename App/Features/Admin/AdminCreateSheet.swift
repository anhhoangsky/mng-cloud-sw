import MNGKit
import SwiftUI

/// Create one user. The password is generated locally and can be copied, the
/// same way the web console does it.
struct AdminCreateSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = AdminPassword.generate()
    @State private var provision = true

    private var admin: AdminModel { model.admin }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field(
                        Strings.adminUsername,
                        text: $username,
                        placeholder: "anh.nguyen",
                        isSecure: false
                    )

                    field(
                        Strings.adminDisplayName,
                        text: $displayName,
                        placeholder: "Anh Nguyễn",
                        isSecure: false
                    )

                    field(
                        Strings.adminPassword,
                        text: $password,
                        placeholder: Strings.adminPasswordPlaceholder,
                        isSecure: true
                    )

                    Button {
                        password = AdminPassword.generate()
                    } label: {
                        Label(Strings.adminGeneratePassword, systemImage: "arrow.triangle.2.circlepath")
                            .font(.mng(13, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: $provision) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Strings.adminProvision)
                                .font(.mng(14, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Text(Strings.adminProvisionHint)
                                .font(.mng(12))
                                .foregroundStyle(Palette.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Palette.accent)

                    if !admin.error.isEmpty {
                        Text(admin.error)
                            .font(.mng(12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await create() }
                    } label: {
                        HStack(spacing: 8) {
                            if admin.isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "person.badge.plus")
                                    .font(.mng(14, weight: .semibold))
                            }
                            Text(Strings.adminCreate)
                                .font(.mng(15, weight: .semibold))
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
                    .disabled(admin.isWorking || username.isEmpty)
                    .opacity(admin.isWorking ? 0.7 : 1)
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.adminCreateTitle)
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
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.mng(12, weight: .semibold))
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

    private func create() async {
        let created = await admin.create(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            provision: provision
        )
        if created {
            dismiss()
        }
    }
}
