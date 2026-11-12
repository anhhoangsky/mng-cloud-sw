import MNGKit
import SwiftUI

/// Rename one account.
///
/// The web console renames an account in a sheet with a text field, so the
/// same is done here.
struct AdminRenameSheet: View {
    let model: ShellModel
    let user: AdminUser

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String

    private var admin: AdminModel { model.admin }

    init(model: ShellModel, user: AdminUser) {
        self.model = model
        self.user = user
        _displayName = State(initialValue: user.displayName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Strings.adminDisplayName)
                            .font(Font.mng(12, weight: .semibold))
                            .foregroundStyle(Palette.text2)

                        TextField(Strings.adminDisplayName, text: $displayName)
                            .textInputAutocapitalization(.words)
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

                    if !admin.error.isEmpty {
                        Text(admin.error)
                            .font(Font.mng(12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await rename() }
                    } label: {
                        HStack(spacing: 8) {
                            if admin.isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(Font.mng(14, weight: .semibold))
                            }
                            Text(Strings.adminSave)
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
                    .disabled(admin.isWorking)
                    .opacity(admin.isWorking ? 0.7 : 1)
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.adminRenameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func rename() async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        await admin.rename(name, for: user)
        dismiss()
    }
}
