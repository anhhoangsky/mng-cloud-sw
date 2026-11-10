/// Legacy search folding shared by the scanner, writer and client.
///
/// Mirrors `crates/mng-core/src/search.rs`: lowercase, strip Vietnamese
/// diacritics, drop Unicode nonspacing marks (`Mn`), collapse every run of
/// non-letter/non-number scalars to one space.
public enum SearchFold {
    /// PHP `rawurldecode()`: decode `%XX` but leave `+` alone.
    public static func rawurldecode(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var output = [UInt8]()
        output.reserveCapacity(bytes.count)

        var index = 0
        while index < bytes.count {
            if bytes[index] == 37, index + 2 < bytes.count,
               let high = hex(bytes[index + 1]),
               let low = hex(bytes[index + 2]) {
                output.append((high << 4) | low)
                index += 3
                continue
            }
            output.append(bytes[index])
            index += 1
        }

        return String(decoding: output, as: UTF8.self)
    }

    /// Legacy `search_fold()`.
    public static func fold(_ value: String) -> String {
        // Rust lowercases one `char` at a time (`char::to_lowercase`), which
        // uses the unconditional mapping Σ -> σ. Foundation applies the
        // context-sensitive Final_Sigma rule to `String.lowercased()`, so the
        // single-scalar string "Σ" would become "ς" instead. Special-case it
        // to keep the fold byte-identical to the Rust writer.
        var lowered = String()
        for scalar in value.unicodeScalars {
            if scalar == "\u{03A3}" {
                lowered += "\u{03C3}"
            } else {
                lowered += String(scalar).lowercased()
            }
        }

        var cleaned = String()
        for scalar in lowered.unicodeScalars {
            let folded = foldScalar(scalar)
            if folded.properties.generalCategory == .nonspacingMark {
                continue
            }
            if isLetterOrNumber(folded) {
                cleaned.append(String(folded))
            } else {
                cleaned.append(" ")
            }
        }

        return cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Legacy `item_search_text()`. Places are ordered by the caller as road,
    /// ward, district, province, display label.
    public static func itemSearchText(
        name: String,
        stem: String,
        path: String,
        places: [String]
    ) -> String {
        var value = "\(name) \(stem) \(rawurldecode(path))"
        for place in places {
            value.append(" ")
            value.append(place)
        }
        return fold(value)
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57:
            return byte - 48
        case 97...102:
            return byte - 97 + 10
        case 65...70:
            return byte - 65 + 10
        default:
            return nil
        }
    }

    private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
             .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func foldScalar(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0x0061, 0x00E0, 0x00E1, 0x1EA3, 0x00E3, 0x1EA1,
             0x0103, 0x1EB1, 0x1EAF, 0x1EB3, 0x1EB5, 0x1EB7,
             0x00E2, 0x1EA7, 0x1EA5, 0x1EA9, 0x1EAB, 0x1EAD:
            return "a"
        case 0x0065, 0x00E8, 0x00E9, 0x1EBB, 0x1EBD, 0x1EB9,
             0x00EA, 0x1EC1, 0x1EBF, 0x1EC3, 0x1EC5, 0x1EC7:
            return "e"
        case 0x0069, 0x00EC, 0x00ED, 0x1EC9, 0x0129, 0x1ECB:
            return "i"
        case 0x006F, 0x00F2, 0x00F3, 0x1ECF, 0x00F5, 0x1ECD,
             0x00F4, 0x1ED3, 0x1ED1, 0x1ED5, 0x1ED7, 0x1ED9,
             0x01A1, 0x1EDD, 0x1EDB, 0x1EDF, 0x1EE1, 0x1EE3:
            return "o"
        case 0x0075, 0x00F9, 0x00FA, 0x1EE7, 0x0169, 0x1EE5,
             0x01B0, 0x1EEB, 0x1EE9, 0x1EED, 0x1EEF, 0x1EF1:
            return "u"
        case 0x0079, 0x1EF3, 0x00FD, 0x1EF7, 0x1EF9, 0x1EF5:
            return "y"
        case 0x0064, 0x0111:
            return "d"
        default:
            return scalar
        }
    }
}
