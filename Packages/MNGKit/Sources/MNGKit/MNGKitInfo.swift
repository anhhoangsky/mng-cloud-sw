/// Typed client for the `mngd` `/api/v1` contract (phase 2).
///
/// The session is a server-set HttpOnly cookie; mutations carry the
/// `X-CSRF-Token` returned by `POST /auth/login` or `GET /auth/me`.
public enum MNGKitInfo {
    public static let version = "0.1.0"
}
