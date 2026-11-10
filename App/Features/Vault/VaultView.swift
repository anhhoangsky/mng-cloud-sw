import MNGCore
import MNGKit
import SwiftUI

/// Native vault tab. The screen follows the PWA: a vault list, an unlock
/// screen per vault and the encrypted file browser.
struct VaultView: View {
    let model: ShellModel

    private var vault: VaultModel { model.vault }

    var body: some View {
        switch vault.screen {
        case .list:
            VaultListView(model: model)
        case .unlock(let target):
            VaultUnlockView(model: model, vault: target)
        case .browse(let target):
            VaultBrowseView(model: model, vault: target)
        }
    }
}
