import SwiftUI

// MARK: - Ring

/// Disk and scan meter: a dial of ticks that light up, with a thin glowing arc inside.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 18
    var colors: [Color] = Theme.ringColors
    @State private var shown: Double = 0

    var body: some View {
        RingDial(progress: shown, colors: colors.map { NSColor($0) }, thickness: lineWidth)
            .onAppear {
                withAnimation(.spring(response: 1.4, dampingFraction: 0.9).delay(0.1)) { shown = progress }
            }
            .onChange(of: progress) { _, new in
                withAnimation(.easeInOut(duration: 0.45)) { shown = new }
            }
    }
}

private struct RingDial: View, @preconcurrency Animatable {
    var progress: Double
    var colors: [NSColor]
    var thickness: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = max(0, min(progress, 1))
        ZStack {
            Canvas { ctx, size in
                let ticks = 90
                let side = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = side / 2
                let length = thickness * 0.85
                let lit = p * Double(ticks)
                for i in 0..<ticks {
                    let angle = Double(i) / Double(ticks) * 2 * .pi - .pi / 2
                    let fraction = Double(i) / Double(ticks)
                    // Partially lit tick at the edge of the fill, for a smooth sweep.
                    let amount = max(0, min(1, lit - Double(i)))
                    let a = CGPoint(x: center.x + cos(angle) * (outer - length), y: center.y + sin(angle) * (outer - length))
                    let b = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
                    var line = Path()
                    line.move(to: a)
                    line.addLine(to: b)
                    let width = max(2, side / 120)
                    ctx.stroke(line, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    if amount > 0 {
                        ctx.stroke(line, with: .color(Color(nsColor: color(at: fraction)).opacity(amount)),
                                   style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                }
            }
            .shadow(color: Color(nsColor: color(at: p)).opacity(0.45), radius: 12)

            // Inner arc that fades in from its start, so it never shows a seam.
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let inset = thickness * 1.55
                let radius = side / 2 - inset
                let headAngle = (p * 360 - 90) * .pi / 180
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.04), lineWidth: 3)
                        .padding(inset)
                    Circle()
                        .trim(from: 0, to: max(0.0001, p))
                        .stroke(
                            AngularGradient(
                                colors: [Color(nsColor: colors[0]).opacity(0)] + colors.map { Color(nsColor: $0) },
                                center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(p, 0.02))
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                    if p > 0.01 {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: .white, radius: 4)
                            .shadow(color: Color(nsColor: color(at: p)), radius: 12)
                            .offset(x: cos(headAngle) * radius, y: sin(headAngle) * radius)
                    }
                    // Soft glass disc in the middle.
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.05), .clear], center: .top, startRadius: 0, endRadius: side * 0.45))
                        .padding(inset + 10)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// Colour along the gradient at `t` (0...1).
    private func color(at t: Double) -> NSColor {
        guard colors.count > 1 else { return colors.first ?? .systemBlue }
        let scaled = max(0, min(1, t)) * Double(colors.count - 1)
        let index = min(Int(scaled), colors.count - 2)
        let local = scaled - Double(index)
        let from = colors[index].usingColorSpace(.sRGB) ?? colors[index]
        let to = colors[index + 1].usingColorSpace(.sRGB) ?? colors[index + 1]
        return from.blended(withFraction: local, of: to) ?? from
    }
}

struct SpinningRing: View {
    var lineWidth: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotating(period: 1.1)
                .shadow(color: Theme.accent.opacity(0.55), radius: 14)
        }
    }
}

// MARK: - Checkbox

enum CheckState { case off, on, mixed }

struct CheckBox: View {
    var state: CheckState
    var action: () -> Void

    init(_ state: CheckState, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    init(isOn: Bool, action: @escaping () -> Void) {
        self.init(isOn ? .on : .off, action: action)
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(state == .off ? Color.clear : Theme.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(state == .off ? Color.white.opacity(0.35) : .clear, lineWidth: 1.5)
                )
                .overlay {
                    if state != .off {
                        Image(systemName: state == .on ? "checkmark" : "minus")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .frame(width: 18, height: 18)
                .scaleEffect(state == .off ? 1 : 1.08)
                .shadow(color: state == .off ? .clear : Theme.accent.opacity(0.6), radius: 6)
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: state)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buttons

/// The bright pill button from Novra for Android ("Scan Device").
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }
}

private struct PillBody: View {
    var configuration: ButtonStyle.Configuration
    var prominent: Bool
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            .foregroundStyle(prominent ? Color(hex: 0x0B1131) : .white)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [.white, Color(hex: 0xDDE5FF)], startPoint: .leading, endPoint: .trailing))
                } else {
                    Capsule().fill(.white.opacity(0.08)).overlay(Capsule().strokeBorder(Theme.stroke))
                }
            }
            .shadow(color: prominent ? Theme.accent.opacity(hover ? 0.6 : 0.35) : .clear, radius: hover ? 24 : 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : hover ? 1.03 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .onHover { hover = $0 }
    }
}

struct AccentButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Capsule().fill(tint.gradient))
            .shadow(color: tint.opacity(0.4), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct IconButton: View {
    var systemName: String
    var help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? .white : Theme.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hover ? Theme.cardHover : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

// MARK: - Layout pieces

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hover ? Theme.cardHover.opacity(0.8) : Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(hover ? Theme.accent.opacity(0.35) : Theme.stroke)
            )
            .animation(.easeOut(duration: 0.2), value: hover)
            .onHover { hover = $0 }
    }
}

struct PageHeader<Trailing: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.lavender.opacity(0.85))
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct FileIcon: View {
    var url: URL
    var size: CGFloat = 28
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.2).fill(.white.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            if let cached = IconCache.cached(url, size: size) { image = cached; return }
            let path = url.path, side = size
            image = await Task.detached(priority: .userInitiated) { IconCache.render(path, size: side) }.value
        }
    }
}

/// Finder icons are slow to draw, so each one is rendered once into a bitmap and reused.
enum IconCache {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    private static func key(_ path: String, _ size: CGFloat) -> NSString { "\(Int(size))|\(path)" as NSString }

    static func cached(_ url: URL, size: CGFloat) -> NSImage? { cache.object(forKey: key(url.path, size)) }

    static func render(_ path: String, size: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let pixels = Int(size * 2)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)
        let image = NSImage(size: NSSize(width: size, height: size))
        if let bitmap, let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        cache.setObject(image, forKey: key(path, size))
        return image
    }
}

struct SizeLabel: View {
    var size: Int64?
    var tint: Color = Theme.orange

    var body: some View {
        Group {
            if let size {
                Text(size.byteString)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: Double(size)))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .animation(.snappy, value: size)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .frame(minWidth: 70, alignment: .trailing)
    }
}

struct InsightBadge: View {
    var insight: Insight

    private var tint: Color {
        switch insight.tone {
        case .needed: Theme.lavender
        case .safe: Theme.green
        case .unused: Theme.orange
        }
    }

    var body: some View {
        Label(insight.label, systemImage: insight.tone == .needed ? "lock.fill" : insight.tone == .safe ? "checkmark" : "moon.zzz.fill")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Shows what Novra knows about an item: a known role first, otherwise how long it has gone unused.
struct UsageBadge: View {
    var url: URL
    var lastUsed: Date?

    var body: some View {
        if let insight = PathHints.insight(for: url) {
            InsightBadge(insight: insight)
        } else {
            StaleBadge(date: lastUsed)
        }
    }
}

struct StaleBadge: View {
    var date: Date?
    /// Show regardless of the stale threshold in Settings (the caller already decided).
    var always = false

    var body: some View {
        if let date, always || date.isStale {
            Text("Not used for \(date.ageString)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.orange.opacity(0.14)))
                .lineLimit(1)
                .fixedSize()
                .help("Nothing inside was opened or changed since \(date.formatted(date: .abbreviated, time: .omitted)).")
        }
    }
}

struct RunningBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            LoopView { date in
                let pulse = Loop.breath(date, period: 1.8)
                Circle().fill(Theme.green).frame(width: 6, height: 6)
                    .scaleEffect(0.8 + 0.5 * pulse)
                    .opacity(0.6 + 0.4 * pulse)
            }
            .frame(width: 6, height: 6)
            Text("Running").font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Theme.green)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Theme.green.opacity(0.14)))
        .fixedSize()
    }
}

struct EmptyState: View {
    var icon: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.lavender)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom bar showing what is selected, with the action that removes it.
struct SelectionBar: View {
    var count: Int
    var size: Int64
    var actionTitle: String.LocalizationValue = "Remove"
    var disabled = false
    var action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "Nothing selected" : "\(count) selected")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(count)))
                Text("Nothing is deleted until you confirm.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Button(action: action) {
                Text(count == 0 || size == 0 ? String(localized: actionTitle) : "\(String(localized: actionTitle)) \(size.byteString)")
                    .contentTransition(.numericText(value: Double(size)))
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(count == 0 || disabled)
            .opacity(count == 0 || disabled ? 0.45 : 1)
        }
        .animation(.snappy, value: count)
        .animation(.snappy, value: size)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.6))
        .background(Color(hex: 0x0A1029).opacity(0.85))
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

// MARK: - Confirm & result sheets

struct ConfirmRemovalSheet: View {
    var title: LocalizedStringKey
    var count: Int
    var size: Int64
    var note: LocalizedStringKey?
    var allowTrashChoice = true
    var defaultToTrash = Prefs.defaultToTrash
    var onConfirm: (_ toTrash: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var toTrash = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white, Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 18, weight: .bold))
                    Text("\(count) items · \(size.byteString)")
                        .foregroundStyle(Theme.secondary)
                }
            }
            if let note {
                Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if allowTrashChoice {
                Picker("", selection: $toTrash) {
                    Text("Move to Trash (recoverable)").tag(true)
                    Text("Delete permanently").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if !toTrash && Prefs.defaultToTrash {
                    Label("Permanently deleted items cannot be restored.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.orange)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(toTrash || !allowTrashChoice ? "Remove" : "Delete permanently") {
                    dismiss()
                    onConfirm(allowTrashChoice ? toTrash : true)
                }
                .buttonStyle(AccentButtonStyle(tint: toTrash ? Theme.accent : Theme.red))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 440)
        .onAppear { toTrash = defaultToTrash }
        .foregroundStyle(.white)
        .background(Color(hex: 0x10173A))
    }
}

struct CleanResultBanner: View {
    var report: CleanReport
    var onEmptyTrash: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.movedToTrash ? "Moved \(report.freed.byteString) to the Trash" : "Freed \(report.freed.byteString)")
                    .font(.system(size: 13.5, weight: .semibold))
                if !report.inUse.isEmpty {
                    let apps = Set(report.inUse.values).sorted().prefix(3).joined(separator: ", ")
                    Text("Skipped \(report.inUse.count) item(s) still in use by \(apps). Quit it and clean again.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                }
                if !report.failed.isEmpty {
                    Text("\(report.failed.count) item(s) couldn't be removed. They may be protected.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                } else if report.movedToTrash && report.inUse.isEmpty {
                    Text("Empty the Trash when you're sure, to get the space back.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            if report.movedToTrash, let onEmptyTrash {
                Button("Empty Trash", action: onEmptyTrash).buttonStyle(PillButtonStyle(prominent: false))
            }
            IconButton(systemName: "xmark", help: "Dismiss", action: onDismiss)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.green.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.green.opacity(0.25)))
    }
}

// MARK: - Pickers

/// Pill-shaped segmented control with a sliding highlight, in place of the system pop-up menu.
struct PillPicker<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? .white : Theme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isOn {
                                Capsule().fill(Theme.accent.gradient)
                                    .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// Checkbox with a label, styled like the rest of Novra.
struct CheckToggle: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            CheckBox(isOn: isOn) { isOn.toggle() }
            Text(title).font(.system(size: 12)).foregroundStyle(isOn ? .white : Theme.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { isOn.toggle() } }
    }
}

/// Centers its content vertically, and scrolls instead of clipping when the window is too short.
struct CenteredScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
            }
            .scrollIndicators(.automatic)
        }
    }
}
