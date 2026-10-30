import SwiftUI

struct SmartScanView: View {
    @Bindable var model: SmartScanModel
    @Environment(AppState.self) private var app
    @State private var confirming = false

    var body: some View {
        switch model.phase {
        case .idle: idle
        case .scanning: scanning
        case .results, .cleaning: results
        }
    }

    // MARK: Idle

    private var idle: some View {
        CenteredScroll {
        VStack(spacing: 26) {
            ZStack {
                ProgressRing(progress: app.disk.usedFraction, lineWidth: 20, colors: Theme.diskColors(app.disk.usedFraction))
                VStack(spacing: 6) {
                    Text(app.disk.free.byteString)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("free of \(app.disk.total.byteString)")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    if app.disk.usedFraction > 0.9 {
                        Text("Almost full")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.orange.opacity(0.14)))
                            .padding(.top, 4)
                    }
                }
                .reveal(delay: 0.25)
            }
            .frame(width: 220, height: 220)
            .reveal()

            VStack(spacing: 10) {
                Text("Novra finds it. You decide what goes.")
                    .font(.system(size: 26, weight: .bold))
                Text("One scan shows what is safe to clear. Nothing is removed until you confirm.")
                    .font(.system(size: 14)).foregroundStyle(Theme.lavender.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .reveal(delay: 0.12)

            Button { model.scan() } label: {
                Label("Scan My Mac", systemImage: "magnifyingglass")
            }
            .buttonStyle(PillButtonStyle())
            .shimmer()
            .keyboardShortcut(.defaultAction)
            .reveal(delay: 0.2)

            categoryStrip(sizes: false)
            if !app.hasFullDiskAccess { FullDiskAccessBanner().frame(maxWidth: 620).reveal(delay: 0.5) }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 30)
        }
    }

    // MARK: Scanning

    private var scanning: some View {
        CenteredScroll {
        VStack(spacing: 0) {
            ZStack {
                ProgressRing(progress: model.progress, lineWidth: 18)
                VStack(spacing: 4) {
                    (Text("\(Int(model.progress * 100))").font(.system(size: 50, weight: .bold, design: .rounded))
                        + Text("%").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(Theme.secondary))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: model.progress))
                        .animation(.snappy, value: Int(model.progress * 100))
                    Text(model.currentKind?.shortTitle ?? "Finishing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.lavender)
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: model.currentKind)
                }
            }
            .frame(width: 220, height: 220)
            .background { BreathingHalo().frame(width: 360, height: 360) }

            VStack(spacing: 8) {
                (Text("Found ").foregroundColor(Theme.secondary) + Text(model.found.byteString).foregroundColor(.white))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(value: Double(model.found)))
                    .animation(.snappy, value: model.found)
                Text(model.currentPath.isEmpty ? " " : URL(filePath: model.currentPath).tildePath)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
            }
            .padding(.top, 26)

            categoryStrip(sizes: true)
                .padding(.top, 26)

            Button("Stop") { model.cancel() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .padding(.top, 26)
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 30)
        }
    }

    private func categoryStrip(sizes: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 6), count: 6), spacing: 4) {
            ForEach(Array(JunkKind.allCases.enumerated()), id: \.element) { index, kind in
                CategoryTile(kind: kind, active: model.currentKind == kind,
                             done: sizes && model.completed.contains(kind),
                             size: sizes ? model.size(of: kind) : nil, showsSize: sizes)
                    .reveal(delay: 0.3 + Double(index) * 0.04)
            }
        }
        .frame(width: 6 * 84 + 5 * 6)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: "Found \(model.found.byteString)",
                               subtitle: "Honest numbers. Nothing counted twice. Pick what goes.") {
                        Button { model.scan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                    if let report = model.report {
                        CleanResultBanner(report: report,
                                          onEmptyTrash: { model.emptyTrash() },
                                          onDismiss: { withAnimation(.snappy) { model.report = nil } })
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if !app.hasFullDiskAccess { FullDiskAccessBanner() }
                    if model.groups.isEmpty {
                        EmptyState(icon: "sparkles", title: "Your Mac is spotless",
                                   message: "Nothing worth removing turned up. Check back in a few weeks.")
                            .frame(height: 300)
                    }
                    ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                        JunkGroupCard(model: model, group: group)
                            .reveal(delay: 0.08 + Double(index) * 0.06)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
            }
            SelectionBar(count: model.selectedItems.count, size: model.selectedSize, actionTitle: "Clean",
                         disabled: model.phase == .cleaning) { confirming = true }
        }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(
                title: "Clean selected junk?",
                count: model.selectedItems.count,
                size: model.selectedSize,
                note: model.selectedItems.contains { item in model.groups.first { $0.kind == .trash }?.items.contains(item) == true }
                    ? LocalizedStringKey("Items already in the Trash are deleted for good.") : nil
            ) { toTrash in model.clean(toTrash: toTrash) }
        }
    }
}

private struct CategoryTile: View {
    var kind: JunkKind
    var active: Bool
    var done: Bool
    var size: Int64?
    var showsSize: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(active ? kind.tint.opacity(0.25) : done ? kind.tint.opacity(0.14) : .white.opacity(0.04))
                    .frame(width: 40, height: 40)
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(active || done || !showsSize ? kind.tint : Theme.tertiary)
                    .symbolEffect(.pulse, isActive: active)
                    .symbolEffect(.bounce, value: done)
                if active {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(kind.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .modifier(Spin())
                }
            }
            .frame(width: 46, height: 46)
            .overlay(alignment: .topTrailing) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, Theme.green)
                        .background(Circle().fill(Color(hex: 0x0B1131)).padding(1))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(kind.shortTitle)
                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : Theme.secondary)
            if showsSize {
                Group {
                    if let size {
                        Text(size.byteString).foregroundStyle(.white)
                    } else if done {
                        Text("Clean").foregroundStyle(Theme.green)
                    } else {
                        Text(active ? "…" : " ").foregroundStyle(Theme.tertiary)
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
            }
        }
        .frame(width: 84)
        .padding(.vertical, showsSize ? 12 : 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(active ? .white.opacity(0.06) : .clear))
        .scaleEffect(active ? 1.04 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: active)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: done)
    }
}

private struct Spin: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { on = true } }
    }
}

private struct JunkGroupCard: View {
    @Bindable var model: SmartScanModel
    var group: JunkGroup

    private var isOpen: Bool { model.expanded.contains(group.kind) }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    CheckBox(model.state(of: group)) { model.toggle(group) }
                    Image(systemName: group.kind.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(group.kind.tint.gradient))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.kind.title).font(.system(size: 14.5, weight: .semibold))
                        Text(group.kind.subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    InfoButton(text: group.kind.impact)
                    SizeLabel(size: group.total)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) {
                        if isOpen { model.expanded.remove(group.kind) } else { model.expanded.insert(group.kind) }
                    }
                }

                if isOpen {
                    Divider().overlay(Theme.stroke)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(group.kind.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("What happens if you clean this").font(.system(size: 11.5, weight: .semibold))
                            Text(group.kind.impact).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(group.kind.tint.opacity(0.08)))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    LazyVStack(spacing: 0) {
                        ForEach(group.items) { item in
                            HStack(spacing: 12) {
                                CheckBox(isOn: model.selected.contains(item.id)) { model.toggle(item) }
                                if let url = item.urls.first { FileIcon(url: url, size: 22) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 13)).lineLimit(1)
                                    if let note = item.note {
                                        Text(note).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                SizeLabel(size: item.size, tint: .white.opacity(0.85))
                                if let url = item.urls.first {
                                    IconButton(systemName: "magnifyingglass", help: "Show in Finder") { SystemInfo.reveal(url) }
                                }
                                IconButton(systemName: "eye.slash", help: "Ignore: never show this again") { model.ignore(item) }
                            }
                            .padding(.horizontal, 16)
                            .padding(.leading, 32)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// Small (i) that explains the effect of cleaning, without opening the group.
struct InfoButton: View {
    var text: String
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.tertiary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What happens if you clean this").font(.system(size: 12, weight: .semibold))
                Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(Theme.lavender)
            VStack(alignment: .leading, spacing: 2) {
                Text("Give Novra Full Disk Access").font(.system(size: 13, weight: .semibold))
                Text("Lets Novra also look at Safari, Mail and Trash. Novra has no internet access; nothing leaves your Mac.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Open Settings") { SystemInfo.openFullDiskAccessSettings() }
                .buttonStyle(PillButtonStyle(prominent: false))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.25)))
    }
}
