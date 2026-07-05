import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme

    private var theme: Theme {
        systemScheme == .dark ? .slate : .light
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            Text(verbatim: "Weave")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text2)
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }
}
