import SwiftUI

/// The removal in progress, shown as an overlay on top of whichever page started it.
@MainActor @Observable
final class Activity {
    static let shared = Activity()

    var isWorking = false
    var title = ""
    var total = 0
    var done = 0
    var currentName = ""
    var bytesDone: Int64 = 0
    var finished: CleanReport?
    private var startedAt = Date.now

    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    func begin(_ title: String, total: Int) {
        self.title = title
        self.total = total
        done = 0
        bytesDone = 0
        currentName = ""
        finished = nil
        startedAt = .now
        withAnimation(.easeOut(duration: 0.25)) { isWorking = true }
    }

    func step(_ name: String, bytes: Int64 = 0) {
        done = min(done + 1, total)
        bytesDone += bytes
        currentName = name
    }

    /// Keeps the overlay up long enough to read, then shows the result for a moment.
    func finish(_ report: CleanReport) async {
        done = total
        let elapsed = Date.now.timeIntervalSince(startedAt)
        if elapsed < 0.9 { try? await Task.sleep(for: .seconds(0.9 - elapsed)) }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isWorking = false
            finished = report.removed > 0 ? report : nil
        }
        guard finished != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeInOut(duration: 0.35)) { finished = nil }
        }
    }
}

struct ActivityOverlay: View {
    var activity = Activity.shared

    var body: some View {
        ZStack {
            if activity.isWorking || activity.finished != nil {
                Rectangle().fill(.ultraThinMaterial)
                Color(hex: 0x060914).opacity(0.6)
            }
            if activity.isWorking {
                progressCard.transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if let report = activity.finished {
                Celebration(
                    title: report.freed == 0 ? "Done"
                        : report.movedToTrash ? "Moved \(report.freed.byteString) to Trash" : "Freed \(report.freed.byteString)",
                    subtitle: report.failed.isEmpty
                        ? "\(report.removed) item\(report.removed == 1 ? "" : "s") removed."
                        : "\(report.removed) removed · \(report.failed.count) couldn't be removed"
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onTapGesture { withAnimation { activity.finished = nil } }
            }
        }
        .allowsHitTesting(activity.isWorking || activity.finished != nil)
    }

    private var progressCard: some View {
        VStack(spacing: 22) {
            ZStack {
                if activity.total > 1 {
                    ProgressRing(progress: activity.fraction, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text("\(Int(activity.fraction * 100))%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                } else {
                    SpinningRing(lineWidth: 8).padding(18)
                }
            }
            .frame(width: 140, height: 140)
            .background { BreathingHalo().frame(width: 260, height: 260) }

            VStack(spacing: 6) {
                Text(activity.title).font(.system(size: 17, weight: .semibold))
                if activity.bytesDone > 0 {
                    Text("\(activity.bytesDone.byteString) \(activity.title.hasPrefix("Moving") ? "moved" : "freed")")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.orange)
                        .monospacedDigit()
                }
            }

            if activity.total > 1 {
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: Theme.ringColors, startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * activity.fraction)
                                    .animation(.easeOut(duration: 0.25), value: activity.done)
                            }
                    }
                    .frame(height: 4)
                    HStack {
                        Text("\(activity.done.formatted()) of \(activity.total.formatted())")
                            .monospacedDigit()
                        Spacer()
                        Text("\(max(activity.total - activity.done, 0).formatted()) left").monospacedDigit()
                    }
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
            }

            Text(activity.currentName.isEmpty ? " " : activity.currentName)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x10173A).opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
    }
}
