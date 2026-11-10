import MNGKit
import SwiftUI

/// Minimal settings screen for phase 3. It keeps the PWA's account/server
/// information and the logout path reachable; storage tools arrive with the
/// settings phase.
struct SettingsView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !isCompact {
                    Text(Strings.navSettings)
                        .font(.system(size: 38, weight: .semibold))
                        .tracking(-0.03)
                        .foregroundStyle(Palette.text)
                        .padding(.bottom, 2)
                }

                accountCard
                serverCard
                cacheCard
                versionCard

                Text(Strings.settingsNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text4)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, isCompact ? 16 : 0)
            .padding(.top, isCompact ? 6 : 28)
            .padding(.bottom, isCompact ? 140 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var accountCard: some View {
        settingsCard(Strings.accountSection) {
            row(Strings.displayName, value: displayName)
            divider
            row(Strings.username, value: model.store.session?.me.username ?? "")
            divider
            Button {
                Task { await model.logout() }
            } label: {
                HStack {
                    Text(model.isLoggingOut ? Strings.signingOut : Strings.logout)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.danger)
                    Spacer()
                    if model.isLoggingOut {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoggingOut)
        }
    }

    private var serverCard: some View {
        settingsCard(Strings.serverSection) {
            row(Strings.serverAddress, value: model.server.origin)
            divider
            row(Strings.activeCloudLabel, value: model.activeCloudLabel)
            if let free = model.storageFreeText {
                divider
                row(Strings.storageFree, value: free)
            }
            divider
            Button {
                if let url = URL(string: model.server.origin) {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                    Text(Strings.serverOpen)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text4)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var cacheCard: some View {
        settingsCard(Strings.cacheSection) {
            Button {
                model.clearThumbnails()
                model.notify(Strings.thumbnailsCleared)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                    Text(Strings.clearThumbnails)
                    Spacer()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var versionCard: some View {
        settingsCard(Strings.versionSection) {
            row(Strings.appVersion, value: model.appVersion)
            divider
            row(
                Strings.buildLabel,
                value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            )
        }
    }

    private var displayName: String {
        let name = model.store.session?.me.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? model.store.session?.me.username ?? "" : name
    }

    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.06)
                .foregroundStyle(Palette.text4)
                .padding(.horizontal, 16)
                .padding(.bottom, 7)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .background(Palette.bgElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Palette.text3)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .frame(minHeight: 44)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
    }
}
