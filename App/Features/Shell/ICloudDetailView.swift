import MNGKit
import SwiftUI

/// iCloud importer sheet: sign in with the Apple ID, answer the 2FA prompt,
/// start the import and follow the job.
struct ICloudDetailView: View {
    let model: ShellModel

    private var icloud: ICloudModel { model.icloud }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                switch icloud.state {
                case .unsupported(let message):
                    noticeCard(
                        icon: "exclamationmark.triangle",
                        tint: Palette.orange,
                        title: message,
                        body: Strings.icloudUnsupportedHint
                    )
                    retryButton
                case .unavailable(let message):
                    noticeCard(
                        icon: "wifi.slash",
                        tint: Palette.danger,
                        title: Strings.icloudCheckFailed,
                        body: message
                    )
                    retryButton
                case .unknown, .ready:
                    content
                }
            }
            .padding(16)
        }
        .task {
            await icloud.load()
            if icloud.isWorkingJob {
                icloud.startPolling()
            }
        }
        .onDisappear {
            icloud.stopPolling()
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "icloud.fill")
                .font(.mng(22, weight: .semibold))
                .foregroundStyle(Palette.icloud)
                .frame(width: 46, height: 46)
                .background(
                    Palette.icloud.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.icloudPhotos)
                    .font(.mng(17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                    Text(icloud.row.subtitle)
                        .font(.mng(12))
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var dotColor: Color {
        switch icloud.row.dot {
        case .none: Palette.text4
        case .ok: Palette.green
        case .warn: Palette.orange
        case .bad: Palette.danger
        }
    }

    private var retryButton: some View {
        Button {
            Task { await icloud.load() }
        } label: {
            HStack(spacing: 7) {
                if icloud.isLoading {
                    ProgressView().controlSize(.small)
                }
                Text(Strings.retry)
            }
            .font(.mng(14, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                Palette.accentSoft,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(icloud.isLoading)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !icloud.actionError.isEmpty {
            noticeCard(
                icon: "exclamationmark.triangle",
                tint: Palette.danger,
                title: Strings.icloudActionFailed,
                body: icloud.actionError
            )
        }

        if !icloud.isAuthenticated {
            loginCard
        }

        if icloud.needsMFA {
            mfaCard
        }

        if icloud.isAuthenticated {
            settingsCard
            startButton
        }

        if let job = icloud.job {
            jobCard(job)
        }

        if icloud.isAuthenticated {
            logoutButton
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.icloudLoginTitle)
                .font(.mng(14, weight: .semibold))
                .foregroundStyle(Palette.text)

            field(
                Strings.icloudAppleID,
                text: Binding(
                    get: { icloud.appleID },
                    set: { icloud.appleID = $0 }
                ),
                placeholder: Strings.icloudAppleIDPlaceholder,
                isSecure: false
            )

            field(
                Strings.icloudPassword,
                text: Binding(
                    get: { icloud.password },
                    set: { icloud.password = $0 }
                ),
                placeholder: Strings.icloudPasswordPlaceholder,
                isSecure: true
            )

            Button {
                Task { await icloud.login() }
            } label: {
                HStack(spacing: 8) {
                    if icloud.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.mng(14, weight: .semibold))
                    }
                    Text(Strings.icloudLogin)
                        .font(.mng(15, weight: .semibold))
                }
                .foregroundStyle(Palette.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Palette.accent,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(icloud.isWorking || icloud.appleID.isEmpty)
            .opacity(icloud.isWorking ? 0.7 : 1)
        }
        .card()
    }

    private var mfaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.icloudMFA)
                .font(.mng(14, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text(Strings.icloudMFAHint)
                .font(.mng(12))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)

            field(
                Strings.icloudMFA,
                text: Binding(
                    get: { icloud.mfaCode },
                    set: { icloud.mfaCode = $0 }
                ),
                placeholder: Strings.icloudMFAPlaceholder,
                isSecure: false
            )
            .keyboardType(.numberPad)

            Button {
                Task { await icloud.submitMFA() }
            } label: {
                HStack(spacing: 8) {
                    if icloud.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(Strings.icloudSendMFA)
                        .font(.mng(15, weight: .semibold))
                }
                .foregroundStyle(Palette.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Palette.accent,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(icloud.isWorking || icloud.mfaCode.count != 6)
            .opacity(icloud.isWorking ? 0.7 : 1)
        }
        .card()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.icloudRecent)
                .font(.mng(13, weight: .semibold))
                .foregroundStyle(Palette.text2)

            Picker(
                Strings.icloudRecent,
                selection: Binding(
                    get: { icloud.recent },
                    set: { icloud.recent = $0 }
                )
            ) {
                ForEach([50, 200, 500, 1000], id: \.self) { value in
                    Text("\(value) ảnh").tag(Int64(value))
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: Binding(
                get: { icloud.deleteAfter },
                set: { icloud.deleteAfter = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.icloudDeleteAfter)
                        .font(.mng(14, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(Strings.icloudDeleteAfterHint)
                        .font(.mng(12))
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.accent)

            Button {
                Task { await icloud.save() }
            } label: {
                Text(Strings.icloudSaveSettings)
                    .font(.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Palette.accentSoft,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(icloud.isWorking)
        }
        .card()
    }

    private var startButton: some View {
        Button {
            Task { await icloud.start() }
        } label: {
            HStack(spacing: 8) {
                if icloud.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.mng(14, weight: .semibold))
                }
                Text(Strings.icloudStart)
                    .font(.mng(15, weight: .semibold))
            }
            .foregroundStyle(Palette.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Palette.accent,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(icloud.isWorking || icloud.isWorkingJob)
        .opacity(icloud.isWorkingJob ? 0.6 : 1)
    }

    private func jobCard(_ job: IcloudJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ICloudModel.jobStateLabel(job.state))
                    .font(.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                if job.imported > 0 {
                    Text(Strings.icloudImported(job.imported))
                        .font(.mng(12, weight: .medium))
                        .foregroundStyle(Palette.text3)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.fill)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(min(max(job.progress, 0), 1))
                        )
                }
            }
            .frame(height: 5)

            if !job.message.isEmpty {
                Text(job.message)
                    .font(.mng(12))
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !job.error.isEmpty {
                Text(job.error)
                    .font(.mng(12, weight: .medium))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if job.isActive {
                HStack(spacing: 8) {
                    jobButton(Strings.icloudPause, icon: "pause") {
                        Task { await icloud.control("pause") }
                    }
                    jobButton(Strings.icloudResume, icon: "play") {
                        Task { await icloud.control("resume") }
                    }
                    jobButton(Strings.icloudCancel, icon: "stop", tint: Palette.danger) {
                        Task { await icloud.control("cancel") }
                    }
                }
            }

            if !job.log.isEmpty {
                DisclosureGroup(Strings.icloudLog) {
                    Text(job.log)
                        .font(.mng(11, design: .monospaced))
                        .foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.mng(12, weight: .semibold))
                .foregroundStyle(Palette.text2)
            }
        }
        .card()
    }

    private func jobButton(
        _ title: String,
        icon: String,
        tint: Color = Palette.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.mng(12, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private var logoutButton: some View {
        Button {
            Task { await icloud.logout() }
        } label: {
            HStack(spacing: 8) {
                if icloud.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.mng(13, weight: .semibold))
                }
                Text(Strings.icloudLogout)
                    .font(.mng(14, weight: .semibold))
            }
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                Palette.dangerSoft,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(icloud.isWorking)
    }

    // MARK: - Building blocks

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
                        .textContentType(.password)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                Palette.bgGrouped,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
        }
    }

    private func noticeCard(
        icon: String,
        tint: Color,
        title: String,
        body: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.mng(15, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
            Text(body)
                .font(.mng(12))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }
}

private extension View {
    /// Card chrome used by the iCloud sheet.
    func card() -> some View {
        padding(12)
            .background(
                Palette.bgElevated,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
    }
}
