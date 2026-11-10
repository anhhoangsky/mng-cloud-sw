import Foundation

/// Vietnamese formatting rules copied from the PWA shell.
///
/// These are deliberately locale-independent: the server renders Vietnamese
/// copy and the PWA always uses `.` thousands separators and `.` decimals.
public enum MNGFormat {
    private static let monthNames = [
        "tháng 1", "tháng 2", "tháng 3", "tháng 4", "tháng 5", "tháng 6",
        "tháng 7", "tháng 8", "tháng 9", "tháng 10", "tháng 11", "tháng 12",
    ]

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// `format_number()`: `1966` → `1.966`.
    public static func number(_ value: Int64) -> String {
        let digits = String(max(0, value))
        guard digits.count > 3 else { return digits }

        var out = ""
        out.reserveCapacity(digits.count + digits.count / 3)
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                out.append(".")
            }
            out.append(character)
        }
        return out
    }

    /// `format_bytes()`: `0 B`, `999 B`, `1.5 KB`, `2.0 GB`.
    public static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        let value = max(0, value)
        guard value > 0 else { return "0 B" }

        var size = Double(value)
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        if unit == 0 {
            return String(format: "%.0f B", locale: posix, size)
        }
        return String(format: "%.1f", locale: posix, size) + " " + units[unit]
    }

    /// `format_duration()`: rounded, always `0:00` for an unknown duration.
    public static func duration(_ value: Double) -> String {
        let total = UInt64(max(0, value.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(minutes):\(twoDigits(seconds))"
    }

    /// `formatCoord()`: `16.05441° N, 108.20217° E`.
    public static func coordinate(latitude: Double, longitude: Double) -> String {
        let northSouth = latitude >= 0 ? "N" : "S"
        let eastWest = longitude >= 0 ? "E" : "W"
        let lat = String(format: "%.5f", locale: posix, abs(latitude))
        let lng = String(format: "%.5f", locale: posix, abs(longitude))
        return "\(lat)° \(northSouth), \(lng)° \(eastWest)"
    }

    /// Timeline section title: `Tháng 11 2026`, or `Không rõ ngày`.
    public static func monthLabel(year: Int, month: Int) -> String {
        guard year != 0, month != 0 else { return "Không rõ ngày" }
        return "Tháng \(month) \(year)"
    }

    /// Legacy `dateLabel`: `5 tháng 11, 2026`.
    public static func itemDate(day: Int, month: Int, year: Int) -> String {
        guard year != 0 else { return "Không rõ ngày" }
        let clamped = min(max(month, 1), 12)
        return "\(day) \(monthNames[clamped - 1]), \(year)"
    }

    public static func itemDate(_ item: Item) -> String {
        itemDate(day: item.day, month: item.month, year: item.year)
    }

    /// Legacy `timeLabel`, rendered in UTC from the stored Unix timestamp.
    public static func time(takenAt: Int64) -> String {
        guard takenAt > 0 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: TimeInterval(takenAt))
        )
        return "\(twoDigits(parts.hour ?? 0)):\(twoDigits(parts.minute ?? 0))"
    }

    /// `today_label()`: `10 tháng 11, 2026`, in the device's local time zone.
    public static func today(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        let month = min(max(parts.month ?? 1, 1), 12)
        return "\(parts.day ?? 1) \(monthNames[month - 1]), \(parts.year ?? 0)"
    }

    /// `1920 × 1080`, or `nil` when the width is unknown.
    public static func resolution(width: Int64, height: Int64) -> String? {
        guard width > 0 else { return nil }
        return "\(width) × \(height)"
    }

    /// PWA count copy: `1.966 mục`, `1 mục`.
    public static func count(_ value: Int64) -> String {
        "\(number(value)) mục"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }

    private static func twoDigits(_ value: UInt64) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
