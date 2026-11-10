import MNGCore
import MNGKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Browser for one unlocked vault: breadcrumb, search and the encrypted file
/// grid. Folders and files come from the decrypted manifest only.
struct VaultBrowseView: View {
    let model: ShellModel
    let vault: NativeVault

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isCreatingFolder = false
    @State private var pendingDelete: PendingDelete?
    @State private var isPickingFile = false
    @State private var isPickingPhoto = false
    @State private var previewTarget: PreviewTarget?

    /// `VaultFile` is not `Identifiable`, so the sheet uses a tiny wrapper.
    private struct PreviewTarget: Identifiable {
        let file: VaultFile
        var id: String { file.id }
    }

    private enum PendingDelete: Identifiable {
        case file(VaultFile)
        case folder(VaultFolder)

        var id: String {
            switch self {
            case .file(let file): return "file-\(file.id)"
            case .folder(let entry): return "folder-\(entry.id)"
            }
        }

        var name: String {
            switch self {
            case .file(let file): return file.name
            case .folder(let entry): return entry.name
            }
        }
    }

    private var state: VaultModel { model.vault }
    private var isCompact: Bool { sizeClass == .compact }

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                toolbar

                if let progress = state.upload {
                    uploadProgress(progress)
                }

                if !state.notice.isEmpty {
                    bar(
                        icon: "checkmark.circle.fill",
                        tint: Palette.green,
                        message: state.notice
                    )
                }

                if !state.operationError.isEmpty {
                    bar(
                        icon: "exclamationmark.triangle.fill",
                        tint: Palette.danger,
                        message: state.operationError
                    )
                }

                searchField

                if state.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    breadcrumbs
                }

                content

                bar(
                    icon: "shield.lefthalf.filled",
                    tint: Palette.text3,
                    message: Strings.vaultNoteChunks
                )
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.top, isCompact ? 6 : 26)
            .padding(.bottom, isCompact ? 140 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg.ignoresSafeArea())
        .task {
            // The PWA starts the move as soon as a vault is unlocked.
            let ids = model.pendingVaultMove
            guard !ids.isEmpty else { return }
            model.pendingVaultMove = []
            await state.moveItems(ids)
        }
        .sheet(isPresented: $isCreatingFolder) {
            VaultFolderSheet(model: model)
        }
        .sheet(isPresented: $isPickingFile) {
            VaultDocumentPicker { url in
                isPickingFile = false
                uploadFile(at: url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPickingPhoto) {
            VaultPhotoPicker { picked in
                isPickingPhoto = false
                upload(picked)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $previewTarget) { target in
            VaultPreviewSheet(model: model)
                .onAppear {
                    Task { await state.openPreview(target.file) }
                }
        }
        .alert(
            Strings.vaultDeleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { item in
            Button(Strings.cancel, role: .cancel) { pendingDelete = nil }
            Button(Strings.delete, role: .destructive) {
                pendingDelete = nil
                Task {
                    switch item {
                    case .file(let file):
                        await state.deleteFile(file)
                    case .folder(let entry):
                        await state.deleteFolder(entry)
                    }
                }
            }
        } message: { item in
            Text(item.name)
        }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Palette.accentSoft,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.mng(17, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(
                        Strings.vaultSubtitle(
                            files: state.manifest?.files.count ?? 0,
                            bytes: state.totalBytes
                        )
                    )
                    .font(.mng(12))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    isCreatingFolder = true
                } label: {
                    Label(Strings.vaultFolder, systemImage: "folder.badge.plus")
                        .font(.mng(13, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Palette.accentSoft,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.isWorking)

                Menu {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label(Strings.vaultUploadFiles, systemImage: "folder")
                    }
                    Button {
                        isPickingPhoto = true
                    } label: {
                        Label(Strings.vaultUploadPhotos, systemImage: "photo")
                    }
                } label: {
                    Label(Strings.vaultUpload, systemImage: "square.and.arrow.up")
                        .font(.mng(13, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Palette.accentSoft,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .disabled(state.isWorking)

                Button {
                    state.lock()
                } label: {
                    Label(Strings.vaultLock, systemImage: "lock")
                        .font(.mng(13, weight: .semibold))
                        .foregroundStyle(Palette.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Palette.fill,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
    }

    private func uploadProgress(_ progress: VaultModel.UploadProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.fill)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(progress.done) / CGFloat(max(1, progress.total))
                        )
                }
            }
            .frame(height: 4)

            Text(Strings.vaultUploadingProgress)
                .font(.mng(12))
                .foregroundStyle(Palette.text3)
        }
        .padding(12)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.mng(13, weight: .semibold))
                .foregroundStyle(Palette.text3)

            TextField(
                Strings.vaultSearchPlaceholder,
                text: Binding(
                    get: { state.search },
                    set: { state.updateSearch($0) }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !state.search.isEmpty {
                Button {
                    state.updateSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.mng(13))
                        .foregroundStyle(Palette.text4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                crumb(
                    title: displayName,
                    isCurrent: state.folder == nil
                ) {
                    state.navigate(to: nil)
                }

                ForEach(state.folderTrail.indices, id: \.self) { index in
                    let entry = state.folderTrail[index]
                    Image(systemName: "chevron.right")
                        .font(.mng(10, weight: .semibold))
                        .foregroundStyle(Palette.text4)
                    crumb(
                        title: entry.name,
                        isCurrent: entry.id == state.folder
                    ) {
                        state.navigate(to: entry.id)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func crumb(title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mng(13, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? Palette.text : Palette.accent)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let folders = state.visibleFolders
        let files = state.visibleFiles

        if folders.isEmpty && files.isEmpty {
            if state.search.isEmpty {
                emptyState(
                    icon: "folder",
                    title: Strings.vaultEmptyFolderTitle,
                    body: Strings.vaultEmptyFolderBody
                )
            } else {
                emptyState(
                    icon: "magnifyingglass",
                    title: Strings.vaultSearchEmptyTitle,
                    body: Strings.vaultSearchEmptyBody
                )
            }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(folders.indices, id: \.self) { index in
                    folderTile(folders[index])
                }

                ForEach(files.indices, id: \.self) { index in
                    fileTile(files[index])
                }
            }
        }
    }

    private func folderTile(_ entry: VaultFolder) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.mng(15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(
                    Palette.accentSoft,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Text(
                    state.search.isEmpty
                        ? Strings.vaultFolderCount(state.fileCount(in: entry.id))
                        : Strings.vaultFolderPath(state.folderPath(entry.parent))
                )
                .font(.mng(11))
                .foregroundStyle(Palette.text3)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.navigate(to: entry.id)
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .folder(entry)
            } label: {
                Label(Strings.delete, systemImage: "trash")
            }
        }
    }

    private func fileTile(_ file: VaultFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VaultThumbnail(file: file, model: model)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Text(
                    state.search.isEmpty
                        ? Strings.vaultFileMeta(label(for: file), file.size)
                        : Strings.vaultFileMetaPath(
                            state.folderPath(file.folder),
                            file.size
                        )
                )
                .font(.mng(11))
                .foregroundStyle(Palette.text3)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewTarget = PreviewTarget(file: file)
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .file(file)
            } label: {
                Label(Strings.delete, systemImage: "trash")
            }
        }
    }

    private func label(for file: VaultFile) -> String {
        switch VaultModel.kind(for: file) {
        case "image": return Strings.vaultImageLabel
        case "video": return Strings.vaultVideoLabel
        default: return Strings.vaultFileLabel
        }
    }

    private var displayName: String {
        let name = state.manifest?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? vault.name : name
    }

    // MARK: - Upload helpers

    private func uploadFile(at url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let size = Int64(values?.fileSize ?? 0)
        let name = values?.name ?? url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        Task {
            await state.upload(
                VaultUploadSource.file(
                    name: name,
                    mime: mime,
                    size: size,
                    url: url
                )
            )
        }
    }

    private func uploadFile(name: String, mime: String, at url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        Task {
            await state.upload(
                VaultUploadSource.file(
                    name: name,
                    mime: mime,
                    size: size,
                    url: url
                )
            )
        }
    }

    private func upload(_ picked: VaultPhotoPicker.Picked) {
        if let url = picked.url {
            uploadFile(name: picked.name, mime: picked.mime, at: url)
            return
        }
        guard let data = picked.data else { return }
        Task {
            await state.upload(
                VaultUploadSource.memory(
                    name: picked.name,
                    mime: picked.mime,
                    data: data
                )
            )
        }
    }

    // MARK: - Building blocks

    private func bar(icon: String, tint: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.mng(13, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.mng(12, weight: .medium))
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.bgElevated,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
    }

    private func emptyState(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.mng(26, weight: .regular))
                .foregroundStyle(Palette.text4)
            Text(title)
                .font(.mng(14, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text(body)
                .font(.mng(12))
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 40)
    }
}

/// Decrypted thumbnail of one vault file. Manifests created by the web client
/// do not carry one, so the tile falls back to a file icon.
private struct VaultThumbnail: View {
    let file: VaultFile
    let model: ShellModel

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: icon)
                    .font(.mng(15, weight: .semibold))
                    .foregroundStyle(Palette.text2)
            }
        }
        .frame(width: 34, height: 34)
        .background(
            Palette.fill,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: file.id) {
            guard image == nil else { return }
            guard let data = await model.vault.thumbnail(for: file) else { return }
            image = UIImage(data: data)
        }
    }

    private var icon: String {
        switch VaultModel.kind(for: file) {
        case "image": return "photo"
        case "video": return "film"
        default: return "doc"
        }
    }
}
