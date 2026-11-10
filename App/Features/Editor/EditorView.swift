import MNGEdit
import MNGKit
import SwiftUI
import UIKit

/// Image editor, ported from the web editor (`web/assets/editor.js`).
///
/// The stage shows the oriented preview with the crop rectangle on top; the
/// panel has the three web tabs (Cắt, Chỉnh màu, Bộ lọc) and the footer keeps
/// the two save modes.
struct EditorView: View {
    let model: ShellModel
    let item: Item

    @Environment(\.dismiss) private var dismiss

    private var editor: EditorModel { model.editor }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stage

                panel

                footer
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(Strings.editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.editorCancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await editor.open(item: item)
        }
        .onDisappear {
            editor.close()
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            Color.black.opacity(0.92)

            switch editor.state {
            case .idle, .loading:
                ProgressView()
                    .tint(.white)
                VStack {
                    Spacer()
                    Text(Strings.editorLoading)
                        .font(.mng(12))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
            case .failed(let message):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.mng(24))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(message)
                        .font(.mng(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            case .ready, .saving:
                if let preview = editor.preview {
                    GeometryReader { geometry in
                        let fitted = fittedSize(
                            image: preview,
                            in: geometry.size
                        )
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: fitted.width, height: fitted.height)
                                .position(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )

                            if editor.tab == .crop {
                                CropOverlay(
                                    crop: editor.crop,
                                    onChange: { editor.setCrop($0) }
                                )
                                .frame(
                                    width: fitted.width,
                                    height: fitted.height
                                )
                                .position(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 220)
        .frame(maxHeight: .infinity)
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

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 12) {
            Picker(
                Strings.editorTitle,
                selection: Binding(
                    get: { editor.tab },
                    set: { editor.selectTab($0) }
                )
            ) {
                Text(Strings.editorCropTab).tag(EditorModel.Tab.crop)
                Text(Strings.editorAdjustTab).tag(EditorModel.Tab.adjust)
                Text(Strings.editorFilterTab).tag(EditorModel.Tab.filter)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            Group {
                switch editor.tab {
                case .crop:
                    cropPanel
                case .adjust:
                    adjustPanel
                case .filter:
                    filterPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .background(Palette.bgElevated)
    }

    private var cropPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.editorGeometry)
                .font(.mng(11, weight: .semibold))
                .tracking(0.06)
                .foregroundStyle(Palette.text4)

            HStack(spacing: 8) {
                chip(Strings.editorRotateLeft, icon: "rotate.left") {
                    editor.rotate(-1)
                }
                chip(Strings.editorRotateRight, icon: "rotate.right") {
                    editor.rotate(1)
                }
                chip(Strings.editorFlipH, icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    editor.flip(horizontal: true)
                }
                chip(Strings.editorFlipV, icon: "arrow.up.and.down") {
                    editor.flip(horizontal: false)
                }
            }

            Text(Strings.editorAspect)
                .font(.mng(11, weight: .semibold))
                .tracking(0.06)
                .foregroundStyle(Palette.text4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorModel.Aspect.allCases) { aspect in
                        Button {
                            editor.applyAspect(aspect)
                        } label: {
                            Text(aspect.title)
                                .font(.mng(13, weight: .semibold))
                                .foregroundStyle(
                                    editor.aspect == aspect
                                        ? Palette.accentInk
                                        : Palette.text2
                                )
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(
                                    editor.aspect == aspect
                                        ? Palette.accent
                                        : Palette.fill,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            Text(Strings.editorCropHint)
                .font(.mng(11))
                .foregroundStyle(Palette.text4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button(Strings.editorCropReset) {
                    editor.resetCrop()
                }
                .font(.mng(14, weight: .semibold))
                .foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Palette.fill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .buttonStyle(.plain)

                Button(Strings.editorCropApply) {
                    editor.setCrop(editor.crop)
                }
                .font(.mng(14, weight: .semibold))
                .foregroundStyle(Palette.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Palette.accent,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    private var adjustPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(EditorModel.Adjustment.allCases) { key in
                HStack(spacing: 10) {
                    Text(key.title)
                        .font(.mng(12))
                        .foregroundStyle(Palette.text2)
                        .frame(width: 92, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { Double(key.value(in: editor.adjustments)) },
                            set: { editor.setAdjustment(key, value: Float($0)) }
                        ),
                        in: -100...100,
                        step: 1
                    )

                    Text("\(Int(key.value(in: editor.adjustments)))")
                        .font(.mng(12, weight: .medium))
                        .foregroundStyle(Palette.text3)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 16)
            }

            Button(Strings.editorAdjustReset) {
                editor.resetAdjustments()
            }
            .font(.mng(13, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .buttonStyle(.plain)
        }
    }

    private var filterPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorFilter.allCases, id: \.self) { filter in
                    Button {
                        editor.setFilter(filter)
                    } label: {
                        Text(Strings.editorFilterTitle(filter))
                            .font(.mng(13, weight: .semibold))
                            .foregroundStyle(
                                editor.filter == filter
                                    ? Palette.accentInk
                                    : Palette.text2
                            )
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                editor.filter == filter
                                    ? Palette.accent
                                    : Palette.fill,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Picker(
                Strings.editorSaveMode,
                selection: Binding(
                    get: { editor.mode },
                    set: { editor.selectMode($0) }
                )
            ) {
                Text(Strings.editorModeOverwrite).tag(EditorModel.SaveMode.overwrite)
                Text(Strings.editorModeCopy).tag(EditorModel.SaveMode.copy)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button(Strings.editorCancel) { dismiss() }
                    .font(.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        Palette.fill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .buttonStyle(.plain)

                Button {
                    Task { await editor.save() }
                } label: {
                    HStack(spacing: 8) {
                        if editor.state == .saving {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.mng(13, weight: .semibold))
                        }
                        Text(Strings.editorSave)
                            .font(.mng(15, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        Palette.accent,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(editor.state != .ready && editor.state != .saving)
                .opacity(editor.state == .ready || editor.state == .saving ? 1 : 0.6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(Palette.bgElevated2)
    }

    private func chip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.mng(14, weight: .semibold))
                Text(title)
                    .font(.mng(10, weight: .semibold))
            }
            .foregroundStyle(Palette.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Palette.fill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

/// Draggable crop rectangle drawn over the preview.
private struct CropOverlay: View {
    let crop: EditorCrop
    let onChange: (EditorCrop) -> Void

    @State private var origin: EditorCrop?

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(
                x: CGFloat(crop.x) * geometry.size.width,
                y: CGFloat(crop.y) * geometry.size.height,
                width: CGFloat(crop.width) * geometry.size.width,
                height: CGFloat(crop.height) * geometry.size.height
            )

            Rectangle()
                .stroke(Palette.accent, lineWidth: 1.5)
                .background(Palette.bg.opacity(0.45))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let start = origin ?? crop
                            if origin == nil {
                                origin = start
                            }
                            let dx = Float(
                                value.translation.width / max(geometry.size.width, 1)
                            )
                            let dy = Float(
                                value.translation.height / max(geometry.size.height, 1)
                            )
                            var next = start
                            next.x = min(max(start.x + dx, 0), 1 - start.width)
                            next.y = min(max(start.y + dy, 0), 1 - start.height)
                            onChange(next)
                        }
                        .onEnded { _ in
                            origin = nil
                        }
                )
        }
    }
}
