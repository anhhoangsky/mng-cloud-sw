import XCTest
@testable import MNGEdit

/// The shared filter catalog.
///
/// `specs/filters.json` is the single source of truth for the web build and
/// the phone. These tests prove that the bundled copy decodes, that every
/// `EditorFilter` still resolves to a tone, and that the final 8-bit palette
/// matches the release implementation the spec was extracted from.
final class FilterSpecTests: XCTestCase {
    private let swatches: [(name: String, rgb: (Int, Int, Int))] = [
        ("skin", (201, 143, 107)),
        ("sky", (125, 167, 201)),
        ("foliage", (77, 122, 69)),
        ("red", (179, 58, 50)),
        ("highlight", (242, 232, 214)),
        ("shadow", (11, 11, 13)),
    ]

    /// Six swatches through every tone, captured before the spec move. The
    /// web page `test-filters.html` checks the same table against the same
    /// JSON. Values are hex RGB, in swatch order.
    private let golden = """
    original        C98F6B 7DA7C9 4D7A45 B33A32 F2E8D6 0B0B0D
    vivid           E38C57 6EADDF 3C7F30 DE2A1E FFF0D5 020205
    dramatic        D9967C 88B2E8 477646 B02C2B FFFFFF 000000
    mono            9B9B9B A4A4A4 6B6B6B 4F4F4F F3F3F3 000000
    vintage         F8A874 C1BCB8 7C804D C4563A FFFFD5 18120C
    warm            E1925E 8CAAB1 567C3D C83B2C FFEDBC 0C0B0B
    cool            B58F7C 70A7E9 457A50 A13A3A DAE8F8 0A0B0F
    meitu-natural   D79163 7EABCA 4C7E3F C6382D FDEDD0 0B0B0D
    meitu-korea     DD8E62 7FA8CB 4D7C3E CD362C FFE8CF 0C0B0D
    meitu-japan     C98F6F 81A5C7 537C4B B44039 F0E2D3 151517
    meitu-skin      DB9B72 8BB4CF 59864C C44439 FFF7DC 141315
    meitu-pink      E18C5F 7EA7CB 4C7B3B D4342A FFE6CC 0C0B0D
    meitu-white     D69B76 89B4D7 55834D BC4038 FFFBE8 0C0C0E
    xingtu-film     CE936D 77B0E3 437D40 B9312A F9F9EF 000000
    xingtu-hk       D09171 82AAD5 4C7845 B3352F FFF3E9 000001
    xingtu-showa    C6906B 87A4B2 577848 A94136 F4E3C5 121111
    xingtu-kama     DA915C 81ABB9 4E7E3B C8392A FFEDBF 0C0B0C
    xingtu-night    C08E74 77A6DD 467648 A73531 ECECF0 020204
    xingtu-morning  DB9460 83AEBE 50803D C83A2C FFF1C6 0C0B0C
    lr-cinema       D3946B 78B1E3 427C3D BC2F27 FFFDEF 000000
    lr-moody        C89172 7FAAD3 477443 A6312B FDF6EE 000000
    lr-vibrant      DE8C59 70ABDC 3F7F34 D92D22 FBEDD3 050508
    lr-pastel       CC916C 7EA9CB 527F49 BC4138 EEE4D2 171719
    lr-desert       E18E58 81A8B6 4E7C37 D13628 FFE8BA 0C0B0C
    lr-street       D2936C 81AED3 47773E B22F26 FFFDEA 000000
    lr-faded        BE9176 85A5BF 597B53 A34741 E8E0D2 19191B
    lr-teal         BF946E 71AEDB 458046 AF3A32 E2F1E3 0A0B0E
    mono-warm       A29C90 AAA497 736F66 58554E F7EDDB 0C0B0A
    mono-cool       9096A2 979DAA 666A73 4E5158 DBE4F7 0A0B0C
    """

    func testTheBundledSpecDecodesTheWholeCatalog() {
        let specs = EditorFilterSpec.all
        XCTAssertEqual(specs.count, 29)
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count)
        XCTAssertEqual(
            EditorFilter.allCases.map(\.rawValue),
            specs.map(\.id),
            "the enum and the spec must stay in the same order"
        )

        var counts: [EditorFilterCategory: Int] = [:]
        for spec in specs {
            counts[spec.category, default: 0] += 1
            XCTAssertFalse(spec.name.isEmpty, spec.id)
            XCTAssertFalse(spec.nameEn.isEmpty, spec.id)
            XCTAssertEqual(spec.matrix.count, 9, spec.id)
            XCTAssertEqual(spec.offset.count, 3, spec.id)
            XCTAssertTrue(spec.matrix.allSatisfy { $0.isFinite }, spec.id)
            XCTAssertTrue(spec.offset.allSatisfy { $0.isFinite }, spec.id)
            if spec.id == "original" {
                XCTAssertTrue(spec.isIdentity)
                XCTAssertEqual(spec.css, "")
            } else {
                XCTAssertFalse(spec.css.isEmpty, spec.id)
            }
        }
        XCTAssertEqual(counts[.root] ?? 0, 6)
        XCTAssertEqual(counts[.meitu] ?? 0, 6)
        XCTAssertEqual(counts[.xingtu] ?? 0, 6)
        XCTAssertEqual(counts[.lr] ?? 0, 8)
        XCTAssertEqual(counts[.mono] ?? 0, 3)
    }

    func testEveryFilterResolvesToItsSpecTransform() {
        for filter in EditorFilter.allCases {
            guard let spec = EditorFilterSpec.filter(id: filter.rawValue) else {
                XCTFail("missing spec for \(filter.rawValue)")
                continue
            }
            if filter == .original {
                XCTAssertTrue(spec.isIdentity)
                XCTAssertNil(Editor.presetTransform(filter))
            } else {
                XCTAssertFalse(spec.isIdentity, spec.id)
                guard let transform = Editor.presetTransform(filter) else {
                    XCTFail("missing transform for \(filter.rawValue)")
                    continue
                }
                XCTAssertEqual(transform.matrix, spec.matrix, spec.id)
                XCTAssertEqual(transform.offset, spec.offset, spec.id)
            }
        }
        XCTAssertNil(EditorFilterSpec.filter(id: "sepia"))
    }

    func testTheGoldenPaletteMatchesTheWebRelease() {
        let rows = parseGolden()
        XCTAssertEqual(rows.count, 29)

        for filter in EditorFilter.allCases {
            guard let expected = rows[filter.rawValue] else {
                XCTFail("no golden row for \(filter.rawValue)")
                continue
            }
            let transform = Editor.presetTransform(filter)
            for (index, swatch) in swatches.enumerated() {
                let actual = apply(transform, to: swatch.rgb)
                let target = expected[index]
                // Swift stores the spec as Float while the browser evaluates
                // the same numbers as Double: one LSB of drift is accepted,
                // more would mean the catalog moved.
                XCTAssertLessThanOrEqual(
                    abs(actual.0 - target.0),
                    1,
                    "\(filter.rawValue) \(swatch.name) red"
                )
                XCTAssertLessThanOrEqual(
                    abs(actual.1 - target.1),
                    1,
                    "\(filter.rawValue) \(swatch.name) green"
                )
                XCTAssertLessThanOrEqual(
                    abs(actual.2 - target.2),
                    1,
                    "\(filter.rawValue) \(swatch.name) blue"
                )
            }
        }
    }

    func testLegacyKeysStillDecode() throws {
        XCTAssertEqual(try EditorFilter(key: "fade"), .lrFaded)
        XCTAssertEqual(try EditorFilter(key: "natural"), .meituNatural)
        XCTAssertEqual(try EditorFilter(key: "korea"), .meituKorea)
        XCTAssertEqual(try EditorFilter(key: "japan"), .meituJapan)
        XCTAssertEqual(try EditorFilter(key: "skin"), .meituSkin)
    }

    // MARK: - Helpers

    private func parseGolden() -> [String: [(Int, Int, Int)]] {
        var rows: [String: [(Int, Int, Int)]] = [:]
        for line in golden.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == swatches.count + 1 else {
                XCTFail("bad golden row: \(line)")
                continue
            }
            var values: [(Int, Int, Int)] = []
            for token in parts.dropFirst() {
                guard let value = hex(token) else {
                    XCTFail("bad golden colour: \(token)")
                    continue
                }
                values.append(value)
            }
            rows[String(parts[0])] = values
        }
        return rows
    }

    private func hex(_ token: Substring) -> (Int, Int, Int)? {
        guard token.count == 6, let value = UInt32(token, radix: 16) else {
            return nil
        }
        return (
            Int((value >> 16) & 0xFF),
            Int((value >> 8) & 0xFF),
            Int(value & 0xFF)
        )
    }

    private func apply(
        _ transform: Editor.PresetTransform?,
        to rgb: (Int, Int, Int)
    ) -> (Int, Int, Int) {
        guard let transform else { return rgb }
        let r = Float(rgb.0) / 255
        let g = Float(rgb.1) / 255
        let b = Float(rgb.2) / 255
        let m = transform.matrix
        let o = transform.offset
        let red = m[0] * r + m[1] * g + m[2] * b + o[0]
        let green = m[3] * r + m[4] * g + m[5] * b + o[1]
        let blue = m[6] * r + m[7] * g + m[8] * b + o[2]
        return (byte(red), byte(green), byte(blue))
    }

    private func byte(_ value: Float) -> Int {
        Int(min(max(value * 255, 0), 255).rounded())
    }
}
