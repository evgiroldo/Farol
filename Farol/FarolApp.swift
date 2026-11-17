import SwiftUI

/// Farol 0.1 preview (ADR 0044): one menu bar app that watches the Mac and explains slowdowns.
@main
struct FarolApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            CardView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel(Text(model.menuBarLabel))
        }
        .menuBarExtraStyle(.window)
    }
}
