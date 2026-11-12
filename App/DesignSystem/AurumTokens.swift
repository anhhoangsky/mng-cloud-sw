import SwiftUI

/// The colours of the Aurum editor.
///
/// The editor of the browser has its own dark and gold identity, and the
/// app keeps it, so a photo looks the same in both.
enum Aurum {
    /// The ground of the editor.
    static let bg = Color(red: 0.031, green: 0.031, blue: 0.039)
    /// The ground of the panels.
    static let bg2 = Color(red: 0.071, green: 0.071, blue: 0.086)
    /// The glass of the buttons.
    static let glass = Color.white.opacity(0.09)
    /// The line of the glass.
    static let glassLine = Color.white.opacity(0.14)
    /// The text.
    static let text = Color(red: 0.957, green: 0.949, blue: 0.925)
    /// The quiet text.
    static let muted = Color(red: 0.561, green: 0.549, blue: 0.596)
    /// The gold of the selection.
    static let gold = Color(red: 0.953, green: 0.780, blue: 0.482)
    /// The stronger gold.
    static let goldStrong = Color(red: 0.886, green: 0.678, blue: 0.322)
    /// The soft gold of the selected chips.
    static let goldSoft = Color(red: 0.953, green: 0.780, blue: 0.482).opacity(0.15)
    /// The danger colour.
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    /// The tick of the slider.
    static let tick = Color.white.opacity(0.58)
}
