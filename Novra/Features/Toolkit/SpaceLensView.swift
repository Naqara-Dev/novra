import SwiftUI

/// Which slice is highlighted. Kept apart from the page so hovering redraws only the ring.
@MainActor @Observable
final class LensHover {
    var id: String?
    private var pending: Task<Void, Never>?

    /// Rows highlight the ring only once the pointer rests, so scrolling past rows stays smooth.
    func rest(on id: String?) {
        pending?.cancel()
        guard let id else {
            pending = Task {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { self.id = nil }
            }
            return
        }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { self.id = id }
        }
    }

    func set(_ id: String?) {
        pending?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { self.id = id }
    }
}

struct LensSlice: Identifiable, Equatable {
    let id: String
    let name: String
    let size: Int64
    let start: Double
    let end: Double
    let color: Color
    let url: URL?
    let isFolder: Bool
}

/// The disk as a ring of slices: hover to see, click to dive in, tick to remove.
struct SpaceLensView: View {
    var onBack: () -> Void
    @State private var model = FolderExplorerModel(root: Cleaner.home)
    @State private var hover = LensHover()
    @State private var confirming = false

    private static let palette: [Color] = [0x3D7BF7, 0x7B61FF, 0x37B6FF, 0x32D583, 0xFF9F0A, 0xFF5A8A, 0xA9B8FF,
                                           0x4FC3A1, 0xFFB547, 0x2A44D2, 0x9B7BFF, 0x0EA5A4, 0xC48A5A, 0x8E9BC7]
        .map { Color(hex: $0) }

    private func makeSlices(_ entries: [FolderExplorerModel.Entry], total: Int64) -> [LensSlice] {
        guard total > 0 else { return [] }
        var result: [LensSlice] = []
        var angle = 0.0
        var other: Int64 = 0
        for (index, entry) in entries.enumerated() {
            let size = model.footprints[entry.id]?.size ?? 0
            guard size > 0 else { continue }
            let fraction = Double(size) / Double(total)
            if index < 13 && fraction >= 0.012 {
                result.append(LensSlice(id: entry.id, name: entry.url.lastPathComponent, size: size, start: angle,
                                        end: angle + fraction, color: Self.palette[index % Self.palette.count],
                                        url: entry.url, isFolder: entry.isFolder))
                angle += fraction
            } else {
                other += size
            }
        }
        if other > 0 {
            result.append(LensSlice(id: "__other__", name: "Everything else", size: other, start: angle, end: 1,
                                    color: .white.opacity(0.18), url: nil, isFolder: false))
        }
        return result
    }

    var body: some View {
        let entries = model.sortedEntries
        let total = entries.compactMap { model.footprints[$0.id]?.size }.sum
        let slices = makeSlices(entries, total: total)
        let colors = Dictionary(uniqueKeysWithValues: slices.map { ($0.id, $0.color) })
        let pending = model.entries.contains { model.footprints[$0.id] == nil }
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 8)
            HStack(alignment: .top, spacing: 28) {
                LensChart(slices: slices, total: total, folderName: model.current.lastPathComponent,
                          pending: pending, hover: hover, onOpen: dive)
                    .id(model.current)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .frame(width: 360, height: 360)
                    .padding(.top, 18)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(entries) { entry in
                            LensRow(entry: entry, footprint: model.footprints[entry.id],
                                    fraction: Double(model.footprints[entry.id]?.size ?? 0) / Double(max(total, 1)),
                                    color: colors[entry.id] ?? .white.opacity(0.2),
                                    isOn: model.selection.contains(entry.id),
                                    onToggle: { model.toggle(entry) },
                                    onOpen: { dive(into: entry.url) },
                                    onHover: { hover.rest(on: $0 ? entry.id : nil) })
                        }
                    }
                    .id(model.current)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 28)
            SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
        }
        .onAppear { if model.entries.isEmpty { model.load() } }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Remove selected items?", count: model.selection.count,
                                size: model.selectionSize, note: nil) { model.remove(toTrash: $0) }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconButton(systemName: "chevron.left", help: "Back to Toolkit", action: onBack)
            VStack(alignment: .leading, spacing: 4) {
                Text("Space Lens").font(.system(size: 22, weight: .bold))
                breadcrumbs
            }
            Spacer()
            if let report = model.report {
                Text(report.movedToTrash ? "Moved \(report.freed.byteString) to Trash" : "Freed \(report.freed.byteString)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.tertiary) }
                Button(index == 0 ? "Home" : url.lastPathComponent) {
                    hover.set(nil)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { model.jump(to: index) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: index == model.path.count - 1 ? .semibold : .regular))
                .foregroundStyle(index == model.path.count - 1 ? .white : Theme.secondary)
            }
        }
    }

    private func dive(into url: URL) {
        guard FileSizer.isDirectory(url) else { return }
        hover.set(nil)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { model.open(url) }
    }
}

// MARK: - Ring

private struct LensChart: View {
    var slices: [LensSlice]
    var total: Int64
    var folderName: String
    var pending: Bool
    var hover: LensHover
    var onOpen: (URL) -> Void

    var body: some View {
        let focused = slices.first { $0.id == hover.id }
        ZStack {
            ForEach(slices) { slice in
                let isHovered = hover.id == slice.id
                let mid = (slice.start + slice.end) / 2 * 2 * .pi - .pi / 2
                SliceShape(start: slice.start, end: slice.end, inner: 0.58)
                    .fill(slice.color)
                    .opacity(hover.id == nil || isHovered ? 1 : 0.4)
                    .offset(x: isHovered ? cos(mid) * 8 : 0, y: isHovered ? sin(mid) * 8 : 0)
                    .shadow(color: isHovered ? slice.color.opacity(0.6) : .clear, radius: 14)
                    .contentShape(SliceShape(start: slice.start, end: slice.end, inner: 0.58))
                    .onHover { hover.set($0 ? slice.id : nil) }
                    .onTapGesture { if slice.isFolder, let url = slice.url { onOpen(url) } }
            }

            VStack(spacing: 4) {
                Text(focused?.name ?? folderName)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).frame(maxWidth: 170)
                Text((focused?.size ?? total).byteString)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if pending {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Measuring").font(.system(size: 11)) }
                        .foregroundStyle(Theme.tertiary)
                } else if focused?.isFolder == true {
                    Text("Click to open").font(.system(size: 11)).foregroundStyle(Theme.lavender)
                }
            }
        }
        .drawingGroup(opaque: false)
    }
}

private struct SliceShape: Shape {
    var start: Double
    var end: Double
    var inner: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 10
        let gap = 0.004
        let a0 = Angle.degrees((start + gap) * 360 - 90)
        let a1 = Angle.degrees(max(start + gap, end - gap) * 360 - 90)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        path.addArc(center: center, radius: outer * inner, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - List row

/// One file or folder. Its hover highlight is local, so moving the pointer doesn't redraw the whole list.
private struct LensRow: View {
    var entry: FolderExplorerModel.Entry
    var footprint: Footprint?
    var fraction: Double
    var color: Color
    var isOn: Bool
    var onToggle: () -> Void
    var onOpen: () -> Void
    var onHover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckBox(isOn: isOn, action: onToggle)
            Circle().fill(color).frame(width: 8, height: 8)
            FileIcon(url: entry.url, size: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.url.lastPathComponent).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                    UsageBadge(url: entry.url, lastUsed: footprint?.lastUsed)
                }
                Capsule().fill(.white.opacity(0.06))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .scaleEffect(x: max(fraction, 0.004), y: 1, anchor: .leading)
                    }
            }
            SizeLabel(size: footprint?.size, tint: .white.opacity(0.85)).frame(width: 78, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(entry.isFolder ? Theme.tertiary : .clear)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.cardHover : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .onTapGesture { if entry.isFolder { onOpen() } }
    }
}
