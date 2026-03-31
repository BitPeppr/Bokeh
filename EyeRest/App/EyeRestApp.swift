import SwiftUI

@main
struct EyeRestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var scheduler = BreakScheduler.shared

    var body: some Scene {
        MenuBarExtra("EyeRest", systemImage: "eye") {
            MenuBarView()
                .environmentObject(scheduler)
        }
        .menuBarExtraStyle(.window)
    }
}
