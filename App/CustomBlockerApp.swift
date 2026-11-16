import SwiftUI

@main
struct CustomBlockerApp: App {
    init() {
        FilterStore.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
