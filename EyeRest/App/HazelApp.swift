import SwiftUI

@main
struct HazelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var scheduler = BreakScheduler.shared

    var body: some Scene {
        MenuBarExtra("Hazel", systemImage: "eye") {
            MenuBarView()
                .environmentObject(scheduler)
        }
        .menuBarExtraStyle(.window)
    }
}
