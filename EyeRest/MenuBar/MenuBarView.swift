import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @ObservedObject var prefs = UserPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.circle.fill").foregroundStyle(.blue)
                switch scheduler.state {
                case .idle:
                    Text("Next break in \(formattedNextBreak)").font(.system(size: 13))
                case .breakActive(let r):
                    Text("Break active — \(r)s remaining")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                }
            }

            Divider()

            Button("Take break now") { scheduler.triggerBreakNow() }
                .disabled(scheduler.state != .idle)
            Toggle("Allow skip button", isOn: $prefs.skipEnabled)
            Toggle("Pause schedule", isOn: $prefs.paused)

            Divider()

            HStack {
                Text("Interval:").foregroundStyle(.secondary)
                Picker("", selection: $prefs.breakIntervalMinutes) {
                    Text("10 min").tag(10)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.menu).frame(width: 90)
            }

            HStack {
                Text("Duration:").foregroundStyle(.secondary)
                Picker("", selection: $prefs.breakDurationSeconds) {
                    Text("15 sec").tag(15)
                    Text("30 sec").tag(30)
                    Text("60 sec").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.menu).frame(width: 90)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Emergency exit during break:")
                Text("⌃⌥⌘⇧E (Ctrl+Opt+Cmd+Shift+E)")
                    .font(.system(size: 12, weight: .medium))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Divider()

            Button("Quit EyeRest") { NSApplication.shared.terminate(nil) }
                .foregroundStyle(.red)
        }
        .padding(12)
        .frame(width: 300)
    }

    private var formattedNextBreak: String {
        let mins = Int(scheduler.nextBreakIn / 60)
        let secs = Int(scheduler.nextBreakIn) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
