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
                stage
                pane
                dock
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
            editor.close()
        }
        .onChange(of: editor.tab) { _, tab in
            // The crop frame is drawn over the fitted photo, not over the
            // zoomed one, so entering the crop resets the stage zoom.
            guard tab == .crop else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                stageScale = 1
                stageOffset = .zero
                gestureScale = 1
                gestureOffset = .zero
            }
        }
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

    /// The photo with the crop rectangle on top.
    ///
    /// The stage can be panned, pinched and tapped twice, so the person can
    /// look at a detail before cropping.
    private var stage: some View {
        GeometryReader { geometry in
            ZStack {
                Aurum.bg

                if let preview = displayedPreview {
                    let fitted = fittedSize(image: preview, in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
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

                        if editor.tab == .crop, !isComparing {
                            CropOverlay(
                                crop: editor.crop,
                                isFixedAspect: editor.aspect != .free,
                                onChange: { editor.setCrop($0) },
                                onBegin: { editor.beginCropEdit() }
                            )
                            .frame(width: fitted.width, height: fitted.height)
                            .position(
                                x: geometry.size.width / 2,
                                y: geometry.size.height / 2
                            )
                        }
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
                    }
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
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.22)) {
                    if stageScale > 1.05 {
                        stageScale = 1
                        stageOffset = .zero
                    } else {
                        stageScale = 2.5
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
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
        VStack(spacing: 10) {
            switch editor.tab {
            case .adjust:
                adjustPane
            case .filter:
                filterPane
            case .crop:
                cropPane
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Aurum.bg2.opacity(0.92))
    }

    /// The chips of the adjustments and the slider of the one that is open.
    private var adjustPane: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chip(
                        Strings.editorAuto,
                        icon: "wand.and.stars",
                        active: false
                    ) {
                        Task { await editor.applyAutoTune() }
                    }
                    ForEach(EditorModel.Adjustment.allCases) { key in
                        chip(
                            key.shortTitle,
                            icon: nil,
                            active: editor.activeAdjustment == key
                        ) {
                            editor.selectAdjustment(key)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            TickSlider(
                value: Binding(
                    get: {
                        editor.activeAdjustment.value(in: editor.adjustments)
                    },
                    set: { editor.setActiveAdjustment(value: $0) }
                )
            )
            .padding(.horizontal, 12)

            HStack {
                Text(editor.activeAdjustment.title)
                    .font(Font.mng(12))
                    .foregroundStyle(Aurum.muted)
                Spacer()
                Text("\(Int(editor.activeAdjustment.value(in: editor.adjustments)))")
                    .font(Font.mng(12, weight: .semibold))
                    .foregroundStyle(Aurum.gold)
                Spacer()
                Button(Strings.editorAdjustReset) {
                    editor.resetAdjustments()
                }
                .font(Font.mng(12, weight: .semibold))
                .foregroundStyle(Aurum.muted)
            }
            .padding(.horizontal, 14)
        }
    }

    /// The presets, each with a preview of the photo.
    private var filterPane: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EditorFilter.allCases, id: \.self) { filter in
                    Button {
                        editor.setFilter(filter)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Aurum.glass)
                                    .frame(width: 62, height: 62)
                                if let thumbnail = editor.filterThumbnails[filter] {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 58, height: 58)
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        )
                                } else {
                                    Image(systemName: "photo")
                                        .font(Font.mng(20))
                                        .foregroundStyle(Aurum.muted)
                                }
                            }
                            Text(Strings.editorFilterTitle(filter))
                                .font(Font.mng(10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            editor.filter == filter ? Aurum.gold : Aurum.text
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    editor.filter == filter ? Aurum.gold : .clear,
                                    lineWidth: 1.5
                                )
                                .padding(-3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    /// The presets of the crop and the rail of the rotation.
    private var cropPane: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(EditorModel.Aspect.allCases) { aspect in
                        chip(aspect.title, icon: nil, active: editor.aspect == aspect) {
                            editor.applyAspect(aspect)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            RotationRail(
                value: Binding(
                    get: { Double(editor.rotation) },
                    set: { editor.setRotation(Int($0)) }
                )
            )
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Button(Strings.editorCropReset) {
                    editor.resetCrop()
                }
                .font(Font.mng(13, weight: .semibold))
                .foregroundStyle(Aurum.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Aurum.glass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.plain)

                Button(Strings.editorCropDone) {
                    editor.finishCrop()
                }
                .font(Font.mng(13, weight: .semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.03))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Aurum.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }

    private func chip(
        _ title: String,
        icon: String?,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(Font.mng(11, weight: .semibold))
                }
                Text(title)
                    .font(Font.mng(12, weight: .semibold))
            }
            .foregroundStyle(active ? Color(red: 0.10, green: 0.08, blue: 0.03) : Aurum.text)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                active ? AnyShapeStyle(Aurum.gold) : AnyShapeStyle(Aurum.glass),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(Aurum.glassLine, lineWidth: active ? 0 : 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dock

    /// The dock of the tabs.
    private var dock: some View {
        HStack(spacing: 0) {
            dockTab(.adjust, "slider.horizontal.3", Strings.editorTuneTab)
            dockTab(.filter, "camera.filters", Strings.editorFilterTab)
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
                    Text("\(editor.saveQuality)%")
                        .font(Font.mng(12, weight: .semibold))
                        .foregroundStyle(Aurum.gold)
                }
                .padding(.top, 2)

                TickSlider(
                    value: Binding(
                        get: { Float(editor.saveQuality) },
                        set: { editor.setSaveQuality(Int($0.rounded())) }
                    ),
                    minimum: 10,
                    maximum: 100
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

/// The slider of the editor: a row of ticks, the chosen one is taller and
/// gold.
private struct TickSlider: View {
    @Binding var value: Float
    /// The range of the slider. The adjustments use -100…100, the export
    /// quality 10…100.
    var minimum: Float = -100
    var maximum: Float = 100

    private let steps = 25

    var body: some View {
        GeometryReader { geometry in
            let span = max(maximum - minimum, 0.001)
            let index = min(
                max(Int(((value - minimum) / span) * Float(steps - 1)), 0),
                steps - 1
            )
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<steps, id: \.self) { tick in
                    Rectangle()
                        .fill(tick == index ? Aurum.gold : Aurum.tick)
                        .frame(width: 2, height: tick == index ? 20 : 11)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = gesture.location.x / max(geometry.size.width, 1)
                        let next = minimum + Float(ratio) * span
                        value = min(max(next, minimum), maximum)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: index)
        }
        .frame(height: 30)
    }
}

/// The rail of the rotation: the four angles of the editor.
private struct RotationRail: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { tick in
                Button {
                    value = Double(tick)
                } label: {
                    Text("\(tick * 90)°")
                        .font(Font.mng(12, weight: .semibold))
                        .foregroundStyle(Int(value) == tick ? Aurum.gold : Aurum.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            Int(value) == tick ? Aurum.goldSoft : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
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
    let onChange: (EditorCrop) -> Void
    let onBegin: () -> Void

    @State private var origin: EditorCrop?

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
                // The ground outside of the rectangle is darker.
                Color.black.opacity(0.5)
                    .mask {
                        Rectangle()
                            .overlay {
                                Rectangle()
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }

                thirds(rect: rect)

                Rectangle()
                    .stroke(Aurum.gold, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let start = begin()
                                let dx = Float(
                                    gesture.translation.width
                                        / max(size.width, 1)
                                )
                                let dy = Float(
                                    gesture.translation.height
                                        / max(size.height, 1)
                                )
                                var next = start
                                next.x = min(
                                    max(start.x + dx, 0),
                                    1 - start.width
                                )
                                next.y = min(
                                    max(start.y + dy, 0),
                                    1 - start.height
                                )
                                onChange(next)
                            }
                            .onEnded { _ in
                                origin = nil
                            }
                    )

                // The four corners, which resize two sides at once.
                ForEach(Corner.allCases, id: \.self) { corner in
                    let point = corner.point(in: rect)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Aurum.gold, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                        .position(x: point.x, y: point.y)
                        .gesture(
                            DragGesture()
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
                                    origin = nil
                                }
                        )
                }

                // The four edges, which resize one side.
                ForEach(Edge.allCases, id: \.self) { edge in
                    let point = edge.point(in: rect)
                    edgeBar(edge)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                        .position(x: point.x, y: point.y)
                        .gesture(
                            DragGesture()
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
                                    origin = nil
                                }
                        )
                }
            }
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
        return start
    }

    private func thirds(rect: CGRect) -> some View {
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
        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeBar(_ edge: Edge) -> some View {
        if edge.isHorizontalBar {
            Capsule()
                .fill(Aurum.gold)
                .frame(width: 26, height: 3)
        } else {
            Capsule()
                .fill(Aurum.gold)
                .frame(width: 3, height: 26)
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

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
    }

    private enum Edge: CaseIterable {
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
