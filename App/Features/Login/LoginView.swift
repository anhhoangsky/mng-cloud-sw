import MNGKit
import SwiftUI

/// Login card matching `ui/src/components/login.rs`, with the native-only
/// server field added above the credentials.
struct LoginView: View {
    @Bindable var store: SessionStore
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case server
        case username
        case password
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            ScrollView {
                card
                    .frame(maxWidth: 440)
                    .padding(.horizontal, Tokens.Spacing.xl)
                    .padding(.vertical, Tokens.Spacing.xl)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            focused = store.serverText.isEmpty ? .server : .username
        }
    }

    private var card: some View {
        VStack(spacing: Tokens.Spacing.m) {
            AppMark(size: 64)
                .padding(.top, Tokens.Spacing.xs)

            Text(Strings.appName)
                .font(.mng(28, weight: .semibold))
                .foregroundStyle(Palette.text)

            Text(Strings.loginSubtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: Tokens.Spacing.m) {
                labeledField(Strings.loginServer, for: "loginServer") {
                    TextField(Strings.loginServerPlaceholder, text: $store.serverText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focused = .username }
                }

                labeledField(Strings.loginUsername, for: "loginUsername") {
                    TextField(Strings.loginUsernamePlaceholder, text: $store.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }

                labeledField(Strings.loginPassword, for: "loginPassword") {
                    SecureField(Strings.loginPasswordPlaceholder, text: $store.password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }
            }
            .padding(.top, Tokens.Spacing.s)

            Text(store.loginError ?? " ")
                .font(.footnote)
                .foregroundStyle(Palette.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 18)

            submitButton

            VStack(spacing: 2) {
                Text(Strings.loginFootServer)
                Text(Strings.loginFootPrivacy)
            }
            .font(.caption)
            .foregroundStyle(Palette.textMuted)
            .multilineTextAlignment(.center)
            .padding(.top, Tokens.Spacing.xs)
        }
        .padding(Tokens.Spacing.xl)
        .background(Palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: Tokens.Spacing.s) {
                if store.isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.accentInk)
                }
                Text(store.isLoggingIn ? Strings.loginOpening : Strings.loginSubmit)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Palette.accent)
        .foregroundStyle(Palette.accentInk)
        .disabled(store.isLoggingIn)
        .accessibilityIdentifier("loginSubmit")
    }

    private func labeledField<Content: View>(
        _ label: String,
        for id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.textMuted)
            content()
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, 11)
                .background(
                    Palette.fill,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 1)
                }
                .accessibilityIdentifier(id)
        }
    }

    private func submit() {
        guard !store.isLoggingIn else { return }
        focused = nil
        Task { @MainActor in
            await store.login()
            switch store.loginErrorField {
            case .server:
                focused = .server
            case .username:
                focused = .username
            case .password:
                focused = .password
            case nil:
                break
            }
        }
    }
}

#Preview {
    LoginView(store: SessionStore())
}
