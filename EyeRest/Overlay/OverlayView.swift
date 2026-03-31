import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var scheduler: BreakScheduler

    var body: some View {
        // No blur here - it's handled at the NSView level
        VStack(spacing: 32) {
            Image(systemName: "eye.fill")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.white.opacity(0.9))

            VStack(spacing: 8) {
                Text("Rest Your Eyes")
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                Text("Look at something 20 feet away")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            CountdownRing(scheduler: scheduler)

            // Skip button — optional, appears only after a 5-second delay
            if UserPreferences.shared.skipEnabled {
                if case .breakActive(let remaining) = scheduler.state, remaining < 25 {
                    Button("Skip") { scheduler.endBreakEarly() }
                        .buttonStyle(SkipButtonStyle())
                        .transition(.opacity.animation(.easeIn(duration: 0.3)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color.clear) // Transparent so blur shows through
    }
}

struct CountdownRing: View {
    @ObservedObject var scheduler: BreakScheduler
    private var total: Int { UserPreferences.shared.countdownDuration }

    private var remaining: Int {
        if case .breakActive(let r) = scheduler.state { return r }
        return total
    }
    private var progress: Double { Double(remaining) / Double(total) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
                .frame(width: 100, height: 100)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
            Text("\(remaining)")
                .font(.system(size: 36, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct SkipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(
                Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .background(Capsule().fill(Color.white.opacity(
                        configuration.isPressed ? 0.1 : 0.05)))
            )
    }
}
