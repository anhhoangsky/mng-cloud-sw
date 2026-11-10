import MNGKit
import SwiftUI

/// Delete one user. The cloud data is only removed when the admin asks for it.
struct AdminDeleteSheet: View {
    let model: ShellModel
    let user: AdminUser

    @Environment(\.dismiss) private var dismiss
    @State private var deleteCloudData = false

    private var admin: AdminModel { model.admin }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Strings.adminDeleteMessage(user.username))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: $deleteCloudData) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Strings.adminDeleteCloudData)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Text(Strings.adminDeleteCloudDataHint)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Palette.danger)

                    if !admin.error.isEmpty {
                        Text(admin.error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button(Strings.cancel) { dismiss() }
                            .font(.system(size: 15, weight: .semibold))
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
                                if admin.isWorking {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                Text(Strings.adminDelete)
                                    .font(.system(size: 15, weight: .semibold))
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
                        .disabled(admin.isWorking)
                        .opacity(admin.isWorking ? 0.7 : 1)
                    }
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.adminDeleteTitle)
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

    private func remove() async {
        await admin.delete(user, deleteCloudData: deleteCloudData)
        dismiss()
    }
}
