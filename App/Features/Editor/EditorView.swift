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

            if phase == .loading || phase == .saving {
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
                    Task {
                        phase = .saving
                        await editor.save()
                        phase = .ready
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

                if let preview = editor.preview {
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

                        if editor.tab == .crop {
                            CropOverlay(
                                crop: editor.crop,
                                onChange: { editor.setCrop($0) },
                                onCommit: { editor.commitCrop() }
                            )
                            .frame(width: fitted.width, height: fitted.height)
                            .position(
                                x: geometry.size.width / 2,
                                y: geometry.size.height / 2
                            )
                        }
                    }
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

                Button(Strings.editorCropApply) {
                    editor.commitCrop()
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
}

/// The slider of the editor: a row of ticks, the chosen one is taller and
/// gold.
private struct TickSlider: View {
    @Binding var value: Float

    private let steps = 25

    var body: some View {
        GeometryReader { geometry in
            let step = geometry.size.width / CGFloat(steps - 1)
            let index = Int(((value + 100) / 200) * Float(steps - 1))
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
                        let next = Float(ratio) * 200 - 100
                        value = min(max(next, -100), 100)
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

/// The crop rectangle with its corner handles, drawn over the preview.
private struct CropOverlay: View {
    let crop: EditorCrop
    let onChange: (EditorCrop) -> Void
    let onCommit: () -> Void

    @State private var origin: EditorCrop?

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(
                x: CGFloat(crop.x) * geometry.size.width,
                y: CGFloat(crop.y) * geometry.size.height,
                width: CGFloat(crop.width) * geometry.size.width,
                height: CGFloat(crop.height) * geometry.size.height
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

                Rectangle()
                    .stroke(Aurum.gold, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let start = origin ?? crop
                                if origin == nil {
                                    origin = start
                                }
                                let dx = Float(
                                    gesture.translation.width / max(geometry.size.width, 1)
                                )
                                let dy = Float(
                                    gesture.translation.height / max(geometry.size.height, 1)
                                )
                                var next = start
                                next.x = min(max(start.x + dx, 0), 1 - start.width)
                                next.y = min(max(start.y + dy, 0), 1 - start.height)
                                onChange(next)
                            }
                            .onEnded { _ in
                                origin = nil
                                onCommit()
                            }
                    )

                // The four corners, which resize the rectangle.
                ForEach(Corner.allCases, id: \.self) { corner in
                    let point = corner.point(in: rect)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Aurum.gold, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .position(x: point.x, y: point.y)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let start = origin ?? crop
                                    if origin == nil {
                                        origin = start
                                    }
                                    let dx = Float(
                                        gesture.translation.width / max(geometry.size.width, 1)
                                    )
                                    let dy = Float(
                                        gesture.translation.height / max(geometry.size.height, 1)
                                    )
                                    var next = start
                                    if corner.affectsX {
                                        next.width = min(max(start.width + dx, 0.08), 1)
                                        next.x = min(
                                            max(start.x + (corner.inX ? dx : 0), 0),
                                            1 - next.width
                                        )
                                    }
                                    if corner.affectsY {
                                        next.height = min(max(start.height + dy, 0.08), 1)
                                        next.y = min(
                                            max(start.y + (corner.inY ? dy : 0), 0),
                                            1 - next.height
                                        )
                                    }
                                    onChange(next)
                                }
                                .onEnded { _ in
                                    origin = nil
                                    onCommit()
                                }
                        )
                }
            }
        }
    }

    private enum Corner: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var affectsX: Bool { true }
        var affectsY: Bool { true }
        /// The corner that moves towards the inside of the rectangle.
        var inX: Bool { self == .topRight || self == .bottomRight }
        var inY: Bool { self == .topLeft || self == .bottomRight }

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
    }
}
