import MNGKit
import SwiftUI

/// Administration console, ported from the web `AdminView`.
struct AdminView: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var passwordAction: PasswordAction?
    @State private var password = ""
    @State private var deleting: AdminUser?

    private enum PasswordAction: Identifiable {
        case reset(AdminUser)
        case reprovision(AdminUser)

        var id: String {
            switch self {
            case .reset(let user): return "reset-\(user.id)"
            case .reprovision(let user): return "reprovision-\(user.id)"
            }
        }

        var title: String {
            switch self {
            case .reset: return Strings.adminResetPassword
            case .reprovision: return Strings.adminReprovision
            }
        }

        var message: String {
            switch self {
            case .reset(let user):
                return Strings.adminResetMessage(user.username)
            case .reprovision(let user):
                return Strings.adminReprovisionMessage(user.username)
            }
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
                password = ""
                passwordAction = nil
                Task {
                    switch target {
                    case .reset(let user):
                        await admin.resetPassword(for: user, password: secret)
                    case .reprovision(let user):
                        await admin.reprovision(for: user, password: secret)
                    }
                }
            }
        } message: { action in
            VStack(alignment: .leading, spacing: 8) {
                Text(action.message)
                TextField(Strings.adminPassword, text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

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

    private func row(_ user: AdminUser) -> some View {
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
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                Task { await admin.setActive(!user.active, for: user) }
            } label: {
                Label(
                    user.active ? Strings.adminLockAccount : Strings.adminUnlockAccount,
                    systemImage: user.active ? "lock" : "lock.open"
                )
            }
            Button {
                Task { await admin.setAdmin(!user.isAdmin, for: user) }
            } label: {
                Label(
                    user.isAdmin ? Strings.adminRevokeRole : Strings.adminGrantRole,
                    systemImage: "shield"
                )
            }
            Button {
                Task { await admin.scan(user) }
            } label: {
                Label(Strings.adminScan, systemImage: "arrow.clockwise")
            }
            Button {
                passwordAction = .reset(user)
            } label: {
                Label(Strings.adminResetPassword, systemImage: "key")
            }
            Button(role: .destructive) {
                deleting = user
            } label: {
                Label(Strings.adminDelete, systemImage: "trash")
            }
        }
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
