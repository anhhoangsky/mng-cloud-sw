import SwiftUI

/// The progress of a "save into the library" run.
///
/// The card floats above the grid so the upload can keep running while the
/// person browses the library.
struct BackupProgressCard: View {
    let model: CloudBackupModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.accent)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isRunning ? Strings.backupTitle : Strings.backupDone)
                        .font(Font.mng(13, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(detail)
                        .font(Font.mng(11))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                if !model.isRunning {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(Font.mng(11, weight: .bold))
                            .foregroundStyle(Palette.text3)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.close)
                }
            }

            if model.total > 0 {
                ProgressView(value: Double(model.completed), total: Double(model.total))
                    .tint(Palette.accent)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var detail: String {
        if model.isRunning {
            if let name = model.currentName, !name.isEmpty {
                return "\(model.completed)/\(model.total) · \(name)"
            }
            return Strings.backupProgress(model.completed, model.total)
        }
        return model.summary
    }
}
