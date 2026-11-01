import SwiftUI

// MARK: - Ambient background

/// Slowly drifting colour glows behind every page. Plain gradients moved by implicit animation,
/// so the GPU composites them instead of re-blurring every frame.
struct AmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.background
                glow(Theme.accentDeep, opacity: 0.55, size: w * 1.1)
                    .position(x: w * (drift ? 0.88 : 0.72), y: h * (drift ? 0.05 : 0.2))
                glow(Theme.purple, opacity: 0.3, size: w * 0.8)
                    .position(x: w * (drift ? 0.1 : 0.22), y: h * (drift ? 0.92 : 0.8))
                glow(Theme.accent, opacity: 0.18, size: w * 0.7)
                    .position(x: w * (drift ? 0.55 : 0.38), y: h * (drift ? 0.42 : 0.6))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func glow(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

// MARK: - Reveal on appear

private struct Reveal: ViewModifier {
    var delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .blur(radius: shown ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Fades, lifts and un-blurs the view in when it first appears.
    func reveal(delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }

    /// Stagger delay for the n-th item of a list, capped so long lists don't drag.
    func reveal(index: Int, step: Double = 0.035) -> some View { reveal(delay: Double(min(index, 14)) * step) }
}

// MARK: - Loops

/// Loops driven by the clock instead of a repeating `withAnimation` in `onAppear`. A repeating animation
/// started while a transition runs can capture it: the view wobbles, or when it's removed the transition
/// never ends and a faded copy stays on screen.
enum Loop {
    /// Goes 0 → 1 once per period, then starts over.
    static func phase(_ date: Date, period: Double) -> Double {
        let t = date.timeIntervalSinceReferenceDate / period
        return t - t.rounded(.down)
    }

    /// Eases 0 → 1 → 0 once per period.
    static func breath(_ date: Date, period: Double) -> Double {
        (1 - cos(phase(date, period: period) * 2 * .pi)) / 2
    }

    /// Ease in and out over 0…1.
    static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

/// Redraws its content every frame with the current time. Holds still when Reduce Motion is on.
struct LoopView<Content: View>: View {
    @ViewBuilder var content: (Date) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in content(context.date) }
    }
}

private struct Rotating: ViewModifier {
    var period: Double

    func body(content: Content) -> some View {
        LoopView { date in content.rotationEffect(.degrees(Loop.phase(date, period: period) * 360)) }
    }
}

extension View {
    /// Turns the view a full circle every `period` seconds.
    func rotating(period: Double) -> some View { modifier(Rotating(period: period)) }
}

// MARK: - Shimmer

/// A soft light sweep across the view, used on the main call-to-action.
private struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LoopView { date in
                        // A 2.4 s sweep from -1 to 1.2, then 0.6 s of rest off the right edge.
                        let sweep = min(Loop.phase(date, period: 3) * 3 / 2.4, 1)
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45)
                            .offset(x: (-1 + 2.2 * Loop.ease(sweep)) * geo.size.width * 1.6)
                            .blendMode(.overlay)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - Breathing halo

/// A glow that softly breathes behind a ring while work is in progress.
struct BreathingHalo: View {
    var color: Color = Theme.accent

    var body: some View {
        LoopView { date in
            let breath = Loop.breath(date, period: 3.6)
            GeometryReader { geo in
                // Fade out fully before the frame's edge, so the glow never shows a rim.
                let radius = min(geo.size.width, geo.size.height) / 2
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.35), color.opacity(0.12), .clear],
                                         center: .center, startRadius: 0, endRadius: radius * 0.85))
            }
            .scaleEffect(0.92 + 0.2 * breath)
            .opacity(0.55 + 0.45 * breath)
        }
        .allowsHitTesting(false)
    }
}

/// A bright point that orbits a ring.
struct OrbitingSpark: View {
    var lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            LoopView { date in
                let angle = Loop.phase(date, period: 2.2) * 2 * .pi
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth * 0.55, height: lineWidth * 0.55)
                    .shadow(color: .white, radius: 8)
                    .shadow(color: Theme.accent, radius: 16)
                    .offset(x: r * cos(angle), y: r * sin(angle))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Celebration

/// A check that draws itself with a burst of sparkles, shown after a clean.
struct Celebration: View {
    var title: String
    var subtitle: String
    @State private var drawn = false
    @State private var burst = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                ForEach(0..<14, id: \.self) { i in
                    let angle = Double(i) / 14 * 2 * .pi
                    Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                        .font(.system(size: i.isMultiple(of: 2) ? 14 : 5))
                        .foregroundStyle(i.isMultiple(of: 3) ? Theme.lavender : Theme.accent)
                        .offset(x: burst ? cos(angle) * 120 : 0, y: burst ? sin(angle) * 120 : 0)
                        .opacity(burst ? 0 : 1)
                        .scaleEffect(burst ? 0.4 : 1.2)
                }
                Circle()
                    .fill(Theme.green.opacity(0.15))
                    .frame(width: 130, height: 130)
                    .scaleEffect(drawn ? 1 : 0.4)
                Circle()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Theme.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                CheckShape()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .frame(width: 52, height: 40)
            }
            .shadow(color: Theme.green.opacity(0.5), radius: 24)

            VStack(spacing: 6) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Theme.secondary)
            }
            .opacity(drawn ? 1 : 0)
            .offset(y: drawn ? 0 : 10)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { drawn = true }
            withAnimation(.easeOut(duration: 1.1).delay(0.25)) { burst = true }
        }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

// MARK: - Hover lift

private struct HoverLift: ViewModifier {
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hover ? 1.006 : 1)
            .shadow(color: .black.opacity(hover ? 0.3 : 0), radius: 18, y: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hover)
            .onHover { hover = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}
