import MNGKit
import SwiftUI

/// Person rename sheet. The lookup card is patched optimistically; the save
/// button stays disabled while the request runs, and a failure restores both
/// name and label from `AlbumsModel`.
struct PersonRenameSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    private var albums: AlbumsModel { model.albums }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let person = albums.personToEdit {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AlbumCatalog.personTitle(person))
                            .font(Font.mng(17, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text(Strings.personRenameSub(
                            itemCount: person.itemCount,
                            faceCount: person.faceCount
                        ))
                        .font(Font.mng(13))
                        .foregroundStyle(Palette.text3)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(Strings.personNameLabel)
                            .font(Font.mng(12, weight: .semibold))
                            .foregroundStyle(Palette.text3)
                        TextField(Strings.personNamePlaceholder, text: nameBinding)
                            .font(Font.mng(17))
                            .foregroundStyle(Palette.text)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($fieldFocused)
                            .onSubmit(save)
                            .padding(.horizontal, 13)
                            .frame(height: 46)
                            .background(
                                Palette.fill,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .accessibilityLabel(Strings.personNameLabel)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        albums.cancelPersonEdit()
                        dismiss()
                    } label: {
                        Text(Strings.cancel)
                            .font(Font.mng(15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Palette.fill2,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: save) {
                        Text(Strings.personNameSave)
                            .font(Font.mng(15, weight: .semibold))
                            .foregroundStyle(Palette.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Palette.accent,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .opacity(albums.personSaving ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(albums.personSaving)
                }
            }
            .padding(16)
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.personRenameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.close) {
                        albums.cancelPersonEdit()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            fieldFocused = true
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { albums.personName },
            set: { albums.personName = String($0.prefix(80)) }
        )
    }

    private func save() {
        albums.savePerson()
        dismiss()
    }
}
