import SwiftUI

final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    @AppStorage("breakIntervalMinutes") var breakIntervalMinutes: Int = 20 {
        didSet { BreakScheduler.shared.resetSchedule() }
    }
    @AppStorage("breakDurationSeconds") var breakDurationSeconds: Int = 30 {
        didSet { BreakScheduler.shared.resetSchedule() }
    }
    @AppStorage("countdownDuration") var countdownDuration: Int = 30 // Deprecated, use breakDurationSeconds
    @AppStorage("skipEnabled") var skipEnabled: Bool = false
    @AppStorage("paused") var paused: Bool = false {
        didSet {
            if paused { BreakScheduler.shared.stop() }
            else { BreakScheduler.shared.start() }
        }
    }

    var breakInterval: TimeInterval { TimeInterval(breakIntervalMinutes * 60) }
    var breakDuration: TimeInterval { TimeInterval(breakDurationSeconds) }

    private init() {}
}
