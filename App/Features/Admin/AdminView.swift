import MNGKit
import SwiftUI

/// Administration console, ported from the web `AdminView`.
///
/// The layout follows the native shell in `mng-cloud-rs`: a summary row, then
/// one row per account with the account name, its role and size, its cloud
/// accounts and the actions of the account. The actions are the same set the
/// server exposes: rescan the library, hand out a new password, lock or
/// unlock the account, grant or revoke the admin role and delete it.
struct AdminView: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var passwordAction: PasswordAction?
    @State private var password = ""
    /// Whether the cloud account is given a new password as well.
    @State private var syncCloud = true
    @State private var deleting: AdminUser?
    @State private var renaming: AdminUser?

    private enum PasswordAction: Identifiable {
        case reset(AdminUser)

        var id: String {
            switch self {
            case .reset(let user): return "reset-\(user.id)"
            }
        }

        var user: AdminUser {
            switch self {
            case .reset(let user): return user
            }
        }

        var title: String {
            Strings.adminResetPassword
        }

        var message: String {
            Strings.adminResetMessage(user.username)
        }
    }

    private var admin: AdminModel { model.admin }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !admin.notice.isEmpty {
                        noticeBar(icon: "checkmark.circle.fill", tint: Palette.green, message: admin.notice)
                    }

                    if !admin.error.isEmpty {
                        noticeBar(icon: "exclamationmark.triangle.fill", tint: Palette.danger, message: admin.error)
                    }

                    if !admin.cloudPassword.isEmpty {
                        cloudPasswordCard
                    }

                    content
                }
                .padding(16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.adminTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .disabled(admin.isWorking)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await admin.load()
        }
        .sheet(isPresented: $isCreating) {
            AdminCreateSheet(model: model)
        }
        .sheet(item: $deleting) { user in
            AdminDeleteSheet(model: model, user: user)
        }
        .sheet(item: $renaming) { user in
            AdminRenameSheet(model: model, user: user)
        }
        .alert(
            passwordAction?.title ?? "",
            isPresented: Binding(
                get: { passwordAction != nil },
                set: { if !$0 { passwordAction = nil } }
            ),
            presenting: passwordAction
        ) { action in
            Button(Strings.cancel, role: .cancel) {
                password = ""
                passwordAction = nil
            }
            Button(Strings.adminConfirm) {
                let target = action
                let secret = password
                let reprovision = syncCloud
                password = ""
                passwordAction = nil
                Task {
                    if reprovision {
                        await admin.reprovision(for: target.user, password: secret)
                    } else {
                        await admin.resetPassword(for: target.user, password: secret)
                    }
                }
            }
        } message: { action in
            VStack(alignment: .leading, spacing: 8) {
                Text(action.message)
                TextField(Strings.adminPassword, text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                // The same switch the native shell has: the cloud account gets
                // a new random password as well.
                Toggle(isOn: $syncCloud) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.adminProvision)
                            .font(Font.mng(13, weight: .semibold))
                        Text(Strings.adminProvisionHint)
                            .font(Font.mng(11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Palette.accent)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch admin.state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Strings.adminLoading).font(Font.mng(12)).foregroundStyle(Palette.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        case .failed(let message):
            noticeBar(icon: "exclamationmark.triangle.fill", tint: Palette.danger, message: message)
        case .ready:
            if admin.users.isEmpty {
                noticeBar(
                    icon: "person.2",
                    tint: Palette.text3,
                    message: Strings.adminEmpty
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(admin.users.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        }
                        row(admin.users[index])
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
    }

    /// The password of the Seafile account, handed out by the server.
    private var cloudPasswordCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.adminCloudPassword)
                .font(Font.mng(11, weight: .semibold))
                .foregroundStyle(Palette.text3)
            Text(admin.cloudPassword)
                .font(Font.mng(13, weight: .medium))
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = admin.cloudPassword
            } label: {
                Label(Strings.adminCopy, systemImage: "doc.on.doc")
                    .font(Font.mng(13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
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

    private func row(_ user: AdminUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: user.isAdmin ? "shield.fill" : "person.fill")
                    .font(Font.mng(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(
                        user.isAdmin ? Palette.accent : Palette.text3,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName.isEmpty ? user.username : user.displayName)
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    Text(subtitle(user))
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !user.active {
                    Text(Strings.adminInactive)
                        .font(Font.mng(11, weight: .semibold))
                        .foregroundStyle(Palette.danger)
                }
            }

            // The same actions as the native shell, one row of buttons.
            HStack(spacing: 16) {
                actionButton(
                    icon: "arrow.clockwise",
                    title: Strings.adminScan
                ) {
                    Task { await admin.scan(user) }
                }
                actionButton(
                    icon: "key",
                    title: Strings.adminResetPassword
                ) {
                    passwordAction = .reset(user)
                }
                actionButton(
                    icon: user.active ? "lock" : "lock.open",
                    title: user.active ? Strings.adminLockAccount : Strings.adminUnlockAccount
                ) {
                    Task { await admin.setActive(!user.active, for: user) }
                }
                actionButton(
                    icon: "shield",
                    title: user.isAdmin ? Strings.adminRevokeRole : Strings.adminGrantRole
                ) {
                    Task { await admin.setAdmin(!user.isAdmin, for: user) }
                }
                actionButton(
                    icon: "pencil",
                    title: Strings.adminRename
                ) {
                    renaming = user
                }
                actionButton(
                    icon: "trash",
                    title: Strings.adminDelete,
                    tint: Palette.danger
                ) {
                    deleting = user
                }
            }
            .padding(.leading, 41)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func actionButton(
        icon: String,
        title: String,
        tint: Color = Palette.text3,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(Font.mng(14, weight: .medium))
                    .frame(width: 30, height: 30)
                Text(title)
                    .font(Font.mng(9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint)
            .frame(width: 54)
        }
        .buttonStyle(.plain)
        .disabled(admin.isWorking)
    }

    private func subtitle(_ user: AdminUser) -> String {
        let role = user.isAdmin ? Strings.roleAdmin : Strings.roleMember
        let items = "\(MNGFormat.number(user.total)) mục"
        let size = MNGFormat.bytes(user.bytes)
        return "\(role) · \(items) · \(size)"
    }

    private func noticeBar(icon: String, tint: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(Font.mng(13, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(Font.mng(12, weight: .medium))
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
}
