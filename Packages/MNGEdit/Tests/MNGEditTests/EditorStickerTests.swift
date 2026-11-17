import XCTest
@testable import MNGEdit

final class EditorStickerTests: XCTestCase {
    private func black(width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 3, to: bytes.count, by: 4) {
            bytes[index] = 255
        }
        return bytes
    }

    func testStickerDefaultsMatchTheWebPane() {
        let sticker = EditorStickerLayer(id: "s1", glyph: "🔥")
        XCTAssertEqual(sticker.x, 0.5)
        XCTAssertEqual(sticker.y, 0.5)
        XCTAssertEqual(sticker.size, 0.24)
        XCTAssertEqual(sticker.rotation, 0)
        XCTAssertEqual(sticker.opacity, 1)
    }

    func testSanitizerKeepsEmojiSequences() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(EditorStickerSanitizer.sanitize(family), family)
        XCTAssertEqual(EditorStickerSanitizer.sanitize("👍🏽"), "👍🏽")
        XCTAssertEqual(EditorStickerSanitizer.sanitize("❤️"), "❤️")
        XCTAssertEqual(EditorStickerSanitizer.sanitize("😀\u{0}\n😎\u{7f}"), "😀😎")
        XCTAssertEqual(EditorStickerSanitizer.sanitize("   "), "")
    }

    func testSanitizerCapsAtSixteenCodePoints() {
        let long = String(repeating: "😀", count: 20)
        let clean = EditorStickerSanitizer.sanitize(long)
        XCTAssertEqual(clean.unicodeScalars.count, 16)
        XCTAssertEqual(clean, String(repeating: "😀", count: 16))
    }

    func testStickerClampsGeometryAndDropsEmptyGlyphs() throws {
        let clamped = try XCTUnwrap(
            EditorStickerLayer(
                id: "s",
                glyph: "⭐",
                x: 9,
                y: -3,
                size: 7,
                rotation: 999,
                opacity: -2
            ).normalized()
        )
        XCTAssertEqual(clamped.x, 1)
        XCTAssertEqual(clamped.y, 0)
        XCTAssertEqual(clamped.size, 1)
        XCTAssertEqual(clamped.opacity, 0)
        // The Swift layer wraps like the text layer, so the handle keeps
        // turning in the same direction instead of sticking at the limit.
        XCTAssertEqual(clamped.rotation, -81, accuracy: 0.0001)

        XCTAssertNil(EditorStickerLayer(id: "s", glyph: "   ").normalized())
    }

    func testSetLayersPreservesOrderSuffixesIdsAndCaps() throws {
        let editor = try Editor(
            width: 4,
            height: 3,
            rgba: black(width: 4, height: 3)
        )
        var copy = editor
        copy.setLayers([
            .text(EditorTextLayer(id: "dup", text: "a")),
            .sticker(EditorStickerLayer(id: "dup", glyph: "🎉")),
            .sticker(EditorStickerLayer(id: "dup", glyph: "🎀")),
        ])
        XCTAssertEqual(copy.allLayers.count, 3)
        XCTAssertEqual(copy.allLayers[0].textLayer?.text, "a")
        XCTAssertEqual(copy.allLayers[1].id, "dup-1")
        XCTAssertEqual(copy.allLayers[1].stickerLayer?.glyph ?? "", "🎉")
        XCTAssertEqual(copy.allLayers[2].id, "dup-2")
        XCTAssertEqual(copy.textLayers.count, 1)

        var many = editor
        many.setLayers(
            (0..<(EditorLayer.maxLayers + 6)).map { index in
                .sticker(EditorStickerLayer(id: "s\(index)", glyph: "⭐"))
            }
        )
        XCTAssertEqual(many.allLayers.count, EditorLayer.maxLayers)
        XCTAssertEqual(many.allLayers.first?.id, "s6")
        XCTAssertEqual(many.allLayers.last?.id, "s\(EditorLayer.maxLayers + 5)")
    }

    func testLayerJSONIsFlatAndMissingKindMeansText() throws {
        let sticker = EditorLayer.sticker(
            EditorStickerLayer(id: "sun", glyph: "🌞", x: 0.8, y: 0.2)
        )
        let data = try JSONEncoder().encode(sticker)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["kind"] as? String, "sticker")
        XCTAssertEqual(object["glyph"] as? String, "🌞")
        XCTAssertEqual(
            try JSONDecoder().decode(EditorLayer.self, from: data),
            sticker
        )

        let legacy = Data(
            #"{"id":"old","text":"Chào","x":0.2,"y":0.3,"size":0.05}"#.utf8
        )
        guard case .text(let text) = try JSONDecoder().decode(
            EditorLayer.self,
            from: legacy
        ) else {
            return XCTFail("a missing kind has to load as text")
        }
        XCTAssertEqual(text.text, "Chào")
        XCTAssertEqual(text.x, 0.2)

        let encodedText = try JSONEncoder().encode(EditorLayer.text(text))
        let textObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedText) as? [String: Any]
        )
        XCTAssertEqual(textObject["kind"] as? String, "text")
    }

    func testReplacingSourceKeepsTextAndStickers() throws {
        var editor = try Editor(
            width: 4,
            height: 3,
            rgba: black(width: 4, height: 3)
        )
        editor.setLayers([
            .text(EditorTextLayer(id: "caption", text: "Aurum")),
            .sticker(EditorStickerLayer(id: "sun", glyph: "🌞", size: 0.5)),
        ])

        let replaced = try editor.replacingSource(
            EditorSourceSnapshot(
                width: 4,
                height: 3,
                rgba: Array(black(width: 4, height: 3).reversed())
            )
        )
        XCTAssertEqual(replaced.allLayers, editor.allLayers)
        XCTAssertEqual(replaced.textLayers.count, 1)
        XCTAssertEqual(replaced.allLayers[1].stickerLayer?.glyph ?? "", "🌞")
    }

    func testExportDrawsStickerPixels() throws {
        let width = 64
        let height = 64
        var editor = try Editor(
            width: UInt32(width),
            height: UInt32(height),
            rgba: black(width: width, height: height)
        )
        editor.setLayers([
            .sticker(
                EditorStickerLayer(
                    id: "fire",
                    glyph: "🔥",
                    x: 0.5,
                    y: 0.5,
                    size: 0.6
                )
            )
        ])
        let data = try editor.renderExport(format: .png, quality: 92)
        let decoded = try XCTUnwrap(EditorImageDecoder.decode(data))
        XCTAssertEqual(decoded.width, UInt32(width))
        XCTAssertEqual(decoded.height, UInt32(height))

        // The sticker has to change the centre of the black frame. A colour
        // emoji is not guaranteed to be a specific hue, so only the presence
        // of non-black pixels is checked.
        var changed = 0
        let box = 20
        for y in (height / 2 - box)..<(height / 2 + box) {
            for x in (width / 2 - box)..<(width / 2 + box) {
                let offset = (y * width + x) * 4
                if Int(decoded.rgba[offset])
                    + Int(decoded.rgba[offset + 1])
                    + Int(decoded.rgba[offset + 2]) > 30 {
                    changed += 1
                }
            }
        }
        XCTAssertGreaterThan(changed, 100, "the sticker did not reach the export")
    }
}
