import SwiftUI

/// The sidebar card that offers an update, then shows it downloading, being verified and installing.
struct UpdateCard: View {
    var release: Updates.Release
    private var updates: Updates { .shared }

    private var working: Bool { updates.isUpdating && updates.phase != .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                UpdateBadge(phase: updates.phase)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.interpolate)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                closeButton
            }
            footer
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(working ? 0.16 : 0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(working ? 0.15 : 0.3))
        }
        .overlay {
            if working { OrbitingBorder(cornerRadius: 12).transition(.opacity) }
        }
        .shadow(color: Theme.accent.opacity(working ? 0.35 : 0), radius: 18, y: 4)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: updates.phase)
    }

    private var title: String {
        switch updates.phase {
        case .idle: String(localized: "Update available")
        case .preparing: String(localized: "Getting Novra \(release.version)")
        case .downloading: String(localized: "Downloading Novra \(release.version)")
        case .verifying: String(localized: "Verifying")
        case .ready: String(localized: "Novra \(release.version) is ready")
        case .installing: String(localized: "Installing")
        case .failed: String(localized: "Update didn't finish")
        }
    }

    private var detail: String {
        switch updates.phase {
        case .idle: "Novra \(release.version)"
        case .preparing: String(localized: "Connecting…")
        case .downloading(let received, let total):
            received > 0 && total > 0 ? String(localized: "\(received.byteString) of \(total.byteString)") : String(localized: "Starting…")
        case .verifying: String(localized: "Checking it's signed by Naqara Dev")
        case .ready: String(localized: "Restart to finish. It takes a few seconds.")
        case .installing: String(localized: "Novra reopens by itself")
        case .failed(let reason): reason
        }
    }

    @ViewBuilder private var closeButton: some View {
        switch updates.phase {
        case .idle:
            close(help: "Skip this version") { updates.skip() }
        case .preparing, .downloading:
            close(help: "Stop") { updates.cancelUpdate?() }
        case .failed:
            close(help: "Dismiss") { withAnimation(.snappy) { updates.phase = .idle } }
        default:
            EmptyView()
        }
    }

    private func close(help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var footer: some View {
        switch updates.phase {
        case .idle:
            links(primary: "Update") { updates.download() }
        case .preparing, .verifying, .installing:
            UpdateBar(progress: nil)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        case .downloading(let received, let total):
            HStack(spacing: 8) {
                UpdateBar(progress: total > 0 ? Double(received) / Double(total) : nil)
                if total > 0 {
                    Text(verbatim: "\(Int(Double(received) / Double(total) * 100))%")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.lavender)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        case .ready:
            Button { updates.restartToUpdate?() } label: {
                Label("Restart to Update", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RestartButtonStyle())
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        case .failed:
            links(primary: "Try again") { updates.download() }
        }
    }

    private func links(primary: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(primary, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Button("What's new") { NSWorkspace.shared.open(release.page) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
        }
    }
}

/// Icon in a circle. While working, a ring fills with the download or spins when there's no number yet.
private struct UpdateBadge: View {
    var phase: Updates.Phase

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            switch phase {
            case .downloading(let received, let total) where total > 0:
                Circle()
                    .trim(from: 0, to: max(0.03, Double(received) / Double(total)))
                    .stroke(Theme.ring, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.accent.opacity(0.7), radius: 4)
                    .animation(.easeOut(duration: 0.35), value: received)
            case .preparing, .downloading, .verifying, .installing:
                SpinningArc()
            default:
                EmptyView()
            }
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: phase == .ready)
        }
        .frame(width: 30, height: 30)
    }

    private var icon: String {
        switch phase {
        case .idle, .preparing, .downloading: "arrow.down"
        case .verifying: "checkmark.shield"
        case .ready: "checkmark"
        case .installing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark"
        }
    }

    private var tint: Color {
        switch phase {
        case .ready: Theme.green
        case .failed: Theme.orange
        default: Theme.accent
        }
    }
}

private struct SpinningArc: View {
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(Theme.ring, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .rotating(period: 0.9)
            .shadow(color: Theme.accent.opacity(0.7), radius: 4)
    }
}

/// Thin glowing bar. With a value it fills and a sheen runs along it; without one, a light sweeps across.
private struct UpdateBar: View {
    var progress: Double?

    var body: some View {
        GeometryReader { geo in
            LoopView { date in
                bar(width: geo.size.width, sweep: Loop.ease(Loop.phase(date, period: 1.3)))
            }
        }
        .frame(height: 5)
    }

    /// `sweep` runs 0 → 1: where the moving light is along the bar.
    private func bar(width w: CGFloat, sweep: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.08))
            if let progress {
                Capsule()
                    .fill(LinearGradient(colors: Theme.ringColors, startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .leading) {
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 36)
                            .offset(x: -36 + (w + 36) * sweep)
                    }
                    .clipShape(Capsule())
                    .frame(width: max(6, w * min(progress, 1)))
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
                    .animation(.easeOut(duration: 0.35), value: progress)
            } else {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0), Theme.accent, Theme.lavender, Theme.accent.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.4)
                    .offset(x: -w * 0.4 + w * 1.4 * sweep)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
            }
        }
        .clipShape(Capsule())
    }
}

/// A short streak of light that circles the card's edge while an update is running.
private struct OrbitingBorder: View {
    var cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height) * 1.6
            AngularGradient(colors: [.clear, .clear, Theme.accent, Theme.lavender, .clear], center: .center)
                .frame(width: size, height: size)
                .rotating(period: 2.6)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(lineWidth: 1.4))
        .allowsHitTesting(false)
    }
}

private struct RestartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Capsule().fill(LinearGradient(colors: [Theme.accentDeep, Theme.accent], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: Theme.accent.opacity(0.5), radius: 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
