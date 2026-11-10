/// Image editing pipeline ported from `crates/mng-edit`.
///
/// Geometry order is rotate → flip → crop; adjustments and filters are applied
/// to the oriented pixels before encoding JPEG/PNG/WebP.
public enum MNGEditInfo {
    public static let version = "0.1.0"
}
