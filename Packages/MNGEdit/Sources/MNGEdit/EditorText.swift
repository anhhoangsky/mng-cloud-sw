#if canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation

extension Editor {
    /// Burn the text and sticker layers into the exported RGBA buffer.
    ///
    /// The web editor draws the layers onto the encoded bitmap with
    /// `CanvasRenderingContext2D` (`compositeLayers()` in `ui.ts`). This is the
    /// CoreGraphics version of that pass: the same centre position, fraction of
    /// the export height, rotation, alignment, outline and shadow. Stickers use
    /// the colour-emoji face so the exported glyph matches the preview.
    func compositeLayers(
        _ rgba: [UInt8],
        width: UInt32,
        height: UInt32
    ) -> [UInt8] {
        let layers = allLayers.filter { layer in
            switch layer {
            case .text(let text):
                return !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && text.opacity > 0
            case .sticker(let sticker):
                return !sticker.glyph.isEmpty && sticker.opacity > 0
            }
        }
        guard !layers.isEmpty,
              width > 0,
              height > 0,
              rgba.count == Int(width) * Int(height) * 4,
              let base = try? Editor.makeImage(
                rgba: rgba,
                width: width,
                height: height
              ) else {
            return rgba
        }

        let pixelWidth = Int(width)
        let pixelHeight = Int(height)
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return rgba
        }

        context.interpolationQuality = .high
        context.draw(
            base,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
        for layer in layers {
            switch layer {
            case .text(let text):
                draw(text, in: context, width: pixelWidth, height: pixelHeight)
            case .sticker(let sticker):
                draw(sticker, in: context, width: pixelWidth, height: pixelHeight)
            }
        }

        guard let data = context.data else { return rgba }
        let count = pixelWidth * pixelHeight * 4
        return Array(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self),
                count: count
            )
        )
    }

    /// Draw one layer at its normalized centre, the way the web canvas pass
    /// does: rotate around the centre, draw each line with the baseline
    /// centred, then stroke or shadow it.
    private func draw(
        _ layer: EditorTextLayer,
        in context: CGContext,
        width: Int,
        height: Int
    ) {
        let text = layer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let size = max(8, CGFloat(layer.size) * CGFloat(height))
        let font = Editor.textFont(for: layer, size: size)
        let color = Editor.color(from: layer.color)
            ?? CGColor(gray: 1, alpha: 1)
        let lines = text.components(separatedBy: "\n")

        // Lay the lines out once so every line can align against the widest.
        var rendered: [(line: CTLine, width: CGFloat, ascent: CGFloat)] = []
        var maxWidth: CGFloat = 0
        for textLine in lines {
            let attributed = NSAttributedString(
                string: textLine.isEmpty ? " " : textLine,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                ]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            let lineWidth = CGFloat(
                CTLineGetTypographicBounds(line, &ascent, nil, nil)
            )
            maxWidth = max(maxWidth, lineWidth)
            rendered.append((line, lineWidth, ascent))
        }

        let lineHeight = size * 1.18
        let blockHeight = lineHeight * CGFloat(rendered.count)
        let centerX = CGFloat(layer.x) * CGFloat(width)
        let centerY = (1 - CGFloat(layer.y)) * CGFloat(height)

        context.saveGState()
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: -CGFloat(layer.rotation) * .pi / 180)
        context.setAlpha(CGFloat(layer.opacity))

        if layer.outline {
            context.setLineJoin(.round)
            context.setLineWidth(max(1, size * 0.09))
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.85))
        } else if layer.shadow {
            context.setShadow(
                offset: CGSize(width: 0, height: -size * 0.04),
                blur: size * 0.18,
                color: CGColor(gray: 0, alpha: 0.45)
            )
        }

        for (index, entry) in rendered.enumerated() {
            let x: CGFloat
            switch layer.align {
            case .left:
                x = -maxWidth / 2
            case .center:
                x = -entry.width / 2
            case .right:
                x = maxWidth / 2 - entry.width
            }
            // The block is centred on the layer position; the first line's
            // top edge sits half a block above the centre.
            let top = blockHeight / 2 - CGFloat(index) * lineHeight
            let baseline = top - entry.ascent

            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x, y: baseline)
            if layer.outline {
                context.setTextDrawingMode(.stroke)
                CTLineDraw(entry.line, context)
                context.setTextDrawingMode(.fill)
            }
            CTLineDraw(entry.line, context)
        }

        context.restoreGState()
    }

    /// Draw one sticker at its normalized centre with the colour-emoji face.
    ///
    /// The web canvas sets `textBaseline = "middle"`; Core Text anchors at the
    /// baseline, so the line is shifted by half of its ascent/descent box to
    /// land on the same centre.
    private func draw(
        _ layer: EditorStickerLayer,
        in context: CGContext,
        width: Int,
        height: Int
    ) {
        guard !layer.glyph.isEmpty else { return }
        let size = max(8, CGFloat(layer.size) * CGFloat(height))
        let font = Editor.stickerFont(size: size)
        let attributed = NSAttributedString(
            string: layer.glyph,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let lineWidth = CGFloat(
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        )

        let centerX = CGFloat(layer.x) * CGFloat(width)
        let centerY = (1 - CGFloat(layer.y)) * CGFloat(height)

        context.saveGState()
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: -CGFloat(layer.rotation) * .pi / 180)
        context.setAlpha(CGFloat(layer.opacity))
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: -lineWidth / 2,
            y: (descent - ascent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func stickerFont(size: CGFloat) -> CTFont {
        let emoji = CTFontCreateWithName(
            "Apple Color Emoji" as CFString,
            size,
            nil
        )
        // The named face exists on every Apple platform that ships the colour
        // emoji font; the UI font is a safe fallback if a future OS renames it.
        if CTFontGetGlyphCount(emoji) > 0 {
            return emoji
        }
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func textFont(
        for layer: EditorTextLayer,
        size: CGFloat
    ) -> CTFont {
        let base: CTFont
        if let name = layer.font.postScriptName {
            base = CTFontCreateWithName(name as CFString, size, nil)
        } else if let system = CTFontCreateUIFontForLanguage(
            .system,
            size,
            nil
        ) {
            base = system
        } else {
            base = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }

        var traits: CTFontSymbolicTraits = []
        if layer.bold { traits.insert(.traitBold) }
        if layer.italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let copy = CTFontCreateCopyWithSymbolicTraits(
                base,
                size,
                nil,
                traits,
                traits
              ) else {
            return base
        }
        return copy
    }

    /// Parse the `#rrggbb` colour of the web text layer.
    static func color(from hex: String) -> CGColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6,
              let packed = UInt32(value, radix: 16) else {
            return nil
        }
        return CGColor(
            red: CGFloat((packed >> 16) & 0xff) / 255,
            green: CGFloat((packed >> 8) & 0xff) / 255,
            blue: CGFloat(packed & 0xff) / 255,
            alpha: 1
        )
    }
}
#endif
