import MNGEdit
import MNGKit
import SwiftUI
import UIKit

/// The standalone collage screen, opened from the viewer.
///
/// It is deliberately not a tab of `EditorView`: the web ships it as its own
/// surface (`collage.html`), and a collage edits several photos while the
/// editor edits one. The geometry and the pixels live in `MNGEdit.Collage`.
struct CollageView: View {
    let shell: ShellModel
    /// Photos of the library page, used by the add sheet.
    let candidates: [Item]

    @Environment(\.dismiss) private var dismiss
    @State private var collage: CollageModel
    @State private var pickerOpen = false

    init(model: ShellModel, seed: Item, candidates: [Item]) {
        shell = model
        self.candidates = candidates
        _collage = State(
            initialValue: CollageModel(
                client: model.client,
                seed: [seed]
            )
        )
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                content
                footer
            }

            status
        }
        .preferredColorScheme(.dark)
        .animation(Tokens.Motion.fade, value: collage.message)
        .task {
            let shell = self.shell
            collage.onUnauthorized = { [weak shell] in
                shell?.expireSession()
            }
            await collage.start()
        }
        .onDisappear {
            collage.stop()
        }
        .sheet(isPresented: $pickerOpen) {
            CollagePickerView(
                client: shell.client,
                items: candidates,
                existing: Set(collage.items.map(\.id)),
                limit: Collage.maxCells - collage.items.count
            ) { picked in
                Task { await collage.add(picked) }
            }
        }
        .sheet(item: exportBinding) { file in
            ActivityView(url: file.url)
                .ignoresSafeArea()
        }
    }

    private var background: some View {
        LinearGradient(
            stops: [
                .init(
                    color: Color(red: 0.09, green: 0.09, blue: 0.11),
                    location: 0
                ),
                .init(
                    color: Color(red: 0.039, green: 0.039, blue: 0.051),
                    location: 0.58
                ),
                .init(
                    color: Color(red: 0.02, green: 0.02, blue: 0.024),
                    location: 1
                ),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Aurum.text)
                    .frame(width: 34, height: 34)
                    .background(Aurum.glass, in: Circle())
                    .overlay {
                        Circle().stroke(Aurum.glassLine, lineWidth: 0.5)
                    }
            }
            .accessibilityLabel(Strings.close)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2")
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Aurum.gold)
                    Text(Strings.collageTitle)
                        .font(Font.mng(17, weight: .bold))
                        .foregroundStyle(Aurum.text)
                }
                Text(subtitle)
                    .font(Font.mng(11.5))
                    .foregroundStyle(Aurum.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, alignment: .leading)

            Spacer(minLength: 8)

            Button {
                openPicker()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(Font.mng(12, weight: .bold))
                    Text(Strings.collageAdd)
                        .font(Font.mng(12, weight: .bold))
                }
                .foregroundStyle(Aurum.text)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Aurum.glass, in: Capsule())
                .overlay {
                    Capsule().stroke(Aurum.glassLine, lineWidth: 0.5)
                }
            }
            .disabled(!collage.canAdd)
            .opacity(collage.canAdd ? 1 : 0.4)
            .accessibilityLabel(Strings.collageAdd)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        guard collage.hasEnough else { return Strings.collageEmptyBody }
        return "\(Strings.collageCount(collage.images.count)) · "
            + Strings.collageLayouts.lowercased()
    }

    // MARK: - Body

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                CollageStage(
                    model: collage,
                    onChoose: openPicker
                )
                .padding(.horizontal, 14)

                if !collage.layouts.isEmpty {
                    CollageRail(model: collage)
                }

                CollagePanel(model: collage)
            }
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .overlay {
            if collage.isLoadingPhotos && collage.hasEnough {
                ProgressView()
                    .tint(Aurum.gold)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(Strings.collageCount(collage.images.count))
                .font(Font.mng(11.5))
                .foregroundStyle(Aurum.muted)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Task { await collage.save() }
            } label: {
                HStack(spacing: 7) {
                    if collage.isExporting {
                        ProgressView()
                            .tint(Color(red: 0.165, green: 0.11, blue: 0.024))
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(Font.mng(13, weight: .bold))
                    }
                    Text(
                        collage.isExporting
                            ? Strings.collageSaving
                            : Strings.collageSave
                    )
                    .font(Font.mng(12.5, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.165, green: 0.11, blue: 0.024))
                .padding(.horizontal, 19)
                .frame(height: 38)
                .background(goldFill, in: Capsule())
                .overlay {
                    Capsule().stroke(
                        Color(red: 1, green: 0.922, blue: 0.745).opacity(0.6),
                        lineWidth: 1
                    )
                }
                .shadow(color: Aurum.goldStrong.opacity(0.26), radius: 10, y: 6)
            }
            .disabled(!collage.hasEnough || collage.isExporting)
            .opacity(collage.hasEnough ? 1 : 0.32)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Color(red: 0.039, green: 0.039, blue: 0.051).opacity(0.82))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Aurum.glassLine)
                .frame(height: 0.5)
        }
    }

    private var goldFill: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: Color(red: 0.976, green: 0.839, blue: 0.576),
                    location: 0
                ),
                .init(color: Aurum.goldStrong, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Status and share

    @ViewBuilder
    private var status: some View {
        if let message = collage.message {
            VStack {
                Spacer()
                Text(message)
                    .font(Font.mng(11.5, weight: .medium))
                    .foregroundStyle(Aurum.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Color(red: 0.078, green: 0.078, blue: 0.098)
                            .opacity(0.96),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().stroke(
                            Aurum.gold.opacity(0.3),
                            lineWidth: 1
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 74)
                    .transition(.opacity)
            }
            .allowsHitTesting(false)
        }
    }

    private struct ExportFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private var exportBinding: Binding<ExportFile?> {
        Binding(
            get: {
                collage.exportURL.map(ExportFile.init(url:))
            },
            set: { next in
                if next == nil {
                    collage.clearExport()
                }
            }
        )
    }

    private func close() {
        collage.stop()
        dismiss()
    }

    /// The seed load owns the photo list for a moment. Opening the picker in
    /// that window would race the first decode, so the empty state and the
    /// header share this guard.
    private func openPicker() {
        guard collage.canAdd else { return }
        pickerOpen = true
    }
}

// MARK: - Stage

/// The square preview and its pan / pinch / double-tap gestures.
private struct CollageStage: View {
    let model: CollageModel
    let onChoose: () -> Void

    @State private var stageSide: CGFloat = 320
    @State private var dragStart = CGSize.zero
    @State private var dragging = false
    @State private var moved = false
    @State private var pinchStart: Double?

    var body: some View {
        ZStack {
            Color(red: 0.047, green: 0.047, blue: 0.063)

            if let preview = model.preview {
                Image(uiImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasEnough {
                ProgressView()
                    .tint(Aurum.gold)
            }

            if !model.hasEnough {
                emptyState
            }

            if model.hasEnough && model.hintVisible {
                hint
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 560)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 23, y: 18)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        stageSide = min(proxy.size.width, proxy.size.height)
                    }
                    .onChange(of: proxy.size) { _, size in
                        stageSide = max(1, min(size.width, size.height))
                    }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            dragGesture,
            including: model.hasEnough ? .all : .none
        )
        .simultaneousGesture(
            pinchGesture,
            including: model.hasEnough ? .all : .none
        )
        .simultaneousGesture(
            doubleTapGesture,
            including: model.hasEnough ? .all : .none
        )
        .animation(Tokens.Motion.fade, value: model.hintVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.collageCanvasLabel)
        .accessibilityValue(
            Strings.collageCount(model.images.count)
        )
    }

    private var failure: String? {
        if case let .failed(text) = model.phase { return text }
        return nil
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if model.isLoading {
                ProgressView()
                    .tint(Aurum.gold)
                    .controlSize(.regular)
                Text(Strings.collageLoading)
                    .font(Font.mng(12.5))
                    .foregroundStyle(Aurum.muted)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Aurum.gold.opacity(0.55))
                Text(
                    failure == nil
                        ? Strings.collageEmptyTitle
                        : Strings.collageOpenFailTitle
                )
                .font(Font.mng(14, weight: .bold))
                .foregroundStyle(Aurum.text)
                Text(failure ?? Strings.collageEmptyBody)
                    .font(Font.mng(12.5))
                    .foregroundStyle(Aurum.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onChoose) {
                    Text(Strings.collageChoose)
                        .font(Font.mng(12.5, weight: .bold))
                        .foregroundStyle(
                            Color(red: 0.165, green: 0.11, blue: 0.024)
                        )
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(
                                        red: 0.976,
                                        green: 0.839,
                                        blue: 0.576
                                    ),
                                    Color(
                                        red: 0.886,
                                        green: 0.678,
                                        blue: 0.322
                                    ),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                }
                .opacity(model.canAdd ? 1 : 0.4)
                .disabled(!model.canAdd)
            }
        }
        .padding(24)
    }

    private var hint: some View {
        VStack {
            Spacer()
            Text(Strings.collageHint)
                .font(Font.mng(10.5))
                .foregroundStyle(Aurum.text.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pinchStart != nil {
                    // Keep the translation fresh so the remaining finger does
                    // not jump when the pinch lets go.
                    dragStart = value.translation
                    return
                }
                if !dragging {
                    dragging = true
                    dragStart = value.translation
                    model.selectCell(at: normalized(value.startLocation))
                    return
                }
                let dx = value.translation.width - dragStart.width
                let dy = value.translation.height - dragStart.height
                guard abs(dx) + abs(dy) > 0.01 else { return }
                if !moved {
                    moved = true
                    model.beginGesture()
                }
                dragStart = value.translation
                model.panSelected(dx: dx, dy: dy, side: stageSide)
            }
            .onEnded { _ in
                dragging = false
                dragStart = .zero
                if moved {
                    moved = false
                    model.endGesture()
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil {
                    pinchStart = model.selectedCell?.zoom ?? 1
                    model.beginGesture()
                }
                model.setPinchZoom(
                    start: pinchStart ?? 1,
                    magnification: Double(value.magnification)
                )
            }
            .onEnded { _ in
                pinchStart = nil
                model.endGesture()
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                model.resetCell(at: normalized(value.location))
            }
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        guard stageSide > 0 else { return .zero }
        return CGPoint(
            x: point.x / stageSide,
            y: point.y / stageSide
        )
    }
}

// MARK: - Layout rail

private struct CollageRail: View {
    let model: CollageModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.layouts, id: \.id) { layout in
                    button(layout)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func button(_ layout: CollageLayout) -> some View {
        let active = layout.id == model.state.layout
        return Button {
            model.setLayout(layout.id)
        } label: {
            VStack(spacing: 5) {
                CollageMiniLayout(layout: layout, active: active)
                Text(Strings.collageLayoutName(layout.id))
                    .font(Font.mng(9.5, weight: .semibold))
                    .foregroundStyle(active ? Aurum.gold : Aurum.muted)
                    .lineLimit(1)
            }
            .padding(6)
            .background(
                active ? Aurum.goldSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        active
                            ? Aurum.gold.opacity(0.45)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(Strings.collageLayoutName(layout.id)) · \(layout.cellCount) ô"
        )
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

private struct CollageMiniLayout: View {
    let layout: CollageLayout
    let active: Bool

    private let side: CGFloat = 54

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.098, green: 0.098, blue: 0.125)
            ForEach(Array(layout.cells.enumerated()), id: \.offset) { _, cell in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        active
                            ? Aurum.gold.opacity(0.75)
                            : Color(red: 0.957, green: 0.949, blue: 0.925)
                                .opacity(0.5)
                    )
                    // The web draws a 1 px cell border inside the box; padding
                    // before the frame keeps the diagram on the same grid.
                    .padding(0.5)
                    .frame(
                        width: max(1, CGFloat(cell.width) * side),
                        height: max(1, CGFloat(cell.height) * side)
                    )
                    .offset(
                        x: CGFloat(cell.x) * side,
                        y: CGFloat(cell.y) * side
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Panel

private struct CollagePanel: View {
    let model: CollageModel

    var body: some View {
        VStack(spacing: 11) {
            sliderRow(
                title: Strings.collageGap,
                value: String(format: "%.1f%%", model.gapPercent),
                binding: Binding(
                    get: { model.gapPercent },
                    set: { model.setGap(percent: $0) }
                ),
                range: 0...Collage.maxGap * 100,
                step: 0.2
            )

            sliderRow(
                title: Strings.collageRadius,
                value: "\(Int(model.radiusPercent.rounded()))%",
                binding: Binding(
                    get: { model.radiusPercent },
                    set: { model.setRadius(percent: $0) }
                ),
                range: 0...Collage.maxRadius * 100,
                step: 1
            )

            backgroundRow

            if model.hasEnough {
                cellBar
            }
        }
        .padding(12)
        .background(
            Color(red: 0.075, green: 0.075, blue: 0.09).opacity(0.68),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Aurum.glassLine, lineWidth: 1)
        }
        .padding(.horizontal, 14)
    }

    private func sliderRow(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Font.mng(11, weight: .semibold))
                    .foregroundStyle(Aurum.muted)
                Spacer(minLength: 8)
                Text(value)
                    .font(Font.mng(11, weight: .bold))
                    .foregroundStyle(Aurum.text)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range, step: step)
                .tint(Aurum.gold)
                .accessibilityLabel(title)
        }
    }

    private var backgroundRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(Strings.collageBackground)
                    .font(Font.mng(11, weight: .semibold))
                    .foregroundStyle(Aurum.muted)
                Spacer(minLength: 8)
                Text(model.state.background)
                    .font(Font.mng(11, weight: .bold))
                    .foregroundStyle(Aurum.text)
                    .monospacedDigit()
            }
            HStack(spacing: 7) {
                ForEach(Self.presets, id: \.self) { hex in
                    swatch(hex: hex)
                }
                ColorPicker(
                    selection: colorBinding,
                    supportsOpacity: false
                ) {
                    Text(Strings.collageBackground)
                }
                .labelsHidden()
                .frame(width: 27, height: 27)
                Spacer(minLength: 0)
            }
        }
    }

    private static let presets = ["#ffffff", "#101014", "#f4f2ec", "#f3c77b"]

    private func swatch(hex: String) -> some View {
        let active = model.state.background.lowercased() == hex
        return Button {
            model.setBackground(hex)
        } label: {
            Circle()
                .fill(Color.mngHex(hex) ?? .white)
                .frame(width: 27, height: 27)
                .overlay {
                    Circle().stroke(
                        active ? Aurum.gold : Color.white.opacity(0.22),
                        lineWidth: active ? 2 : 1
                    )
                }
                .shadow(
                    color: active ? Aurum.gold.opacity(0.28) : .clear,
                    radius: 4
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Strings.collageBackground) \(hex)")
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color.mngHex(model.state.background) ?? .white
            },
            set: { color in
                model.setBackground(hex(from: color))
            }
        )
    }

    private func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard ui.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return Collage.defaultBackground
        }
        return String(
            format: "#%02x%02x%02x",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    private var cellBar: some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Aurum.gold)
                    .frame(width: 6, height: 6)
                    .shadow(color: Aurum.gold.opacity(0.3), radius: 2)
                Text(Strings.collageCellIndex(model.selected))
                    .font(Font.mng(11, weight: .bold))
                    .foregroundStyle(
                        Color(red: 0.973, green: 0.898, blue: 0.741)
                    )
                    .lineLimit(1)
            }

            Slider(
                value: Binding(
                    get: { model.zoomPercent },
                    set: { model.setZoom(percent: $0) }
                ),
                in: 100...(Collage.maxZoom * 100),
                step: 1
            )
            .tint(Aurum.gold)
            .accessibilityLabel(Strings.collageZoom)

            Text("\(Int(model.zoomPercent.rounded()))%")
                .font(Font.mng(10))
                .foregroundStyle(Aurum.muted)
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)

            Button {
                model.resetSelected()
            } label: {
                Text(Strings.collageReset)
                    .font(Font.mng(10.5, weight: .bold))
                    .foregroundStyle(Aurum.text)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(
                        Color.white.opacity(0.05),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().stroke(
                            Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            Aurum.gold.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Aurum.gold.opacity(0.22), lineWidth: 1)
        }
    }
}

// MARK: - Picker

/// Multi-select sheet over the photos already loaded in the library page.
/// The grid shows authenticated thumbnails; nothing is uploaded or copied
/// until the person taps "Thêm".
struct CollagePickerView: View {
    let client: MNGAPIClient
    let items: [Item]
    let existing: Set<Int64>
    let limit: Int
    let onAdd: ([Item]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int64> = []
    /// Tap order, so the cells follow the photos as they were picked instead
    /// of the library order.
    @State private var order: [Int64] = []

    private var available: [Item] {
        items.filter { !$0.isVideo && !existing.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if available.isEmpty {
                    ContentUnavailableView {
                        Label(
                            Strings.collagePickerTitle,
                            systemImage: "photo.on.rectangle"
                        )
                    } description: {
                        Text(Strings.collagePickerEmpty)
                    }
                } else {
                    grid
                }
            }
            .background(Aurum.bg.ignoresSafeArea())
            .navigationTitle(Strings.collagePickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        add()
                    } label: {
                        Text(
                            "\(Strings.collagePickerAdd) (\(selected.count))"
                        )
                        .font(Font.mng(13, weight: .bold))
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(Strings.collageSelection(selected.count, limit: limit))
                    .font(Font.mng(12))
                    .foregroundStyle(Aurum.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .tint(Aurum.gold)
        .preferredColorScheme(.dark)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 104), spacing: 4),
                ],
                spacing: 4
            ) {
                ForEach(available) { item in
                    cell(item)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
    }

    private func cell(_ item: Item) -> some View {
        let isSelected = selected.contains(item.id)
        let isFull = selected.count >= limit && !isSelected
        return Button {
            toggle(item)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ThumbnailView(
                        client: client,
                        path: item.thumbnailPath(size: 360),
                        fallbacks: item.thumbnailFallbackPaths,
                        placeholder: Aurum.bg2
                    )
                }
                .clipped()
                .overlay {
                    if isSelected {
                        Rectangle()
                            .stroke(Aurum.gold, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(Font.mng(10, weight: .bold))
                            .foregroundStyle(
                                Color(red: 0.165, green: 0.11, blue: 0.024)
                            )
                            .frame(width: 21, height: 21)
                            .background(Aurum.gold, in: Circle())
                            .padding(6)
                    }
                }
                .opacity(isFull ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFull)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func toggle(_ item: Item) {
        if selected.contains(item.id) {
            selected.remove(item.id)
            order.removeAll { $0 == item.id }
        } else if selected.count < limit {
            selected.insert(item.id)
            order.append(item.id)
        }
    }

    private func add() {
        guard !selected.isEmpty else { return }
        let byID = Dictionary(
            available.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let picked = order.compactMap { byID[$0] }
        guard !picked.isEmpty else { return }
        onAdd(picked)
        dismiss()
    }
}
