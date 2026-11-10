import SwiftUI

/// Phase-3 placeholder for the destinations that arrive in later phases.
/// The shell, copy and layout are already the final ones.
struct PlaceholderPage: View {
    let tab: ShellTab

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.l) {
                Image(systemName: tab.icon)
                    .font(.mng(40, weight: .regular))
                    .foregroundStyle(Palette.text4)

                Text(tab.label)
                    .font(.mng(28, weight: .semibold))
                    .foregroundStyle(Palette.text)

                Text(Strings.comingSoon)
                    .font(.mng(15))
                    .foregroundStyle(Palette.text3)

                Text(Strings.comingSoonHint)
                    .font(.mng(13))
                    .foregroundStyle(Palette.text4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.top, 96)
            .padding(.bottom, 120)
        }
        .background(Palette.bg.ignoresSafeArea())
    }
}
