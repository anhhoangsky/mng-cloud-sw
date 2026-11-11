import Foundation

/// The file name rules the indexer uses.
///
/// The Rust worker (`crates/mng-core/src/names.rs`) derives the capture date
/// from a file name and falls back to the modification time. The app needs the
/// same value for the upload dedupe pre-check, otherwise the client would
/// report "not in the library" for a photo the worker already indexed.
///
/// The patterns are tried in the same order as the worker, so a name can
/// never mean two different dates.
public enum MNGNames {
    /// `IMG_20220910_183859`, `VID-20220910-183859`, `Screenshot_…`, …
    private static let namedPattern =
        "(?i)(?:IMG|VID|PXL|MVIMG|Screenshot|Screen)[_-](\\d{4})(\\d{2})(\\d{2})[_-](\\d{2})(\\d{2})(\\d{2})"
    /// `2022-09-10 18.38.59` and the `2022.09.10_18-38-59` variants.
    private static let separatedPattern =
        "(\\d{4})[-_.](\\d{2})[-_.](\\d{2})[ T_-](\\d{2})[-_.:](\\d{2})[-_.:](\\d{2})"
    /// `22-09-10 18-38-59`: the two digit year means 20xx.
    private static let shortPattern =
        "(\\d{2})-(\\d{2})-(\\d{2})[ _](\\d{2})-(\\d{2})-(\\d{2})"
    /// `20220910_183859`, but only when no digit touches the match.
    private static let compactPattern =
        "(\\d{4})(\\d{2})(\\d{2})[_-](\\d{2})(\\d{2})(\\d{2})"

    /// The capture date of a media file, as a Unix timestamp.
    ///
    /// The timestamp is a UTC epoch that represents local wall-clock time,
    /// exactly like the worker stores it. A file name wins over the
    /// modification time; when neither carries a date the result is `0`.
    public static func takenAt(from name: String, mtime: Int64 = 0) -> Int64 {
        let decoded = name.removingPercentEncoding ?? name

        let patterns: [(String, Bool)] = [
            (namedPattern, false),
            (separatedPattern, false),
            (shortPattern, true)
        ]
        for (pattern, shortYear) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = firstMatch(regex, in: decoded) else { continue }
            if let timestamp = timestamp(match, in: decoded, shortYear: shortYear) {
                return timestamp
            }
        }

        // The compact form is the last one the worker tries. A match that
        // touches another digit is not a date, and a boundary-valid match with
        // an impossible date falls back to the modification time instead of
        // letting a later number in the same name win.
        if let regex = try? NSRegularExpression(pattern: compactPattern) {
            for match in regex.matches(in: decoded, range: fullRange(decoded)) {
                guard !touchesDigitBoundary(match, in: decoded) else { continue }
                if let timestamp = timestamp(match, in: decoded, shortYear: false) {
                    return timestamp
                }
                break
            }
        }

        return mtime > 0 ? mtime : 0
    }

    /// The capture date of a photo, as the server stores it.
    ///
    /// The server keeps the capture date as a UTC epoch that carries the
    /// local wall-clock time, exactly like a date in a file name does. A
    /// phone names its photos `IMG_1234.HEIC`, so the name carries no date
    /// and the app has to send the capture date itself; otherwise the photo
    /// is filed under the time of the upload.
    ///
    /// The date is read in the device's own time zone, so the photo lands
    /// on the day the user took it.
    public static func captureTimestamp(from date: Date) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard let year = parts.year,
              let month = parts.month,
              let day = parts.day
        else {
            return 0
        }
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        guard (1990...2037).contains(year),
              (1...12).contains(month),
              day >= 1,
              day <= daysInMonth(year: year, month: month),
              hour <= 23,
              minute <= 59,
              second <= 59
        else {
            return 0
        }
        return daysFromCivil(year: year, month: month, day: day) * 86_400
            + hour * 3_600
            + minute * 60
            + second
    }

    /// The file name without its extension.
    public static func stem(of name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? name : base
    }

    // MARK: - Helpers

    private static func fullRange(_ value: String) -> NSRange {
        NSRange(location: 0, length: (value as NSString).length)
    }

    private static func firstMatch(
        _ regex: NSRegularExpression,
        in value: String
    ) -> NSTextCheckingResult? {
        regex.firstMatch(in: value, options: [], range: fullRange(value))
    }

    /// True when a digit sits directly before or after the match.
    private static func touchesDigitBoundary(
        _ match: NSTextCheckingResult,
        in value: String
    ) -> Bool {
        let text = value as NSString
        let whole = match.range
        guard whole.location != NSNotFound else { return false }
        if whole.location > 0, isDigit(text.character(at: whole.location - 1)) {
            return true
        }
        let end = whole.location + whole.length
        if end < text.length, isDigit(text.character(at: end)) {
            return true
        }
        return false
    }

    private static func isDigit(_ value: unichar) -> Bool {
        value >= 48 && value <= 57
    }

    /// Validate the six captured numbers and turn them into a timestamp.
    private static func timestamp(
        _ match: NSTextCheckingResult,
        in value: String,
        shortYear: Bool
    ) -> Int64? {
        let text = value as NSString
        var parts = [Int64](repeating: 0, count: 6)
        for index in 0..<6 {
            let range = match.range(at: index + 1)
            guard range.location != NSNotFound else { return nil }
            guard let parsed = Int64(text.substring(with: range)) else { return nil }
            parts[index] = parsed
        }

        var year = parts[0]
        let month = parts[1]
        let day = parts[2]
        let hour = parts[3]
        let minute = parts[4]
        let second = parts[5]
        if shortYear {
            year += 2000
        }
        guard (1990...2037).contains(year),
              (1...12).contains(month),
              day >= 1,
              day <= daysInMonth(year: year, month: month),
              hour <= 23,
              minute <= 59,
              second <= 59
        else {
            return nil
        }
        return daysFromCivil(year: year, month: month, day: day) * 86_400
            + hour * 3_600
            + minute * 60
            + second
    }

    private static func daysInMonth(year: Int64, month: Int64) -> Int64 {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            return leap ? 29 : 28
        default:
            return 0
        }
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date.
    ///
    /// The same `days_from_civil` the worker uses, so both sides agree without
    /// a calendar or a time zone.
    private static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let monthShift = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthShift + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
