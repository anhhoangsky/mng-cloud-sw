/// Shared primitives for the MNG Cloud client.
///
/// Phase 1 adds the Seafile E2EE engine (`e2ee.rs`) and the native
/// `mng-vault/v1` engine (`vault.rs`) here. The JSON vectors under
/// `Tests/MNGCoreTests/Fixtures` are copied verbatim from
/// `mng-cloud-rs/crates/mng-core/tests/fixtures` and are the parity gate for
/// every crypto change.
public enum MNGCoreInfo {
    public static let version = "0.1.0"
}
