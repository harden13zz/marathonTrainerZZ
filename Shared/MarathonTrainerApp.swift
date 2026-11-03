import SwiftUI
import SwiftData

@main
struct MarathonTrainerApp: App {

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if !os(watchOS)
        .modelContainer(StoreFactory.shared)
        #endif
    }
}

struct RootView: View {
    var body: some View {
        #if os(watchOS)
        WatchContentView()
        #else
        ContentView()
        #endif
    }
}
