import Foundation
import Observation

/// Observable session state machine matching the PWA's `app.rs`:
/// `checking → login` or `checking → ready`, with the boot error kept while
/// the screen stays on `checking` so "Thử lại" can retry.
@MainActor
@Observable
public final class SessionStore {
    public enum Phase: Equatable, Sendable {
        case checking
        case login
        case ready
    }

    /// Which login field should regain focus after a validation/server failure.
    public enum LoginField: Equatable, Sendable {
        case server
        case username
        case password
    }

    public private(set) var phase: Phase = .checking
    public private(set) var session: Session?
    /// Origin backing the active client. Nil while logged out.
    public private(set) var server: MNGServer?
    public private(set) var bootError: String?
    public private(set) var loginError: String?
    public private(set) var loginErrorField: LoginField?
    public private(set) var logoutError: String?
    public private(set) var isLoggingIn = false
    public private(set) var isLoggingOut = false

    /// Server field on the login card. Persisted only after a successful login.
    public var serverText: String
    public var username: String
    public var password: String = ""

    public static let serverKey = "mng.server"
    public static let usernameKey = "mng.username"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clientFactory: (MNGServer) -> MNGAPIClient
    @ObservationIgnored private var client: MNGAPIClient?
    @ObservationIgnored private var didStart = false

    public init(
        defaults: UserDefaults = .standard,
        clientFactory: @escaping (MNGServer) -> MNGAPIClient = { MNGAPIClient(server: $0) }
    ) {
        self.defaults = defaults
        self.clientFactory = clientFactory

        let savedServer = defaults
            .string(forKey: Self.serverKey)
            .flatMap(MNGServer.init(string:))
        server = savedServer
        serverText = savedServer?.origin ?? ""
        username = defaults.string(forKey: Self.usernameKey) ?? ""
    }

    /// The client for the active session, used by the shell once ready.
    public var apiClient: MNGAPIClient? { client }

    /// Check the HttpOnly session once. Safe to call from `.task`.
    public func start() async {
        guard !didStart else { return }
        didStart = true
        await checkSession()
    }

    /// Boot screen "Thử lại".
    public func retry() async {
        await checkSession()
    }

    private func checkSession() async {
        phase = .checking
        bootError = nil
        loginError = nil
        loginErrorField = nil
        logoutError = nil

        guard let saved = defaults.string(forKey: Self.serverKey),
              let server = MNGServer(string: saved) else {
            client = nil
            session = nil
            self.server = nil
            phase = .login
            return
        }

        serverText = server.origin
        self.server = server
        let api = clientFactory(server)
        client = api

        do {
            let response = try await api.me()
            session = Session(response)
            phase = .ready
        } catch let error as APIError where error.status == 401 {
            await api.setCSRF(nil)
            client = nil
            session = nil
            self.server = nil
            phase = .login
        } catch let error as APIError {
            // Keep `checking` with the failure visible: the PWA does not fall
            // through to the login card when the session check itself failed.
            bootError = APIMessages.boot(error)
        } catch {
            bootError = APIMessages.boot(.network())
        }
    }

    /// Submit the login card.
    public func login() async {
        guard !isLoggingIn else { return }

        let parsed = MNGServer.parse(serverText)
        let server: MNGServer
        switch parsed {
        case .success(let value):
            server = value
        case .failure(let error):
            loginError = error.message
            loginErrorField = .server
            return
        }

        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        if name.isEmpty {
            loginError = APIMessages.usernameRequired
            loginErrorField = .username
            return
        }
        if pass.isEmpty {
            loginError = APIMessages.passwordRequired
            loginErrorField = .password
            return
        }

        loginError = nil
        loginErrorField = nil
        isLoggingIn = true

        let api = clientFactory(server)
        do {
            let response = try await api.login(username: name, password: pass)
            // Persist only successful values, like the PWA remembering the
            // username after the server accepted the password.
            defaults.set(server.origin, forKey: Self.serverKey)
            defaults.set(name, forKey: Self.usernameKey)
            username = name
            serverText = server.origin
            self.server = server
            client = api
            session = Session(response)
            password = ""
            loginErrorField = nil
            logoutError = nil
            phase = .ready
        } catch let error as APIError {
            loginError = APIMessages.login(error)
            loginErrorField = .password
        } catch {
            loginError = APIMessages.login(.network())
            loginErrorField = .password
        }

        isLoggingIn = false
    }

    /// Logout with the CSRF header, then clear the local cookie/token.
    /// A 401 means the session is already gone, so the local cleanup proceeds;
    /// other failures keep the session and surface the PWA toast copy.
    public func logout() async {
        guard !isLoggingOut,
              session != nil,
              let api = client else {
            return
        }

        isLoggingOut = true
        logoutError = nil

        do {
            try await api.logout()
        } catch let error as APIError where error.status == 401 {
            // The session cookie is already invalid; local cleanup follows.
        } catch let error as APIError {
            logoutError = APIMessages.logout(error)
            isLoggingOut = false
            return
        } catch {
            logoutError = APIMessages.logout(.network())
            isLoggingOut = false
            return
        }

        await api.clearSessionCookies()
        await api.setCSRF(nil)
        client = nil
        session = nil
        server = nil
        password = ""
        isLoggingOut = false
        phase = .login
    }

    /// Dismiss the logout failure banner/alert.
    public func clearLogoutError() {
        logoutError = nil
    }

    /// A later API call hit `401`: forget the session and show the login card.
    public func expireSession() async {
        if let api = client {
            await api.clearSessionCookies()
            await api.setCSRF(nil)
        }
        client = nil
        session = nil
        server = nil
        password = ""
        loginError = nil
        loginErrorField = nil
        bootError = nil
        phase = .login
    }

    /// Shared 401 handling for feature views.
    @discardableResult
    public func handle(_ error: APIError) async -> Bool {
        guard error.status == 401 else { return false }
        await expireSession()
        return true
    }
}
