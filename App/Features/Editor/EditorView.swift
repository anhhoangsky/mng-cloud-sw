import MNGEdit
import MNGKit
import SwiftUI
import UIKit

/// The Aurum editor of the phone.
///
/// It is the editor of the browser, ported to the device: the same layout
/// with the glass header, the stage, the pane and the dock of tabs, the
/// same presets and the same adjustments. The pixels are rendered by the
/// `MNGEdit` pipeline on the device and never leave it before the export.
struct EditorView: View {
    let model: ShellModel
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    /// The zoom of the stage, for looking at the photo.
    @State private var stageScale: CGFloat = 1
    /// The pan of the stage, for looking at the photo.
    @State private var stageOffset: CGSize = .zero
    /// The zoom while the fingers are on the screen.
    @State private var gestureScale: CGFloat = 1
    /// The pan while the fingers are on the screen.
    @State private var gestureOffset: CGSize = .zero
    /// The last scale of the pinch, so the gesture can be relative.
    @State private var pinchStart: CGFloat = 1
    /// The export sheet is open over the editor.
    @State private var exportOpen = false
    /// True while the person holds the compare button down.
    @State private var isComparing = false
    /// The size of the stage, used by the screen aspect preset.
    @State private var stageSize: CGSize = .zero
    /// The text layer whose inline field is open, and its draft.
    @State private var editingTextId: String?
    @State private var textDraft = ""
    @FocusState private var textFocus: String?
    /// The one-shot "tap the photo to place text" mode of the web pane.
    @State private var textPlacing = false
    /// The web's `aurum:text-frame` toggle: the dashed frame around the
    /// selected layer with its rotate and scale handles.
    @AppStorage("aurum:text-frame") private var textFrameVisible = true
    /// The name typed next to the "Lưu" action of the filter pane.
    @State private var presetName = ""
    /// The quick style the selected layer was given in this pane.
    @State private var activeTextStyle: EditorModel.TextStyle = .title
    /// The rail of the crop pane.
    @State private var cropMode: CropMode = .ratio
    /// Interaction states that fade the chrome and reveal the crop grid,
    /// mirroring the web's `au-cropping` / `au-ratioing` / `au-rotating`.
    @State private var isCropDragging = false
    @State private var isRatioing = false
    @State private var isGeometryEditing = false
    @State private var ratioResetTask: Task<Void, Never>?
    /// The origin of a text node gesture, so every change is relative to the
    /// first frame instead of accumulating rounding errors.
    @State private var textDragId: String?
    @State private var textDragOrigin: CGPoint = .zero
    @State private var textDragStartTranslation: CGSize = .zero
    @State private var textScaleOrigin: Float?
    @State private var textScaleStartDistance: CGFloat = 1
    @State private var textRotateOrigin: Float?
    @State private var textRotateStartAngle: CGFloat = 0
    /// The first location of the current handle drag. A cancelled gesture
    /// never gets its `onEnded`, so this identifies a fresh drag even when
    /// the previous origin was not cleared.
    @State private var textRotateDragStart: CGPoint?

    /// The four modes of the crop pane, in the web's order: ratio, rotation
    /// and the two 3D perspective axes.
    private enum CropMode: String, CaseIterable, Identifiable {
        case ratio
        case rotation
        case perspectiveY
        case perspectiveX

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ratio: return Strings.editorCropRatio
            case .rotation: return Strings.editorCropRotation
            case .perspectiveY: return Strings.editorCropPerspectiveVertical
            case .perspectiveX: return Strings.editorCropPerspectiveHorizontal
            }
        }

        var icon: String {
            switch self {
            case .ratio: return "crop"
            case .rotation: return "rotate.right"
            case .perspectiveY: return "arrow.up.and.down"
            case .perspectiveX: return "arrow.left.and.right"
            }
        }
    }

    private static let textStageSpace = "editorTextStage"
    private static let tuneKeys: [EditorModel.Adjustment] = [
        .brightness, .contrast, .saturation,
        .warmth, .tint, .vibrance, .vignette,
    ]

    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case failed(String)
    }

    private var editor: EditorModel { model.editor }

    var body: some View {
        ZStack {
            Aurum.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .opacity(chromeHidden ? 0 : 1)
                    .allowsHitTesting(!chromeHidden)
                    .animation(.easeOut(duration: 0.18), value: chromeHidden)
                stage
                pane
                dock
                    .opacity(chromeHidden ? 0 : 1)
                    .allowsHitTesting(!chromeHidden)
                    .animation(.easeOut(duration: 0.18), value: chromeHidden)
            }

            if phase == .loading {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView()
                    .tint(Aurum.gold)
            }

            if case .failed(let message) = phase {
                Color.black.opacity(0.72).ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Font.mng(26))
                        .foregroundStyle(Aurum.gold)
                    Text(message)
                        .font(Font.mng(13))
                        .foregroundStyle(Aurum.text)
                        .multilineTextAlignment(.center)
                    Button(Strings.editorCancel) { dismiss() }
                        .font(Font.mng(14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.03))
                        .padding(.horizontal, 22)
                        .frame(height: 38)
                        .background(Aurum.gold, in: Capsule())
                        .buttonStyle(.plain)
                }
                .padding(24)
            }

            if exportOpen {
                exportSheet
                    .zIndex(20)
            }
        }
        .task {
            await editor.open(item: item)
            switch editor.state {
            case .ready:
                phase = .ready
            case .failed(let message):
                phase = .failed(message)
            default:
                phase = .loading
            }
        }
        .onDisappear {
            ratioResetTask?.cancel()
            commitTextEditing()
            editor.close()
        }
        .onChange(of: editor.tab) { oldTab, tab in
            commitTextEditing()
            editor.endEdit()
            // A gesture that was interrupted by the tab change may never get
            // its `onEnded`; clear its origin so the next drag starts clean.
            textDragId = nil
            textScaleOrigin = nil
            textRotateOrigin = nil
            textRotateDragStart = nil
            textPlacing = false
            if tab != .crop {
                isCropDragging = false
                isRatioing = false
                isGeometryEditing = false
            }
            if tab == .text || oldTab == .crop {
                stageScale = 1
                stageOffset = .zero
                gestureScale = 1
                gestureOffset = .zero
            }
            guard tab == .crop else { return }
            // The crop frame is drawn over the fitted photo, not over the
            // zoomed one, so entering the crop resets the stage zoom.
            withAnimation(.easeOut(duration: 0.2)) {
                stageScale = 1
                stageOffset = .zero
                gestureScale = 1
                gestureOffset = .zero
                cropMode = .ratio
            }
        }
        .onChange(of: textFocus) { _, focus in
            if focus == nil, editingTextId != nil {
                commitTextEditing()
            }
        }
        .onChange(of: textDraft) { _, draft in
            // Live typing: the layer follows the field on every keystroke
            // instead of waiting for a tap outside. The editing session is one
            // open transaction, so the whole edit is one undo step.
            guard let id = editingTextId else { return }
            editor.updateText(id, coalescing: false) { $0.text = draft }
        }
        .ignoresSafeArea(
            .keyboard,
            edges: editor.tab == .text ? .bottom : Edge.Set()
        )
    }

    /// The chrome fades while the crop frame, the ratio rail or a geometry
    /// ruler owns the screen, like the web's `au-cropping` classes.
    private var chromeHidden: Bool {
        editor.tab == .crop && (isCropDragging || isRatioing || isGeometryEditing)
    }

    /// The mode rail fades during a ratio change and a geometry drag, but
    /// stays while the frame is dragged (the web keeps the deck there).
    private var cropModesHidden: Bool {
        editor.tab == .crop && (isRatioing || isGeometryEditing)
    }

    // MARK: - Header

    /// The glass header: cancel and save on the first row, the history and
    /// the geometry on the second one.
    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                glassButton(Strings.editorCancel, icon: nil) {
                    dismiss()
                }
                Spacer(minLength: 12)
                glassButton(Strings.editorSave, icon: nil, gold: true) {
                    guard phase == .ready else { return }
                    withAnimation(Tokens.Motion.spring) {
                        exportOpen = true
                    }
                }
            }

            HStack(spacing: 6) {
                toolButton("arrow.uturn.backward", label: Strings.editorUndo) {
                    editor.undo()
                }
                toolButton("arrow.uturn.forward", label: Strings.editorRedo) {
                    editor.redo()
                }
                Spacer(minLength: 8)
                toolButton("rotate.left", label: Strings.editorRotateLeft) {
                    editor.rotate(-1)
                }
                toolButton("rotate.right", label: Strings.editorRotateRight) {
                    editor.rotate(1)
                }
                toolButton(
                    "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    label: Strings.editorFlipH
                ) {
                    editor.flip(horizontal: true)
                }
                toolButton("arrow.up.and.down", label: Strings.editorFlipV) {
                    editor.flip(horizontal: false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func glassButton(
        _ title: String,
        icon: String?,
        gold: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(Font.mng(13, weight: .semibold))
                }
                Text(title)
                    .font(Font.mng(14, weight: .semibold))
            }
            .foregroundStyle(gold ? Color(red: 0.10, green: 0.08, blue: 0.03) : Aurum.text)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(
                gold ? AnyShapeStyle(Aurum.gold) : AnyShapeStyle(Aurum.glass),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Aurum.glassLine, lineWidth: gold ? 0 : 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func toolButton(
        _ icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Font.mng(15, weight: .medium))
                .foregroundStyle(Aurum.text)
                .frame(width: 36, height: 36)
                .background(Aurum.glass, in: Circle())
                .overlay {
                    Circle().stroke(Aurum.glassLine, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Stage

    /// The photo with the crop rectangle and, outside the crop tab, the text
    /// layers on top.
    ///
    /// The stage can be panned, pinched and tapped twice, so the person can
    /// look at a detail before cropping. In the text tab the subview gestures
    /// own the screen instead of the stage pan.
    private var stage: some View {
        GeometryReader { geometry in
            ZStack {
                Aurum.bg

                if let preview = displayedPreview {
                    let fitted = fittedSize(image: preview, in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: fitted.width, height: fitted.height)

                            if editor.tab == .crop {
                                // The overlay lives inside the scaled photo
                                // stack, so the dim scrim covers the whole
                                // photo even when it is zoomed or panned.
                                if !isComparing {
                                    CropOverlay(
                                        crop: editor.crop,
                                        isFixedAspect: editor.aspect != .free,
                                        scrimVisible: !isCropDragging && !isRatioing,
                                        showGrid: isCropDragging || isGeometryEditing,
                                        isGeometryEditing: isGeometryEditing,
                                        onChange: { editor.setCrop($0) },
                                        onBegin: { editor.beginCropEdit() },
                                        onDragState: { active in
                                            if !active {
                                                editor.endEdit()
                                            }
                                            withAnimation(.easeOut(duration: 0.18)) {
                                                isCropDragging = active
                                            }
                                        }
                                    )
                                    .frame(
                                        width: fitted.width,
                                        height: fitted.height
                                    )
                                }
                            } else if !isComparing {
                                textOverlay(fitted: fitted)
                                    .frame(
                                        width: fitted.width,
                                        height: fitted.height
                                    )
                            }
                        }
                        .frame(width: fitted.width, height: fitted.height)
                        .scaleEffect(stageScale * gestureScale)
                        .offset(
                            x: stageOffset.width + gestureOffset.width,
                            y: stageOffset.height + gestureOffset.height
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                    }
                }

                if editor.originalPreview != nil {
                    compareButton
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        gestureOffset = value.translation
                    }
                    .onEnded { value in
                        stageOffset.width += value.translation.width
                        stageOffset.height += value.translation.height
                        gestureOffset = .zero
                    },
                including: editor.tab == .text ? .subviews : .all
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        gestureScale = value
                    }
                    .onEnded { value in
                        pinchStart = max(min(stageScale * value, 6), 1)
                        stageScale = pinchStart
                        gestureScale = 1
                    },
                including: editor.tab == .text ? .subviews : .all
            )
            .onTapGesture(count: 2) {
                guard editor.tab != .text else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    if stageScale > 1.05 {
                        stageScale = 1
                        stageOffset = .zero
                    } else {
                        stageScale = 2.5
                    }
                }
            }
            .onAppear {
                stageSize = geometry.size
            }
            .onChange(of: geometry.size) { _, size in
                stageSize = size
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Text layers

    /// The text nodes over the photo. The whole layer is normalized to the
    /// fitted image, so the preview and the full-resolution export line up.
    @ViewBuilder
    private func textOverlay(fitted: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Tapping the photo outside the field writes the draft back and
            // keeps the selected frame, so the text stays on the canvas.
            if editingTextId != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        commitTextEditing()
                    }
            }

            ForEach(editor.texts) { layer in
                if editingTextId == layer.id {
                    inlineTextEditor(layer, fitted: fitted)
                } else {
                    textNode(layer, fitted: fitted)
                }
            }

            // "Chạm đặt" is a one-shot mode: the next tap on the photo adds
            // the layer exactly where the finger landed and opens the field.
            if textPlacing {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let x = Float(
                                    value.location.x / max(fitted.width, 1)
                                )
                                let y = Float(
                                    value.location.y / max(fitted.height, 1)
                                )
                                guard x >= 0.03, x <= 0.97,
                                      y >= 0.03, y <= 0.97 else {
                                    return
                                }
                                placeText(x: x, y: y)
                            }
                    )
            }
        }
        .frame(
            width: fitted.width,
            height: fitted.height,
            alignment: .topLeading
        )
        .coordinateSpace(name: Self.textStageSpace)
    }

    private func textNode(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some View {
        let selected = editor.tab == .text && editor.selectedTextId == layer.id
        let fontSize = max(10, fitted.height * CGFloat(layer.size))
        let widthLimit = max(fitted.width * 0.7, 60)
        let measured = textNodeSize(
            layer,
            fontSize: fontSize,
            limit: widthLimit
        )
        let showFrame = selected && textFrameVisible
        let glyphs = textGlyphs(layer, fontSize: fontSize)
            .frame(
                width: measured.width,
                height: measured.height,
                alignment: textAlignment(layer.align)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                beginEditing(layer)
            }
            .onTapGesture {
                if editingTextId != nil {
                    commitTextEditing()
                }
                editor.selectText(layer.id)
            }
            .gesture(moveTextGesture(layer, fitted: fitted))
            .simultaneousGesture(scaleTextGesture(layer, fitted: fitted))
            .simultaneousGesture(rotateTextGesture(layer, fitted: fitted))
            // Outside the text tab the stage owns the pan and the pinch, so
            // the layer is visible but transparent to the finger.
            .allowsHitTesting(editor.tab == .text)

        return ZStack {
            glyphs

            if showFrame {
                // The dashed frame hugs the measured text, so it stays glued
                // to the glyphs while the size slider or the scale handle
                // changes them.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Aurum.gold.opacity(0.80),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [4, 3]
                        )
                    )
                    .frame(
                        width: measured.width + 12,
                        height: measured.height + 12
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: measured.width, height: measured.height)
        // The padding gives the rotate and scale handles room inside the
        // hit-testable bounds of the node.
        .padding(30)
        .overlay(alignment: .top) {
            if selected {
                rotateHandle(layer, fitted: fitted)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selected {
                scaleHandle(layer, fitted: fitted)
            }
        }
        // Rotate the node around its own centre, then place that centre on
        // the layer point. `.position` first would make this view fill the
        // whole stage, so the following rotation would orbit the stage
        // centre instead of the text.
        .rotationEffect(.degrees(Double(layer.rotation)))
        .position(
            x: CGFloat(layer.x) * fitted.width,
            y: CGFloat(layer.y) * fitted.height
        )
    }

    /// The size the glyphs need, measured with the same font the exporter and
    /// the SwiftUI text run. It is used for the frame and the handle anchors,
    /// not for the export geometry.
    private func textNodeSize(
        _ layer: EditorTextLayer,
        fontSize: CGFloat,
        limit: CGFloat
    ) -> CGSize {
        let content = layer.text.isEmpty ? " " : layer.text
        let paragraph = NSMutableParagraphStyle()
        switch layer.align {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textUIFont(layer, size: fontSize),
            .paragraphStyle: paragraph,
        ]
        let bounding = (content as NSString).boundingRect(
            with: CGSize(
                width: limit,
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let stroke = layer.outline ? max(1, fontSize * 0.045) * 2 : 0
        return CGSize(
            width: min(
                max(ceil(bounding.width) + stroke + 4, 12),
                limit + stroke + 4
            ),
            height: max(ceil(bounding.height) + stroke + 4, fontSize)
        )
    }

    private func textUIFont(
        _ layer: EditorTextLayer,
        size: CGFloat
    ) -> UIFont {
        let base: UIFont
        switch layer.font {
        case .sys:
            base = UIFont.systemFont(
                ofSize: size,
                weight: layer.bold ? .bold : .regular
            )
        case .serif:
            base = UIFont(name: layer.bold ? "Georgia-Bold" : "Georgia", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: layer.bold ? .bold : .regular)
        case .mono:
            base = UIFont(name: layer.bold ? "Menlo-Bold" : "Menlo-Regular", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: layer.bold ? .bold : .regular)
        case .round:
            base = UIFont(name: "ArialRoundedMTBold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold)
        case .heavy:
            base = UIFont(name: "Arial-Black", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        }
        guard layer.italic else { return base }
        let traits = base.fontDescriptor.symbolicTraits.union(.traitItalic)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func textAlignment(_ align: EditorTextAlign) -> Alignment {
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private func textGlyphs(
        _ layer: EditorTextLayer,
        fontSize: CGFloat
    ) -> some View {
        let color = Color.mngHex(layer.color) ?? .white
        let content = layer.text.isEmpty ? " " : layer.text
        let font = textFont(layer, size: fontSize)
        let alignment: TextAlignment
        switch layer.align {
        case .left: alignment = .leading
        case .center: alignment = .center
        case .right: alignment = .trailing
        }
        let stroke = max(1, fontSize * 0.045)

        return ZStack {
            if layer.outline {
                ForEach(0..<8, id: \.self) { index in
                    let angle = Double(index) * .pi / 4
                    Text(content)
                        .font(font)
                        .foregroundStyle(Color.black.opacity(0.9))
                        .multilineTextAlignment(alignment)
                        .offset(
                            x: stroke * CGFloat(cos(angle)),
                            y: stroke * CGFloat(sin(angle))
                        )
                }
            }
            Text(content)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(alignment)
                .shadow(
                    color: layer.shadow ? Color.black.opacity(0.6) : .clear,
                    radius: layer.shadow ? fontSize * 0.18 : 0,
                    y: layer.shadow ? fontSize * 0.08 : 0
                )
        }
        .opacity(Double(layer.opacity))
        .accessibilityLabel(content)
    }

    private func textFont(_ layer: EditorTextLayer, size: CGFloat) -> Font {
        let base: Font
        switch layer.font {
        case .sys:
            base = .system(size: size)
        case .serif:
            base = .custom("Georgia", size: size)
        case .mono:
            base = .custom("Menlo", size: size)
        case .round:
            base = .custom("ArialRoundedMTBold", size: size)
        case .heavy:
            base = .custom("Arial-Black", size: size)
        }
        var font = layer.bold ? base.weight(.bold) : base
        if layer.italic {
            font = font.italic()
        }
        return font
    }

    private func rotateHandle(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some View {
        Circle()
            .fill(Aurum.gold)
            .frame(width: 28, height: 28)
            .overlay {
                Circle().stroke(Color.black.opacity(0.6), lineWidth: 2)
            }
            .overlay {
                Image(systemName: "rotate.right")
                    .font(Font.mng(11, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.65))
            }
            .shadow(color: Color.black.opacity(0.5), radius: 6, y: 3)
            .frame(width: 44, height: 44)
            // Keep the visible gold dot on the old spot while the 44 pt
            // frame gives the thumb a real target.
            .offset(y: -8)
            .contentShape(Circle())
            .highPriorityGesture(rotateHandleGesture(layer, fitted: fitted))
    }

    private func scaleHandle(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some View {
        Circle()
            .fill(Aurum.gold)
            .frame(width: 28, height: 28)
            .overlay {
                Circle().stroke(Color.black.opacity(0.6), lineWidth: 2)
            }
            .overlay {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(Font.mng(9, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.65))
            }
            .shadow(color: Color.black.opacity(0.5), radius: 6, y: 3)
            .contentShape(Circle())
            .highPriorityGesture(scaleHandleGesture(layer, fitted: fitted))
    }

    private func moveTextGesture(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(Self.textStageSpace)
        )
        .onChanged { value in
            if textDragId != layer.id {
                textDragId = layer.id
                textDragOrigin = CGPoint(
                    x: CGFloat(layer.x),
                    y: CGFloat(layer.y)
                )
                // A drag with a 3 pt threshold reports those 3 pt in the first
                // event; keeping them out avoids the little jump at the start.
                textDragStartTranslation = value.translation
                editor.selectText(layer.id)
                editor.beginEdit()
            }
            let dx = Float(
                (value.translation.width - textDragStartTranslation.width)
                    / max(fitted.width, 1)
            )
            let dy = Float(
                (value.translation.height - textDragStartTranslation.height)
                    / max(fitted.height, 1)
            )
            editor.updateText(layer.id) { text in
                text.x = Float(textDragOrigin.x) + dx
                text.y = Float(textDragOrigin.y) + dy
            }
        }
        .onEnded { _ in
            textDragId = nil
            editor.endEdit()
        }
    }

    private func scaleTextGesture(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if textScaleOrigin == nil {
                    textScaleOrigin = layer.size
                    editor.selectText(layer.id)
                    editor.beginEdit()
                }
                let origin = textScaleOrigin ?? layer.size
                editor.updateText(layer.id) { text in
                    text.size = origin * Float(value)
                }
            }
            .onEnded { _ in
                textScaleOrigin = nil
                editor.endEdit()
            }
    }

    private func rotateTextGesture(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some Gesture {
        RotationGesture()
            .onChanged { value in
                if textRotateOrigin == nil {
                    textRotateOrigin = layer.rotation
                    editor.selectText(layer.id)
                    editor.beginEdit()
                }
                let origin = textRotateOrigin ?? layer.rotation
                editor.updateText(layer.id) { text in
                    text.rotation = origin
                        + Float(value.degrees)
                }
            }
            .onEnded { _ in
                textRotateOrigin = nil
                editor.endEdit()
            }
    }

    private func rotateHandleGesture(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(Self.textStageSpace)
        )
        .onChanged { value in
            let center = CGPoint(
                x: CGFloat(layer.x) * fitted.width,
                y: CGFloat(layer.y) * fitted.height
            )
            let angle = atan2(
                value.location.y - center.y,
                value.location.x - center.x
            ) * 180 / .pi
            // `onEnded` is not called when a competing gesture cancels this
            // drag. A new start location then begins a clean session instead
            // of reusing the stale origin and snapping the layer.
            if textRotateOrigin == nil
                || textRotateDragStart != value.startLocation {
                textRotateOrigin = layer.rotation
                textRotateStartAngle = angle
                textRotateDragStart = value.startLocation
                editor.selectText(layer.id)
                editor.beginEdit()
            }
            let delta = angle - textRotateStartAngle
            let origin = textRotateOrigin ?? layer.rotation
            editor.updateText(layer.id) { text in
                text.rotation = origin + Float(delta)
            }
        }
        .onEnded { _ in
            textRotateOrigin = nil
            textRotateDragStart = nil
            editor.endEdit()
        }
    }

    private func scaleHandleGesture(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(Self.textStageSpace)
        )
        .onChanged { value in
            let center = CGPoint(
                x: CGFloat(layer.x) * fitted.width,
                y: CGFloat(layer.y) * fitted.height
            )
            let distance = max(
                hypot(
                    value.location.x - center.x,
                    value.location.y - center.y
                ),
                1
            )
            if textScaleOrigin == nil {
                textScaleOrigin = layer.size
                textScaleStartDistance = distance
                editor.selectText(layer.id)
                editor.beginEdit()
            }
            let factor = distance / max(textScaleStartDistance, 1)
            let origin = textScaleOrigin ?? layer.size
            editor.updateText(layer.id) { text in
                text.size = origin * Float(factor)
            }
        }
        .onEnded { _ in
            textScaleOrigin = nil
            editor.endEdit()
        }
    }

    private func inlineTextEditor(
        _ layer: EditorTextLayer,
        fitted: CGSize
    ) -> some View {
        let width = min(max(fitted.width * 0.72, 150), 340)
        return TextField(
            Strings.editorTextInput,
            text: $textDraft,
            axis: .vertical
        )
        .font(
            .system(
                size: max(13, min(fitted.height * CGFloat(layer.size), 22)),
                weight: .semibold
            )
        )
        .foregroundStyle(Color.white)
        .multilineTextAlignment(.center)
        .lineLimit(1...4)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    Color(red: 0.078, green: 0.078, blue: 0.094)
                        .opacity(0.96)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Aurum.gold.opacity(0.7), lineWidth: 1)
        }
        .focused($textFocus, equals: layer.id)
        .submitLabel(.done)
        .onSubmit {
            commitTextEditing()
        }
        // Rotate the node around its own centre, then place that centre on
        // the layer point. `.position` first would make this view fill the
        // whole stage, so the following rotation would orbit the stage
        // centre instead of the text.
        .rotationEffect(.degrees(Double(layer.rotation)))
        .position(
            x: CGFloat(layer.x) * fitted.width,
            y: CGFloat(layer.y) * fitted.height
        )
        .onAppear {
            DispatchQueue.main.async {
                textFocus = layer.id
            }
        }
    }

    /// The one-shot placement mode: create the layer at the finger and open
    /// its field. The transaction starts before the layer exists, so adding
    /// and typing undo as one step.
    private func placeText(x: Float, y: Float) {
        textPlacing = false
        editor.beginEdit()
        guard let layer = editor.addText(x: x, y: y) else {
            editor.endEdit()
            return
        }
        beginEditing(layer)
    }

    private func beginEditing(_ layer: EditorTextLayer) {
        guard editingTextId != layer.id else { return }
        commitTextEditing()
        editor.selectText(layer.id)
        textDraft = layer.text
        editingTextId = layer.id
        // Live typing is one transaction: every keystroke previews, releasing
        // the field records a single undo step.
        editor.beginEdit()
        DispatchQueue.main.async {
            textFocus = layer.id
        }
    }

    /// Write the inline field back into the layer. A layer that was left
    /// empty is removed, so no invisible text survives into the export.
    private func commitTextEditing() {
        guard let id = editingTextId else { return }
        editingTextId = nil
        textFocus = nil
        let draft = textDraft
        textDraft = ""
        guard let layer = editor.texts.first(where: { $0.id == id }) else {
            editor.endEdit()
            return
        }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if editor.selectedTextId != id {
                editor.selectText(id)
            }
            editor.deleteSelectedText()
        } else if draft != layer.text {
            editor.updateText(id, coalescing: false) { $0.text = draft }
        }
        editor.endEdit()
    }

    private func fittedSize(image: UIImage, in size: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return size
        }
        let scale = min(
            size.width / image.size.width,
            size.height / image.size.height
        )
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }

    /// The edited photo, or the untouched original while the compare button
    /// is held down.
    private var displayedPreview: UIImage? {
        if isComparing, let original = editor.originalPreview {
            return original
        }
        return editor.preview
    }

    /// The web's "Nguyên bản" button: hold it to see the photo without the
    /// filter and the adjustments.
    private var compareButton: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle")
                .font(Font.mng(12, weight: .semibold))
            Text(Strings.editorHoldOriginal)
                .font(Font.mng(11, weight: .semibold))
        }
        .foregroundStyle(isComparing ? Aurum.gold : Aurum.text)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Aurum.bg2.opacity(0.82), in: Capsule())
        .overlay {
            Capsule().stroke(
                isComparing ? Aurum.gold : Aurum.glassLine,
                lineWidth: 1
            )
        }
        .contentShape(Capsule())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isComparing {
                        isComparing = true
                    }
                }
                .onEnded { _ in
                    isComparing = false
                }
        )
        .accessibilityLabel(Strings.editorHoldOriginal)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Pane

    /// The pane of the tab that is open.
    @ViewBuilder
    private var pane: some View {
        VStack(spacing: 8) {
            switch editor.tab {
            case .adjust:
                adjustPane
            case .filter:
                filterPane
            case .text:
                textPane
            case .crop:
                cropPane
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Aurum.bg2.opacity(0.92))
    }

    /// The fixed Auto action, the rail of parameters with their group
    /// captions, the gold value chip and the ruler, exactly the layout of the
    /// web's `.au-deck__row--adjust`.
    private var adjustPane: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                autoButton

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(
                                EditorModel.AdjustmentGroup.allCases
                            ) { group in
                                groupSeparator(group)
                                ForEach(
                                    EditorModel.Adjustment.allCases.filter {
                                        $0.group == group
                                    }
                                ) { key in
                                    selectChip(
                                        key.shortTitle,
                                        active: editor.activeAdjustment == key,
                                        height: 30,
                                        fontSize: 11
                                    ) {
                                        editor.selectAdjustment(key)
                                    }
                                    .id(key.rawValue)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.03),
                                .init(color: .black, location: 0.97),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .onChange(of: editor.activeAdjustment) { _, key in
                        withAnimation(.easeOut(duration: 0.26)) {
                            proxy.scrollTo(key.rawValue, anchor: .center)
                        }
                    }
                }

                valueChip(for: editor.activeAdjustment)
            }
            .padding(.horizontal, 12)

            TickSlider(
                value: Binding(
                    get: {
                        editor.activeAdjustment.value(in: editor.adjustments)
                    },
                    set: { editor.setActiveAdjustment(value: $0) }
                ),
                label: editor.activeAdjustment.title,
                minimum: editor.activeAdjustment == .vignette ? 0 : -100,
                maximum: 100,
                zero: editor.activeAdjustment != .vignette,
                ruler: true,
                onEditingChanged: { editing in
                    if editing {
                        editor.beginEdit()
                    } else {
                        editor.endEdit()
                    }
                }
            )
            .padding(.horizontal, 12)
        }
    }

    private var autoButton: some View {
        Button {
            editor.applyAutoTune()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(Font.mng(15, weight: .semibold))
                Text(Strings.editorAuto)
                    .font(Font.mng(10.5, weight: .bold))
                    .tracking(0.2)
            }
            .foregroundStyle(Aurum.gold)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                LinearGradient(
                    colors: [
                        Aurum.gold.opacity(0.20),
                        Aurum.gold.opacity(0.09),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Aurum.gold.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(GlassPressStyle(scale: 0.94))
        .accessibilityLabel(Strings.editorAutoTitle)
    }

    /// A hairline and a 7 pt caption mark the start of an adjustment family
    /// inside the rail, so the chips stay on one scrollable row.
    private func groupSeparator(
        _ group: EditorModel.AdjustmentGroup
    ) -> some View {
        VStack(spacing: 2) {
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.30),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1, height: 13)
            Text(groupCaption(group).uppercased())
                .font(Font.mng(7, weight: .bold))
                .tracking(0.35)
                .foregroundStyle(Color.white.opacity(0.32))
                .fixedSize()
        }
        .padding(.horizontal, 1)
        .allowsHitTesting(false)
    }

    private func groupCaption(
        _ group: EditorModel.AdjustmentGroup
    ) -> String {
        switch group {
        case .light: return Strings.editorGroupLight
        case .color: return Strings.editorGroupColor
        case .effect: return Strings.editorGroupEffect
        }
    }

    /// The gold chip that shows the open value. Tapping it resets just this
    /// slider, like the web's `.au-value`.
    private func valueChip(
        for key: EditorModel.Adjustment
    ) -> some View {
        let label = formatAdjustment(
            key.value(in: editor.adjustments),
            unsigned: key == .vignette
        )
        return Button {
            editor.resetAdjustment(key)
        } label: {
            Text(label)
                .font(Font.mng(11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Aurum.gold)
                .padding(.horizontal, 9)
                .frame(minWidth: 48)
                .frame(height: 32)
                .background(
                    Aurum.gold.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Aurum.gold.opacity(0.30), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(key.title): \(label)")
        .accessibilityHint(Strings.editorAdjustReset)
    }

    private func formatAdjustment(
        _ value: Float,
        unsigned: Bool = false
    ) -> String {
        let rounded = Int(value.rounded())
        if unsigned {
            return "\(rounded)"
        }
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    /// The category rail, the hint of the open tone, the 29 thumbnails and
    /// the collapsible tone tune, in the order of the web filter pane.
    private var filterPane: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(
                            EditorModel.FilterCategory.allCases
                        ) { category in
                            selectChip(
                                category.title,
                                active: editor.filterCategory == category,
                                height: 30,
                                fontSize: 11.5
                            ) {
                                editor.selectFilterCategory(category)
                            }
                            .id(category.rawValue)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: editor.filterCategory) { _, category in
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo(category.rawValue, anchor: .center)
                    }
                }
            }

            Text(Strings.editorFilterHint(editor.filter))
                .font(Font.mng(10.5))
                .foregroundStyle(Aurum.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .contentTransition(.opacity)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        // Saved presets lead the rail like the web's personal
                        // row, separated from the built-in tones by "Mặc định".
                        ForEach(editor.userPresets) { preset in
                            savedPresetButton(preset)
                        }
                        if !editor.userPresets.isEmpty {
                            filterSeparator
                        }
                        ForEach(editor.visibleFilters, id: \.self) { filter in
                            filterThumbnail(filter)
                                .id(filter)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
                .onChange(of: editor.filter) { _, filter in
                    // A saved preset may sit at the head of the rail while
                    // its underlying tone is far to the right; keep the head
                    // in view instead of scrolling away from the active card.
                    guard editor.activeSavedPresetId == nil,
                          editor.visibleFilters.contains(filter) else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo(filter, anchor: .center)
                    }
                }
            }

            tuneSection
        }
    }

    /// The divider between the personal row and the built-in tones, drawn
    /// with the vertical hairline and tiny caps of `.au-filter-sep`.
    private var filterSeparator: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1, height: 20)
            Text(Strings.editorFilterDefaultLabel.uppercased())
                .font(Font.mng(7, weight: .bold))
                .tracking(0.35)
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(width: 42, height: 68)
        .allowsHitTesting(false)
    }

    private func savedPresetButton(
        _ preset: EditorModel.UserPreset
    ) -> some View {
        let active = editor.activeSavedPresetId == preset.id
        return ZStack(alignment: .topTrailing) {
            Button {
                editor.applyUserPreset(preset)
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.11, green: 0.11, blue: 0.13))
                        if let thumbnail = editor.filterThumbnails[preset.filter] {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 52, height: 52)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )
                        } else {
                            Image(systemName: "bookmark")
                                .font(Font.mng(16))
                                .foregroundStyle(Aurum.muted)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                active
                                    ? AnyShapeStyle(Aurum.gold)
                                    : AnyShapeStyle(
                                        Color.white.opacity(0.28)
                                    ),
                                style: StrokeStyle(
                                    lineWidth: active ? 2 : 1,
                                    dash: active ? [] : [4, 3]
                                )
                            )
                    }
                    .shadow(
                        color: active
                            ? Aurum.gold.opacity(0.22)
                            : Color.black.opacity(0.35),
                        radius: active ? 10 : 4,
                        y: 3
                    )
                    Text(preset.name)
                        .font(Font.mng(9.5, weight: .semibold))
                        .foregroundStyle(active ? Aurum.gold : Aurum.muted)
                        .lineLimit(1)
                        .frame(width: 54)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preset.name)
            .accessibilityAddTraits(active ? .isSelected : [])

            Button {
                editor.deleteUserPreset(preset.id)
            } label: {
                Image(systemName: "xmark")
                    .font(Font.mng(7, weight: .bold))
                    .foregroundStyle(Color(red: 0.94, green: 0.64, blue: 0.56))
                    .frame(width: 16, height: 16)
                    .background(
                        Color(red: 0.23, green: 0.23, blue: 0.25),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .accessibilityLabel(Strings.editorPresetDelete)
        }
        .frame(width: 56)
    }

    /// The name field and the save action of the web's "Lưu bộ lọc" row.
    private var savePresetRow: some View {
        HStack(spacing: 6) {
            TextField(Strings.editorPresetName, text: $presetName)
                .font(Font.mng(11.5))
                .foregroundStyle(Aurum.text)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit {
                    savePreset()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    Color.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            Button(Strings.editorPresetSave) {
                savePreset()
            }
            .font(Font.mng(11.5, weight: .semibold))
            .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.03))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(
                Aurum.gold,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private func savePreset() {
        if editor.saveUserPreset(named: presetName) {
            presetName = ""
        }
    }

    private func filterThumbnail(_ filter: EditorFilter) -> some View {
        let active = editor.filter == filter
        return Button {
            editor.setFilter(filter)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.11, green: 0.11, blue: 0.13))
                    if let thumbnail = editor.filterThumbnails[filter] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                    } else {
                        Image(systemName: "photo")
                            .font(Font.mng(16))
                            .foregroundStyle(Aurum.muted)
                    }
                }
                .frame(width: 52, height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(active ? Aurum.gold : .clear, lineWidth: 2)
                }
                .shadow(
                    color: active
                        ? Aurum.gold.opacity(0.22)
                        : Color.black.opacity(0.35),
                    radius: active ? 10 : 4,
                    y: 3
                )
                Text(Strings.editorFilterTitle(filter))
                    .font(Font.mng(9.5, weight: .semibold))
                    .foregroundStyle(active ? Aurum.gold : Aurum.muted)
                    .lineLimit(1)
                    .frame(width: 54)
            }
            .frame(width: 54)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.editorFilterTitle(filter))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The collapsible "Tùy chỉnh tone" of the web filter pane: seven sliders
    /// that write back into the same adjustments as the Adjust tab.
    private var tuneSection: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(Strings.editorTuneTitle.uppercased())
                        .font(Font.mng(11, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(
                            Color(red: 0.94, green: 0.92, blue: 0.85)
                        )
                        .lineLimit(1)
                    Text(Strings.editorTuneHint)
                        .font(Font.mng(10))
                        .foregroundStyle(Aurum.muted)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        editor.toggleTune()
                    }
                }

                Spacer(minLength: 2)

                Button(Strings.editorTuneReset) {
                    editor.resetTune()
                }
                .font(Font.mng(10, weight: .semibold))
                .foregroundStyle(Aurum.muted)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.white.opacity(0.055), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .buttonStyle(.plain)

                Image(
                    systemName: editor.tuneOpen ? "chevron.up" : "chevron.down"
                )
                .font(Font.mng(10, weight: .bold))
                .foregroundStyle(Aurum.muted)
            }
            .padding(.horizontal, 14)

            if editor.tuneOpen {
                VStack(spacing: 8) {
                    tuneControls

                    // The web moved "Đã lưu" and the save form into the tune
                    // collapse, so the filter rail stays a pure preset list.
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.horizontal, 14)

                        Text(Strings.editorPresetSavedTitle.uppercased())
                            .font(Font.mng(8.5, weight: .bold))
                            .tracking(0.35)
                            .foregroundStyle(Color.white.opacity(0.38))
                            .padding(.horizontal, 14)

                        savePresetRow
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var tuneControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(Self.tuneKeys, id: \.self) { key in
                                selectChip(
                                    key.shortTitle,
                                    active: editor.tuneKey == key,
                                    height: 30,
                                    fontSize: 11
                                ) {
                                    editor.selectTuneKey(key)
                                }
                                .id(key.rawValue)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: editor.tuneKey) { _, key in
                        withAnimation(.easeOut(duration: 0.24)) {
                            proxy.scrollTo(key.rawValue, anchor: .center)
                        }
                    }
                }

                valueChip(for: editor.tuneKey)
            }
            .padding(.horizontal, 12)

            TickSlider(
                value: Binding(
                    get: {
                        editor.tuneKey.value(in: editor.adjustments)
                    },
                    set: { editor.setTune(value: $0) }
                ),
                label:
                    "\(Strings.editorTuneTitle) · \(editor.tuneKey.title)",
                minimum: editor.tuneKey == .vignette ? 0 : -100,
                maximum: 100,
                zero: editor.tuneKey != .vignette,
                ruler: true,
                onEditingChanged: { editing in
                    if editing {
                        editor.beginEdit()
                    } else {
                        editor.endEdit()
                    }
                }
            )
            .padding(.horizontal, 12)
        }
    }

    /// The quick styles, fonts, colour, toggles and opacity of the text pane,
    /// plus the one-shot placement mode of the web.
    private var textPane: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    selectChip(
                        Strings.editorTextPlace,
                        icon: "plus.viewfinder",
                        active: textPlacing,
                        height: 36,
                        fontSize: 12
                    ) {
                        textPlacing.toggle()
                    }

                    selectChip(
                        Strings.editorTextFrame,
                        icon: "rectangle.dashed",
                        active: textFrameVisible,
                        height: 36,
                        fontSize: 12
                    ) {
                        textFrameVisible.toggle()
                    }

                    ForEach(EditorModel.TextStyle.allCases) { style in
                        selectChip(
                            style.title,
                            active: activeTextStyle == style,
                            height: 36,
                            fontSize: 12
                        ) {
                            activeTextStyle = style
                            editor.applyTextStyle(style)
                        }
                        .disabled(editor.selectedText == nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 1)
            }

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(EditorTextFont.allCases, id: \.self) { font in
                            fontButton(font)
                        }
                    }
                    .padding(2)
                    .background(
                        Color.white.opacity(0.04),
                        in: RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
                }
                .frame(maxWidth: .infinity)

                ColorPicker(
                    selection: textColorBinding,
                    supportsOpacity: false
                ) {
                    Text(Strings.editorTextColor)
                        .font(Font.mng(10.5, weight: .semibold))
                        .foregroundStyle(Aurum.muted)
                }
                .fixedSize()
                .disabled(editor.selectedText == nil)
                .opacity(editor.selectedText == nil ? 0.45 : 1)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    textToggle(
                        Strings.editorTextBold,
                        active: editor.selectedText?.bold == true
                    ) {
                        editor.updateSelectedText(coalescing: false) {
                            $0.bold.toggle()
                        }
                    }
                    textToggle(
                        Strings.editorTextItalic,
                        active: editor.selectedText?.italic == true
                    ) {
                        editor.updateSelectedText(coalescing: false) {
                            $0.italic.toggle()
                        }
                    }
                    textToggle(
                        Strings.editorTextOutline,
                        active: editor.selectedText?.outline == true
                    ) {
                        editor.updateSelectedText(coalescing: false) {
                            $0.outline.toggle()
                        }
                    }
                    textToggle(
                        Strings.editorTextShadow,
                        active: editor.selectedText?.shadow == true
                    ) {
                        editor.updateSelectedText(coalescing: false) {
                            $0.shadow.toggle()
                        }
                    }
                    selectChip(
                        Strings.editorTextDuplicate,
                        icon: "doc.on.doc",
                        active: false,
                        height: 30,
                        fontSize: 11
                    ) {
                        editor.duplicateSelectedText()
                    }
                    .disabled(editor.selectedText == nil)

                    selectChip(
                        Strings.editorTextDelete,
                        icon: "trash",
                        active: false,
                        height: 30,
                        fontSize: 11,
                        danger: true
                    ) {
                        editor.deleteSelectedText()
                    }
                    .disabled(editor.selectedText == nil)
                }
                .padding(.horizontal, 12)
            }
            .opacity(editor.selectedText == nil ? 0.5 : 1)

            if let selected = editor.selectedText {
                HStack(spacing: 8) {
                    Text(Strings.editorTextOpacity)
                        .font(Font.mng(12))
                        .foregroundStyle(Aurum.muted)
                    Spacer(minLength: 8)
                    Button {
                        editor.setTextOpacity(100)
                    } label: {
                        Text("\(Int((selected.opacity * 100).rounded()))%")
                            .font(Font.mng(11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Aurum.gold)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 36, minHeight: 20)
                            .background(
                                Aurum.gold.opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 6,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.editorTextOpacity)
                    .accessibilityHint(Strings.editorAdjustReset)
                }
                .padding(.horizontal, 14)

                TickSlider(
                    value: Binding(
                        get: {
                            Float(
                                (editor.selectedText?.opacity ?? 1) * 100
                            )
                        },
                        set: { editor.setTextOpacity($0) }
                    ),
                    label: Strings.editorTextOpacity,
                    minimum: 10,
                    maximum: 100,
                    tickStep: 2,
                    ruler: true,
                    onEditingChanged: { editing in
                        if editing {
                            editor.beginEdit()
                        } else {
                            editor.endEdit()
                        }
                    }
                )
                .padding(.horizontal, 12)
            } else {
                Text(Strings.editorTextEmpty)
                    .font(Font.mng(10.5))
                    .foregroundStyle(Aurum.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
    }

    private func textToggle(
        _ title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        selectChip(
            title,
            active: active,
            height: 30,
            fontSize: 11,
            action: action
        )
        .disabled(editor.selectedText == nil)
    }

    private func fontButton(_ font: EditorTextFont) -> some View {
        let active = editor.selectedText?.font == font
        return Button {
            editor.updateSelectedText(coalescing: false) {
                $0.font = font
            }
        } label: {
            Text(font.title)
                .font(fontPreview(font))
                .foregroundStyle(active ? Aurum.gold : Aurum.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 5)
                .frame(minWidth: 44)
                .frame(height: 28)
                .background(
                    active ? Aurum.gold.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(editor.selectedText == nil)
        .opacity(editor.selectedText == nil ? 0.5 : 1)
    }

    private func fontPreview(_ font: EditorTextFont) -> Font {
        switch font {
        case .sys: return Font.mng(11, weight: .semibold)
        case .serif: return .custom("Georgia", size: 11)
        case .mono: return .custom("Menlo", size: 10.5)
        case .round: return .custom("ArialRoundedMTBold", size: 10.5)
        case .heavy: return .custom("Arial-Black", size: 10.5)
        }
    }

    /// The bridge between the hex colour of the layer and SwiftUI's picker.
    private var textColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let text = editor.selectedText else { return .white }
                return Color.mngHex(text.color) ?? .white
            },
            set: { color in
                let hex = hexString(from: color)
                editor.updateSelectedText(coalescing: false) {
                    $0.color = hex
                }
            }
        )
    }

    private func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return "#ffffff"
        }
        return String(
            format: "#%02x%02x%02x",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// The crop pane: the ratio, rotation and two perspective modes with
    /// their reset, plus the context of the open mode. The rotate and flip
    /// tools live in the header, so the pane keeps only framing controls.
    private var cropPane: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(CropMode.allCases) { mode in
                    cropModeButton(mode)
                }

                Button {
                    resetCropMode()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Aurum.text)
                        .frame(width: 36, height: 36)
                        .background(Aurum.glass, in: Circle())
                        .overlay {
                            Circle().stroke(Aurum.glassLine, lineWidth: 1)
                        }
                }
                .buttonStyle(GlassPressStyle(scale: 0.93))
                .accessibilityLabel(
                    cropMode == .ratio
                        ? Strings.editorCropReset
                        : cropMode.title
                )
            }
            .padding(.horizontal, 12)
            .opacity(cropModesHidden ? 0 : 1)
            .allowsHitTesting(!cropModesHidden)
            .animation(.easeOut(duration: 0.18), value: cropModesHidden)

            Group {
                switch cropMode {
                case .ratio:
                    ratioContext
                case .rotation:
                    rotationContext
                case .perspectiveY:
                    perspectiveContext(vertical: true)
                case .perspectiveX:
                    perspectiveContext(vertical: false)
                }
            }
            .frame(minHeight: 44)
        }
    }

    private func cropModeButton(_ mode: CropMode) -> some View {
        let active = cropMode == mode
        let value: String
        switch mode {
        case .ratio:
            value = editor.aspect.title
        case .rotation:
            let angle = Int(editor.rotation) * 90
                + Int(editor.fineRotation.rounded())
            value = "\(angle)°"
        case .perspectiveY:
            value = signedValue(editor.perspectiveY)
        case .perspectiveX:
            value = signedValue(editor.perspectiveX)
        }
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                cropMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(Font.mng(15, weight: .medium))
                    .foregroundStyle(Aurum.gold)
                Text(value)
                    .font(Font.mng(11.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Aurum.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                active
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Aurum.gold.opacity(0.22),
                                Aurum.gold.opacity(0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(Aurum.glass),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        active ? Aurum.gold.opacity(0.40) : Aurum.glassLine,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(GlassPressStyle(scale: 0.97))
        .accessibilityLabel(mode.title)
        .accessibilityValue(value)
    }

    private func signedValue(_ value: Float) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private var ratioContext: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(EditorModel.Aspect.allCases) { aspect in
                            selectChip(
                                aspect.title,
                                active: editor.aspect == aspect,
                                height: 30,
                                fontSize: 11.5
                            ) {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    editor.selectAspect(
                                        aspect,
                                        viewport: stageSize
                                    )
                                }
                                markRatioing()
                            }
                            .id(aspect.rawValue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 5)
                }

                // The fixed gold line of the web's `.au-chipsrail`; the
                // active chip is scrolled under it.
                Capsule()
                    .fill(Aurum.gold)
                    .frame(width: 2, height: 7)
                    .shadow(color: Aurum.gold.opacity(0.65), radius: 4)
                    .allowsHitTesting(false)
            }
            .frame(height: 40)
            .onAppear {
                proxy.scrollTo(editor.aspect.rawValue, anchor: .center)
            }
            .onChange(of: editor.aspect) { _, aspect in
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(aspect.rawValue, anchor: .center)
                }
            }
        }
    }

    /// The web's continuous rotation ruler: −180…180°, one degree per step,
    /// a tick every three degrees and the gold zero mark of the original.
    private var rotationContext: some View {
        TickSlider(
            value: Binding(
                get: { editor.fineRotation },
                set: { editor.setFineRotation($0) }
            ),
            label: Strings.editorCropRotation,
            minimum: -180,
            maximum: 180,
            step: 1,
            tickStep: 3,
            zero: true,
            ruler: true,
            onEditingChanged: { editing in
                if editing {
                    editor.beginEdit()
                } else {
                    editor.endEdit()
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    isGeometryEditing = editing
                }
            }
        )
        .padding(.horizontal, 12)
    }

    /// One axis of the 3D correction: the web's -100…100 ruler with a tick
    /// every two steps. A drag is one undo step, like the rotation ruler, and
    /// it removes the glass blur exactly the same way so the outside of the
    /// frame stays legible while the perspective changes.
    private func perspectiveContext(vertical: Bool) -> some View {
        TickSlider(
            value: Binding(
                get: {
                    vertical ? editor.perspectiveY : editor.perspectiveX
                },
                set: {
                    editor.setPerspective(vertical: vertical, value: $0)
                }
            ),
            label: vertical
                ? Strings.editorCropPerspectiveVertical
                : Strings.editorCropPerspectiveHorizontal,
            minimum: -100,
            maximum: 100,
            step: 1,
            tickStep: 2,
            zero: true,
            ruler: true,
            onEditingChanged: { editing in
                if editing {
                    editor.beginEdit()
                } else {
                    editor.endEdit()
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    isGeometryEditing = editing
                }
            }
        )
        .padding(.horizontal, 12)
    }

    /// The ratio change keeps the chips visible while the rest of the chrome
    /// fades for about half a second, like `markRatioing()` on the web.
    private func markRatioing() {
        ratioResetTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            isRatioing = true
        }
        ratioResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isRatioing = false
            }
        }
    }

    private func resetCropMode() {
        switch cropMode {
        case .rotation:
            editor.resetRotation()
        case .perspectiveY:
            editor.resetPerspective(vertical: true)
        case .perspectiveX:
            editor.resetPerspective(vertical: false)
        case .ratio:
            editor.resetCrop()
            markRatioing()
        }
    }

    /// The shared chip of the editor: a quiet glass cell when off, a gold
    /// soft cell with a gold hairline when on. The optional icon serves the
    /// text pane and the dangerous delete keeps the red label of the web.
    private func selectChip(
        _ title: String,
        icon: String? = nil,
        active: Bool,
        height: CGFloat = 30,
        fontSize: CGFloat = 11,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let foreground: Color
        if danger {
            foreground = Aurum.danger
        } else {
            foreground = active
                ? Aurum.gold
                : Color(red: 0.81, green: 0.80, blue: 0.84)
        }
        let background: Color
        if danger {
            background = Aurum.danger.opacity(0.10)
        } else if active {
            background = Aurum.gold.opacity(0.16)
        } else {
            background = Color.white.opacity(0.055)
        }
        let border: Color
        if danger {
            border = Aurum.danger.opacity(0.30)
        } else if active {
            border = Aurum.gold.opacity(0.38)
        } else {
            border = Color.white.opacity(0.08)
        }

        return Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(Font.mng(fontSize - 1, weight: .semibold))
                }
                Text(title)
                    .font(Font.mng(fontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(GlassPressStyle(scale: 0.96))
    }

    // MARK: - Dock

    /// The dock of the tabs.
    private var dock: some View {
        HStack(spacing: 0) {
            dockTab(.adjust, "slider.horizontal.3", Strings.editorTuneTab)
            dockTab(.filter, "camera.filters", Strings.editorFilterTab)
            dockTab(.text, "textformat", Strings.editorTextTab)
            dockTab(.crop, "crop", Strings.editorCropTab)
        }
        .padding(5)
        .background(Aurum.bg2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Aurum.glassLine, lineWidth: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func dockTab(_ tab: EditorModel.Tab, _ icon: String, _ title: String) -> some View {
        let active = editor.tab == tab
        return Button {
            editor.selectTab(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(Font.mng(16, weight: .medium))
                Text(title)
                    .font(Font.mng(10, weight: .semibold))
            }
            .foregroundStyle(active ? Aurum.gold : Aurum.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                active ? Aurum.goldSoft : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export sheet

    /// The sheet of the save button: the container, the quality and the two
    /// ways of storing the edit, exactly like the web's `au-sheet`.
    private var exportSheet: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    guard phase != .saving else { return }
                    withAnimation(Tokens.Motion.spring) {
                        exportOpen = false
                    }
                }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Aurum.muted.opacity(0.45))
                    .frame(width: 38, height: 4)
                    .padding(.top, 8)

                Text(Strings.editorExportTitle)
                    .font(Font.mng(17, weight: .semibold))
                    .foregroundStyle(Aurum.text)
                    .padding(.top, 12)

                Text(Strings.editorExportSub)
                    .font(Font.mng(12))
                    .foregroundStyle(Aurum.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                    .padding(.top, 4)

                exportMeta

                if phase == .saving {
                    VStack(spacing: 9) {
                        ProgressView()
                            .tint(Aurum.gold)
                        Text(Strings.editorExporting)
                            .font(Font.mng(12))
                            .foregroundStyle(Aurum.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    exportOptions
                }

                if phase != .saving {
                    HStack(spacing: 8) {
                        Button {
                            save(.overwrite)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(Font.mng(13, weight: .semibold))
                                Text(Strings.editorSaveOverwrite)
                                    .font(Font.mng(14, weight: .semibold))
                            }
                            .foregroundStyle(
                                Color(red: 0.10, green: 0.08, blue: 0.03)
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Aurum.gold,
                                in: RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            save(.copy)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                    .font(Font.mng(13, weight: .semibold))
                                Text(Strings.editorSaveCopy)
                                    .font(Font.mng(14, weight: .semibold))
                            }
                            .foregroundStyle(Aurum.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Aurum.glass,
                                in: RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                                .stroke(Aurum.glassLine, lineWidth: 0.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                Button(Strings.editorCancel) {
                    withAnimation(Tokens.Motion.spring) {
                        exportOpen = false
                    }
                }
                .font(Font.mng(13, weight: .semibold))
                .foregroundStyle(Aurum.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .disabled(phase == .saving)
                .opacity(phase == .saving ? 0.4 : 1)
            }
            .padding(.bottom, 6)
            .background(
                Aurum.bg2,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    topTrailingRadius: 20,
                    style: .continuous
                )
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    topTrailingRadius: 20,
                    style: .continuous
                )
                .stroke(Aurum.glassLine, lineWidth: 0.5)
            }
            .transition(.move(edge: .bottom))
        }
        .transition(.opacity)
    }

    private var exportMeta: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(Font.mng(16, weight: .medium))
                .foregroundStyle(Aurum.gold)
                .frame(width: 30, height: 30)
                .background(Aurum.goldSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(editor.exportFileName)
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Aurum.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(exportMetaInfo)
                    .font(Font.mng(11))
                    .foregroundStyle(Aurum.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Aurum.glass,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var exportMetaInfo: String {
        let size = editor.exportSize
        guard size.width > 0 else { return editor.exportFormatLabel }
        return "\(size.width) × \(size.height) px · \(editor.exportFormatLabel) · ~\(editor.exportEstimate)"
    }

    private var exportOptions: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Strings.editorFormat)
                    .font(Font.mng(12))
                    .foregroundStyle(Aurum.muted)
                Spacer()
            }

            HStack(spacing: 6) {
                Text(editor.exportFormatLabel)
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(
                        Color(red: 0.10, green: 0.08, blue: 0.03)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        Aurum.gold,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }

            // PNG is lossless: a quality slider would be misleading, so the
            // row is hidden exactly like the web sheet.
            if editor.exportFormat != .png {
                HStack {
                    Text(Strings.editorQuality)
                        .font(Font.mng(12))
                        .foregroundStyle(Aurum.muted)
                    Spacer()
                    // The web's value chip resets the quality to its default.
                    Button {
                        editor.setSaveQuality(92)
                    } label: {
                        Text("\(editor.saveQuality)%")
                            .font(Font.mng(11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Aurum.gold)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 36, minHeight: 20)
                            .background(
                                Aurum.gold.opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 6,
                                    style: .continuous
                                )
                            )
                            .contentShape(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(Strings.editorQuality): \(editor.saveQuality)%"
                    )
                    .accessibilityHint(Strings.editorAdjustReset)
                }
                .padding(.top, 2)

                TickSlider(
                    value: Binding(
                        get: { Float(editor.saveQuality) },
                        set: { editor.setSaveQuality(Int($0.rounded())) }
                    ),
                    label: Strings.editorQuality,
                    minimum: 10,
                    maximum: 100,
                    tickStep: 3
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func save(_ mode: EditorModel.SaveMode) {
        guard phase == .ready else { return }
        Task {
            phase = .saving
            let saved = await editor.save(
                mode: mode,
                quality: editor.saveQuality
            )
            phase = .ready
            guard saved else { return }
            withAnimation(Tokens.Motion.spring) {
                exportOpen = false
            }
        }
    }
}

/// The tick slider of the editor, ported from the web's `.au-ticks`.
///
/// A glass rail with 2 pt ticks: major marks (every fifth and the zero mark)
/// are taller, the active tick becomes a 30 pt gold pill. In ruler mode the
/// white track slides under a fixed gold centre line, so dragging right walks
/// back through the values exactly like the browser ruler. The adjustment
/// slider uses the ruler; the quality slider uses the direct mode.
private struct TickSlider: View {
    @Binding var value: Float
    var label: String = ""
    /// The range of the slider. The adjustments use -100…100 and the export
    /// quality 10…100.
    var minimum: Float = -100
    var maximum: Float = 100
    /// The value snap. Every slider here is integer-valued.
    var step: Float = 1
    /// The spacing between ticks, matching the web's `tickStep`.
    var tickStep: Float = 2
    /// Draw a taller centre mark at zero.
    var zero: Bool = false
    /// Slide the track under a fixed centre line.
    var ruler: Bool = false
    /// Called when the finger lands and when it lifts. The crop rail uses it
    /// to fade the chrome while the rotation is being dragged.
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var dragStartValue: Float?
    @State private var dragStartX: CGFloat = 0

    private var tickCount: Int {
        max(2, Int(((maximum - minimum) / max(tickStep, 0.0001)).rounded()) + 1)
    }

    private func index(for input: Float) -> Int {
        let raw = ((input - minimum) / max(tickStep, 0.0001)).rounded()
        return min(max(Int(raw), 0), tickCount - 1)
    }

    private func quantize(_ input: Float) -> Float {
        let snap = ((input - minimum) / max(step, 0.0001)).rounded()
        return min(max(minimum + snap * step, minimum), maximum)
    }

    private func apply(_ next: Float) {
        let clamped = min(max(next, minimum), maximum)
        guard abs(clamped - value) > 0.0001 else { return }
        value = clamped
    }

    private func value(at x: CGFloat, width: CGFloat) -> Float {
        let pad: CGFloat = 10
        let usable = max(width - pad * 2, 1)
        let ratio = min(max((x - pad) / usable, 0), 1)
        return quantize(minimum + Float(ratio) * (maximum - minimum))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let ratio = CGFloat(index(for: value)) / CGFloat(max(tickCount - 1, 1))
            let usable = max(width - 20, 1)
            let activeX = ruler ? width / 2 : 10 + ratio * usable

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let trackWidth = ruler ? size.width * 1.18 : max(size.width - 20, 1)
                    let left = ruler
                        ? size.width / 2 - ratio * trackWidth
                        : 10
                    let spacing = trackWidth / CGFloat(max(tickCount - 1, 1))
                    let centerY = size.height / 2

                    for tick in 0..<tickCount {
                        let x = left + CGFloat(tick) * spacing
                        guard x >= -2, x <= size.width + 2 else { continue }
                        let tickValue = minimum + Float(tick) * tickStep
                        let isZero = zero && abs(tickValue) < tickStep / 2
                        let isMajor = tick % 5 == 0 || isZero
                        if tick == index(for: value) { continue }

                        // The ruler has a clear hierarchy: the zero mark is
                        // the tallest, the milestone marks (every fifth tick)
                        // come next, and every other tick is shorter and
                        // thinner so the scale reads at a glance.
                        let height: CGFloat
                        let thickness: CGFloat
                        let color: Color
                        if ruler {
                            height = isZero ? 26 : isMajor ? 22 : 15
                            thickness = isZero ? 2.5 : isMajor ? 2 : 1
                            color = Color.white
                                .opacity(isZero ? 0.98 : 0.72)
                        } else {
                            height = isZero ? 22 : isMajor ? 20 : 14
                            thickness = isZero ? 2.5 : isMajor ? 2 : 1
                            color = Color.white
                                .opacity(isZero ? 0.92 : 0.58)
                        }
                        let rect = CGRect(
                            x: x - thickness / 2,
                            y: centerY - height / 2,
                            width: thickness,
                            height: height
                        )
                        context.fill(
                            Path(
                                roundedRect: rect,
                                cornerRadius: min(1, thickness / 2)
                            ),
                            with: .color(color)
                        )
                    }
                }

                // The active mark is a separate view so it can glow like the
                // web's gold tick without a Canvas shadow filter.
                Rectangle()
                    .fill(ruler ? Color.white : Aurum.gold)
                    .frame(width: 2, height: 30)
                    .position(x: activeX, y: 20)
                    .shadow(
                        color: ruler ? .clear : Aurum.gold.opacity(0.55),
                        radius: 4.5
                    )

                if ruler {
                    // The fixed gold line the ruler slides under.
                    Capsule()
                        .fill(Aurum.gold)
                        .frame(width: 2, height: 30)
                        .position(x: width / 2, y: 20)
                        .shadow(color: Aurum.gold.opacity(0.72), radius: 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: 40)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                Color(red: 0.031, green: 0.031, blue: 0.039)
                                    .opacity(0.30)
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStartValue == nil {
                            dragStartValue = value
                            dragStartX = gesture.startLocation.x
                            onEditingChanged?(true)
                            if !ruler {
                                apply(value(at: gesture.location.x, width: width))
                            }
                        }
                        if ruler {
                            let start = dragStartValue ?? value
                            let delta = (gesture.location.x - dragStartX) / usable
                            apply(
                                quantize(
                                    start - Float(delta) * (maximum - minimum)
                                )
                            )
                        } else {
                            apply(value(at: gesture.location.x, width: width))
                        }
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        onEditingChanged?(false)
                    }
            )
        }
        .frame(height: 40)
        .sensoryFeedback(.selection, trigger: index(for: value))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                apply(value + max(step, 1))
            case .decrement:
                apply(value - max(step, 1))
            @unknown default:
                break
            }
        }
    }
}

/// The crop rectangle with its eight handles, drawn over the preview.
///
/// A free frame moves one side at a time. A ratio preset grows around the
/// centre, like the web crop, where the frame stays centred and only its
/// scale changes.
private struct CropOverlay: View {
    let crop: EditorCrop
    let isFixedAspect: Bool
    let scrimVisible: Bool
    let showGrid: Bool
    let isGeometryEditing: Bool
    let onChange: (EditorCrop) -> Void
    let onBegin: () -> Void
    let onDragState: (Bool) -> Void

    @State private var origin: EditorCrop?
    @State private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rect = CGRect(
                x: CGFloat(crop.x) * size.width,
                y: CGFloat(crop.y) * size.height,
                width: CGFloat(crop.width) * size.width,
                height: CGFloat(crop.height) * size.height
            )

            ZStack {
                // A real glass scrim: the crop frame is a hole, not a
                // translucent shadow. The world outside is blurred and
                // dimmed while the photo inside stays untouched.
                //
                // While a rotation or perspective ruler is held the blur is
                // removed and only the dim remains, matching
                // `.au-root.au-rotating .au-scrim` on the web: the area
                // outside the frame must stay legible while the geometry
                // changes. The two perspective sliders follow the same rule
                // as the angle ruler.
                CropHoleShape(hole: rect)
                    .fill(
                        .ultraThinMaterial,
                        style: FillStyle(eoFill: true)
                    )
                    .opacity(isGeometryEditing ? 0 : 1)
                    .animation(
                        .easeInOut(duration: 0.16),
                        value: isGeometryEditing
                    )
                    .overlay {
                        CropHoleShape(hole: rect)
                            .fill(
                                Color.black.opacity(isGeometryEditing ? 0.42 : 0.30),
                                style: FillStyle(eoFill: true)
                            )
                    }
                    .opacity(scrimVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(
                        .easeInOut(duration: 0.18),
                        value: scrimVisible
                    )

                cropGrid(rect: rect)
                    .opacity(showGrid ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(
                        .easeInOut(duration: 0.16),
                        value: showGrid
                    )

                // The frame itself drags the whole rectangle.
                Rectangle()
                    .stroke(
                        dragging || isGeometryEditing
                            ? Aurum.gold
                            : Color.white.opacity(0.7),
                        lineWidth: dragging || isGeometryEditing ? 1.5 : 1
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(
                        color: dragging || isGeometryEditing
                            ? Aurum.gold.opacity(0.35)
                            : Color.black.opacity(0.18),
                        radius: dragging || isGeometryEditing ? 12 : 10,
                        y: 4
                    )
                    .contentShape(Rectangle())
                    .gesture(moveGesture(size: size))

                // The four corners, two bevelled gold bars each.
                ForEach(Corner.allCases, id: \.self) { corner in
                    let point = corner.point(in: rect)
                    cornerHandle(corner)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .position(x: point.x, y: point.y)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    onChange(
                                        resized(
                                            start: begin(),
                                            dx: Float(gesture.translation.width),
                                            dy: Float(gesture.translation.height),
                                            size: size,
                                            dirX: corner.dirX,
                                            dirY: corner.dirY
                                        )
                                    )
                                }
                                .onEnded { _ in
                                    finishDrag()
                                }
                        )
                }

                // The four edges, which resize one side.
                ForEach(Side.allCases, id: \.self) { edge in
                    let point = edge.point(in: rect)
                    edgeHandle(edge)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .position(x: point.x, y: point.y)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    onChange(
                                        resized(
                                            start: begin(),
                                            dx: Float(gesture.translation.width),
                                            dy: Float(gesture.translation.height),
                                            size: size,
                                            dirX: edge.dirX,
                                            dirY: edge.dirY
                                        )
                                    )
                                }
                                .onEnded { _ in
                                    finishDrag()
                                }
                        )
                }
            }
        }
    }

    /// Drag the whole frame inside the image.
    private func moveGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let start = begin()
                let dx = Float(
                    gesture.translation.width / max(size.width, 1)
                )
                let dy = Float(
                    gesture.translation.height / max(size.height, 1)
                )
                var next = start
                next.x = min(max(start.x + dx, 0), 1 - start.width)
                next.y = min(max(start.y + dy, 0), 1 - start.height)
                onChange(next)
            }
            .onEnded { _ in
                finishDrag()
            }
    }

    /// Remember the rectangle before the first change of a gesture, and give
    /// the model one undo step for the whole gesture.
    private func begin() -> EditorCrop {
        if let origin {
            return origin
        }
        let start = crop
        origin = start
        onBegin()
        setDragging(true)
        return start
    }

    private func finishDrag() {
        origin = nil
        setDragging(false)
    }

    private func setDragging(_ active: Bool) {
        guard dragging != active else { return }
        dragging = active
        onDragState(active)
    }

    /// The composition grid only appears while the frame is actively used,
    /// exactly like the web's `.au-grid`.
    private func cropGrid(rect: CGRect) -> some View {
        Path { path in
            let fractions: [CGFloat] = [1.0 / 3.0, 2.0 / 3.0]
            for fraction in fractions {
                let x = rect.minX + rect.width * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.17), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    /// A 24 pt corner made of two bevelled gold bars. The bright face always
    /// points towards the corner's outer edge, like the CSS gradients.
    private func cornerHandle(_ corner: Corner) -> some View {
        let bevel = LinearGradient(
            stops: [
                .init(
                    color: Color(red: 1.0, green: 0.953, blue: 0.831),
                    location: 0
                ),
                .init(
                    color: Color(red: 0.969, green: 0.827, blue: 0.573),
                    location: 0.32
                ),
                .init(
                    color: Color(red: 0.886, green: 0.678, blue: 0.322),
                    location: 0.64
                ),
                .init(
                    color: Color(red: 0.561, green: 0.369, blue: 0.106),
                    location: 1
                ),
            ],
            startPoint: corner.isBottom ? .bottom : .top,
            endPoint: corner.isBottom ? .top : .bottom
        )
        let side = LinearGradient(
            stops: [
                .init(
                    color: Color(red: 1.0, green: 0.953, blue: 0.831),
                    location: 0
                ),
                .init(
                    color: Color(red: 0.969, green: 0.827, blue: 0.573),
                    location: 0.32
                ),
                .init(
                    color: Color(red: 0.886, green: 0.678, blue: 0.322),
                    location: 0.64
                ),
                .init(
                    color: Color(red: 0.561, green: 0.369, blue: 0.106),
                    location: 1
                ),
            ],
            startPoint: corner.isTrailing ? .trailing : .leading,
            endPoint: corner.isTrailing ? .leading : .trailing
        )
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(bevel)
                .frame(width: 24, height: 3.5)
                .position(x: 12, y: corner.isBottom ? 22.25 : 1.75)
            Rectangle()
                .fill(side)
                .frame(width: 3.5, height: 24)
                .position(x: corner.isTrailing ? 22.25 : 1.75, y: 12)
        }
        .frame(width: 24, height: 24)
        .shadow(
            color: dragging
                ? Aurum.gold.opacity(0.8)
                : Color.black.opacity(0.65),
            radius: dragging ? 9 : 1.5,
            y: 1
        )
    }

    @ViewBuilder
    private func edgeHandle(_ edge: Side) -> some View {
        if edge.isHorizontalBar {
            Capsule()
                .fill(Aurum.gold)
                .frame(width: 20, height: 2)
                .shadow(
                    color: dragging
                        ? Aurum.gold.opacity(0.7)
                        : Color.black.opacity(0.55),
                    radius: dragging ? 7 : 3
                )
        } else {
            Capsule()
                .fill(Aurum.gold)
                .frame(width: 2, height: 20)
                .shadow(
                    color: dragging
                        ? Aurum.gold.opacity(0.7)
                        : Color.black.opacity(0.55),
                    radius: dragging ? 7 : 3
                )
        }
    }

    /// Resize the rectangle from one handle. `dirX`/`dirY` are -1, 0 or 1.
    private func resized(
        start: EditorCrop,
        dx: Float,
        dy: Float,
        size: CGSize,
        dirX: Float,
        dirY: Float
    ) -> EditorCrop {
        let width = max(Float(size.width), 1)
        let height = max(Float(size.height), 1)

        if isFixedAspect {
            // The frame stays centred: a 2× size delta makes the dragged
            // edge follow the finger 1:1 while the opposite edge grows
            // symmetrically, the way the web crop does.
            let startWidth = start.width * width
            let startHeight = start.height * height
            let centerX = (start.x + start.width / 2) * width
            let centerY = (start.y + start.height / 2) * height
            var factor: Float = 1
            if dirX != 0, dirY != 0 {
                let denominator = max(
                    startWidth * startWidth + startHeight * startHeight,
                    1
                )
                factor = 1 + (
                    dirX * dx * 2 * startWidth
                        + dirY * dy * 2 * startHeight
                ) / denominator
            } else if dirX != 0 {
                factor = 1 + (dirX * dx * 2) / max(startWidth, 1)
            } else if dirY != 0 {
                factor = 1 + (dirY * dy * 2) / max(startHeight, 1)
            }

            let maxWidth = 2 * min(centerX, width - centerX)
            let maxHeight = 2 * min(centerY, height - centerY)
            let maxFactor = min(
                maxWidth / max(startWidth, 1),
                maxHeight / max(startHeight, 1)
            )
            let minFactor = max(
                24 / max(startWidth, 1),
                24 / max(startHeight, 1)
            )
            factor = min(max(factor, minFactor), max(maxFactor, minFactor))

            let nextWidth = startWidth * factor
            let nextHeight = startHeight * factor
            return EditorCrop(
                x: (centerX - nextWidth / 2) / width,
                y: (centerY - nextHeight / 2) / height,
                width: nextWidth / width,
                height: nextHeight / height
            )
        }

        // A free frame: only the dragged sides move.
        var x = start.x
        var y = start.y
        var nextWidth = start.width
        var nextHeight = start.height
        let normalizedX = dx / width
        let normalizedY = dy / height
        if dirX > 0 {
            nextWidth = min(
                max(start.width + normalizedX, 0.02),
                1 - start.x
            )
        } else if dirX < 0 {
            let grown = min(
                max(start.width - normalizedX, 0.02),
                start.x + start.width
            )
            nextWidth = grown
            x = start.x + (start.width - grown)
        }
        if dirY > 0 {
            nextHeight = min(
                max(start.height + normalizedY, 0.02),
                1 - start.y
            )
        } else if dirY < 0 {
            let grown = min(
                max(start.height - normalizedY, 0.02),
                start.y + start.height
            )
            nextHeight = grown
            y = start.y + (start.height - grown)
        }
        return EditorCrop(
            x: x,
            y: y,
            width: nextWidth,
            height: nextHeight
        )
    }

    /// The frame with a rectangular hole, filled with the even-odd rule.
    private struct CropHoleShape: Shape {
        var hole: CGRect

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addRect(rect)
            path.addRect(hole)
            return path
        }
    }

    private enum Corner: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var dirX: Float {
            self == .topRight || self == .bottomRight ? 1 : -1
        }

        var dirY: Float {
            self == .bottomLeft || self == .bottomRight ? 1 : -1
        }

        var isBottom: Bool {
            self == .bottomLeft || self == .bottomRight
        }

        var isTrailing: Bool {
            self == .topRight || self == .bottomRight
        }

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
    }

    private enum Side: CaseIterable {
        case top
        case bottom
        case leading
        case trailing

        var dirX: Float {
            switch self {
            case .leading: return -1
            case .trailing: return 1
            case .top, .bottom: return 0
            }
        }

        var dirY: Float {
            switch self {
            case .top: return -1
            case .bottom: return 1
            case .leading, .trailing: return 0
            }
        }

        var isHorizontalBar: Bool {
            self == .top || self == .bottom
        }

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .top: return CGPoint(x: rect.midX, y: rect.minY)
            case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
            case .leading: return CGPoint(x: rect.minX, y: rect.midY)
            case .trailing: return CGPoint(x: rect.maxX, y: rect.midY)
            }
        }
    }
}
