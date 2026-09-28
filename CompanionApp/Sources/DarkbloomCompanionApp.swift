import SwiftUI

@main
struct DarkbloomCompanionApp: App {
    @State private var store = CompanionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
