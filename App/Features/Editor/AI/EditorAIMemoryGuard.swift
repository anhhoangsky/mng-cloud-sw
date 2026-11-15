import Foundation

/// Decides whether a model may load right now.
///
/// The thresholds are advisory, not a guarantee: iOS can change the limit at
/// any time. The pass therefore still keeps Vision as the final fallback and
/// the editor unloads the model on a memory warning.
enum EditorAIMemoryGuard {
    static var availableMB: Int {
        let bytes = os_proc_available_memory()
        // The call can report 0 when the process limit is unknown (the
        // simulator, for one). Treat that as "no evidence" instead of
        // blocking every model load.
        return bytes > 0 ? Int(bytes / 1_048_576) : Int.max
    }

    static var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    static var isLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func allows(_ descriptor: EditorAIModelDescriptor) -> Bool {
        denialReason(for: descriptor) == nil
    }

    /// A short reason for the UI and the benchmark CSV. The checks are in
    /// priority order, and the light models stay allowed where the heavy
    /// general mattes do not.
    static func denialReason(
        for descriptor: EditorAIModelDescriptor
    ) -> String? {
        if availableMB < descriptor.minimumAvailableMB {
            return "low-memory"
        }
        if thermalState == .critical {
            return "thermal"
        }
        let isLight = descriptor.tier == .balanced
            || descriptor.tier == .retouch
        if thermalState == .serious, !isLight {
            return "thermal"
        }
        if thermalState == .fair, descriptor.tier == .maximum {
            return "thermal"
        }
        if isLowPowerMode, !isLight {
            return "low-power"
        }
        return nil
    }
}
