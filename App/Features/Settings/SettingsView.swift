import MNGKit
import SwiftUI

/// Settings tab, ported from `SettingsView` in `shell.rs`: connections,
/// iCloud, library actions, duplicate browser, account and about.
struct SettingsView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL

    private var settings: SettingsModel { model.settings }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                connectionsSection
                icloudSection
                librarySection
                toolsSection
                accountSection
                aboutSection
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.top, isCompact ? 6 : 26)
            .padding(.bottom, isCompact ? 140 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg.ignoresSafeArea())
        .task {
            // The PWA refreshes the iCloud row whenever Settings opens; it never
            // polls in the background.
            await model.icloud.load()
        }
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        settingsSection(
            Strings.connectionsSection,
            note: Strings.settingsConnectionsNote
        ) {
            if model.clouds.isEmpty {
                SettingsRowLabel(
                    icon: "cloud",
                    tint: Palette.accent,
                    title: Strings.connecting,
                    subtitle: ""
                ) {
                    ProgressView().controlSize(.small)
                }
            } else {
                ForEach(model.clouds.indices, id: \.self) { index in
                    if index > 0 {
                        divider
                    }
                    cloudRow(model.clouds[index])
                }
                divider
            }

            Button {
                if let url = URL(string: model.server.origin) {
                    openURL(url)
                }
            } label: {
                SettingsRowLabel(
                    icon: "safari",
                    tint: Palette.seafile,
                    title: Strings.serverOpen,
                    subtitle: Strings.serverOpenBody
                ) {
                    chevron
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func cloudRow(_ cloud: CloudCard) -> some View {
        let label = cloud.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = label.isEmpty ? cloud.key : label
        let subtitle = "\(cloud.username) · \(MNGFormat.number(cloud.counts.total)) mục"
        let tint = Color.mngHex(cloud.color)
            ?? (cloud.key == "seafile" ? Palette.seafile : Palette.accent)
        return Button {
            Task { await settings.testCloud(cloud) }
        } label: {
            SettingsRowLabel(
                icon: "cloud.fill",
                tint: tint,
                title: title,
                subtitle: subtitle
            ) {
                if settings.isTesting(cloud.key) {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(Strings.cloudTesting)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.text3)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(healthColor(cloud))
                            .frame(width: 7, height: 7)
                        Text(healthText(cloud))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.text3)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(settings.isTesting(cloud.key))
    }

    private func healthColor(_ cloud: CloudCard) -> Color {
        guard let health = cloud.health else { return Palette.text4 }
        return health.ok ? Palette.green : Palette.danger
    }

    private func healthText(_ cloud: CloudCard) -> String {
        guard let health = cloud.health else { return Strings.cloudHealthUnknown }
        return health.ok ? Strings.cloudHealth(ms: health.ms) : Strings.cloudHealthBad
    }

    // MARK: - iCloud

    private var icloudSection: some View {
        settingsSection(Strings.icloudSection) {
            Button {
                model.presentICloud()
            } label: {
                SettingsRowLabel(
                    icon: "icloud",
                    tint: Palette.icloud,
                    title: Strings.icloudPhotos,
                    subtitle: model.icloud.row.subtitle
                ) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(icloudDotColor)
                            .frame(width: 7, height: 7)
                        Text(model.icloud.row.value)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.text3)
                            .lineLimit(1)
                        chevron
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var icloudDotColor: Color {
        switch model.icloud.row.dot {
        case .none: Palette.text4
        case .ok: Palette.green
        case .warn: Palette.orange
        case .bad: Palette.danger
        }
    }

    // MARK: - Library actions

    private var librarySection: some View {
        settingsSection(Strings.librarySection) {
            Button {
                model.selectTab(.vault)
            } label: {
                SettingsRowLabel(
                    icon: "lock",
                    tint: Palette.accent,
                    title: Strings.navVault,
                    subtitle: Strings.vaultRowBody
                ) {
                    chevron
                }
            }
            .buttonStyle(.plain)

            divider

            actionRow(
                icon: "arrow.clockwise",
                tint: Palette.accent,
                title: Strings.scanRowTitle,
                subtitle: settings.scanBusy ? Strings.scanBusyBody : Strings.scanRowBody,
                busy: settings.scanBusy
            ) {
                await settings.scanAll()
            }

            divider

            actionRow(
                icon: "sparkles",
                tint: Palette.orange,
                title: Strings.thumbsRowTitle,
                subtitle: settings.thumbsBusy
                    ? Strings.thumbsBusyBody
                    : Strings.thumbsRowSub(model.bootstrap?.total ?? 0),
                busy: settings.thumbsBusy
            ) {
                await settings.retryThumbs()
            }

            divider

            actionRow(
                icon: "trash",
                tint: Palette.text3,
                title: Strings.tmpRowTitle,
                subtitle: settings.tmpBusy ? Strings.tmpBusyBody : Strings.tmpRowBody,
                busy: settings.tmpBusy
            ) {
                await settings.clearTmp()
            }

            divider

            SettingsRowLabel(
                icon: "server.rack",
                tint: Palette.green,
                title: Strings.storageFree,
                subtitle: Strings.storageServerBody
            ) {
                Text(storageFreeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text3)
            }
        }
    }

    private var storageFreeText: String {
        let free = model.bootstrap?.storage.free ?? 0
        return MNGFormat.bytes(Int64(clamping: free))
    }

    private func actionRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        busy: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            SettingsRowLabel(
                icon: icon,
                tint: tint,
                title: title,
                subtitle: subtitle
            ) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    chevron
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - Tools

    private var toolsSection: some View {
        settingsSection(Strings.toolsSection) {
            Button {
                model.presentDuplicates()
            } label: {
                SettingsRowLabel(
                    icon: "magnifyingglass",
                    tint: Palette.accent,
                    title: Strings.duplicatesRowTitle,
                    subtitle: Strings.duplicatesRowBody
                ) {
                    chevron
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        settingsSection(Strings.accountSection) {
            SettingsRowLabel(
                icon: "shield",
                tint: Palette.text3,
                title: displayName,
                subtitle: accountSubtitle
            ) {
                EmptyView()
            }

            divider

            Button {
                Task { await model.logout() }
            } label: {
                SettingsRowLabel(
                    icon: "rectangle.portrait.and.arrow.right",
                    tint: Palette.danger,
                    title: model.isLoggingOut ? Strings.signingOut : Strings.logout,
                    subtitle: Strings.accountLogoutBody
                ) {
                    if model.isLoggingOut {
                        ProgressView().controlSize(.small)
                    } else {
                        EmptyView()
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isLoggingOut)
        }
    }

    private var displayName: String {
        model.store.session?.me.label ?? ""
    }

    private var accountSubtitle: String {
        let username = model.store.session?.me.username ?? ""
        let role = model.store.session?.me.isAdmin == true
            ? Strings.roleAdmin
            : Strings.roleMember
        return "\(username) · \(role)"
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Strings.aboutSection.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.06)
                .foregroundStyle(Palette.text4)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("MNG Cloud \(model.appVersion)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(Strings.settingsAboutBody)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Building blocks

    private func settingsSection<Content: View>(
        _ title: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.06)
                .foregroundStyle(Palette.text4)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .background(
                Palette.bgElevated,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }

            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.text4)
    }
}

/// Shared row chrome: tinted icon, title/subtitle and a trailing value.
private struct SettingsRowLabel<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(
                    tint,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
