import Foundation
import AppKit
import Combine

enum AppState: Equatable {
    case idle
    case breakActive(secondsRemaining: Int)
}

final class BreakScheduler: ObservableObject {
    static let shared = BreakScheduler()

    @Published private(set) var state: AppState = .idle
    @Published private(set) var nextBreakIn: TimeInterval = 0

    var breakInterval: TimeInterval { UserPreferences.shared.breakInterval }
    var countdownDuration: Int { UserPreferences.shared.countdownDuration }

    private var breakDispatchTimer: DispatchSourceTimer?
    private var countdownTimer: Timer?
    private var nextBreakDate: Date?
    private var tickTimer: Timer?

    private init() {}

    // MARK: - Public API

    func start() {
        guard !UserPreferences.shared.paused else { return }
        scheduleNextBreak()
    }

    func stop() {
        cancelAll()
    }

    func triggerBreakNow() {
        beginBreak()
    }

    func resetSchedule() {
        if state == .idle && !UserPreferences.shared.paused {
            scheduleNextBreak()
        }
    }

    func endBreakEarly() {
        endBreak()
    }

    // MARK: - Private

    private func scheduleNextBreak() {
        cancelAll()
        nextBreakDate = Date().addingTimeInterval(breakInterval)

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + breakInterval, repeating: .never)
        timer.setEventHandler { [weak self] in self?.beginBreak() }
        timer.resume()
        breakDispatchTimer = timer

        scheduleTick()
    }

    private func beginBreak() {
        cancelDispatchTimer()
        cancelTickTimer()
        var remaining = countdownDuration
        state = .breakActive(secondsRemaining: remaining)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 {
                self.endBreak()
            } else {
                self.state = .breakActive(secondsRemaining: remaining)
            }
        }
    }

    private func endBreak() {
        cancelCountdownTimer()
        state = .idle
        if !UserPreferences.shared.paused {
            scheduleNextBreak()
        }
    }

    private func cancelDispatchTimer() {
        breakDispatchTimer?.cancel()
        breakDispatchTimer = nil
    }

    private func cancelCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func cancelTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func cancelAll() {
        cancelDispatchTimer()
        cancelCountdownTimer()
        cancelTickTimer()
    }

    // MARK: - Sleep / Wake

    func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemWillSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemDidWake),
                       name: NSWorkspace.didWakeNotification, object: nil)

        // Screensaver notifications
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screensaverStarted),
            name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screensaverStopped),
            name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)
    }

    @objc private func systemWillSleep() {
        cancelAll()
        state = .idle
    }

    @objc private func systemDidWake() {
        if !UserPreferences.shared.paused {
            scheduleNextBreak()
        }
    }

    @objc private func screensaverStarted() {
        if case .breakActive = state {
            endBreakEarly()
        }
    }

    @objc private func screensaverStopped() {
        if !UserPreferences.shared.paused {
            scheduleNextBreak()
        }
    }

    // MARK: - Tick (for menu bar "next break in X:XX")

    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let date = self.nextBreakDate else { return }
            self.nextBreakIn = max(0, date.timeIntervalSinceNow)
        }
    }
}
