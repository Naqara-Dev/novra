import SwiftUI

/// One photo at a time: ← delete, → keep, ⌘Z undo. Nothing is deleted until the end.
struct SwipeView: View {
    var items: [PhotoItem]
    var onFinish: ([PhotoItem]) -> Void

    @State private var index = 0
    @State private var decisions: [(PhotoItem, Bool)] = []
    @State private var drag: CGSize = .zero
    @FocusState private var focused: Bool

    private var current: PhotoItem? { index < items.count ? items[index] : nil }
    private var toDelete: [PhotoItem] { decisions.filter { !$0.1 }.map(\.0) }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(hex: 0x060914).opacity(0.75)
            VStack(spacing: 22) {
                HStack {
                    Text("Swipe to Clean").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text("\(min(index + 1, items.count)) of \(items.count)").monospacedDigit().foregroundStyle(Theme.secondary)
                    Button("Done") { onFinish(toDelete) }.buttonStyle(PillButtonStyle(prominent: false))
                        .keyboardShortcut(.cancelAction)
                }
                if let item = current {
                    card(item)
                } else {
                    finished
                }
                if current != nil {
                    HStack(spacing: 18) {
                        circleButton("trash.fill", tint: Theme.red, label: "Delete  ←") { decide(false) }
                        circleButton("arrow.uturn.backward", tint: Theme.secondary, label: "Undo  ⌘Z") { undo() }
                            .disabled(decisions.isEmpty)
                        circleButton("heart.fill", tint: Theme.green, label: "Keep  →") { decide(true) }
                    }
                }
                Text("\(toDelete.count) marked for deletion · \(toDelete.map(\.size).sum.byteString)")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary).monospacedDigit()
            }
            .padding(36)
            .frame(maxWidth: 760)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { decide(false); return .handled }
        .onKeyPress(.rightArrow) { decide(true); return .handled }
        .background {
            Button("") { undo() }.keyboardShortcut("z", modifiers: .command).hidden()
        }
    }

    private func card(_ item: PhotoItem) -> some View {
        let offset = drag.width
        return PhotoThumb(item: item, maxPixel: 1400)
            .frame(maxWidth: 640, maxHeight: 440)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(offset < -40 ? Theme.red : offset > 40 ? Theme.green : .white.opacity(0.1), lineWidth: 3)
            }
            .overlay(alignment: .topLeading) {
                if offset < -40 { stamp("DELETE", Theme.red).padding(20) }
            }
            .overlay(alignment: .topTrailing) {
                if offset > 40 { stamp("KEEP", Theme.green).padding(20) }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text([item.size.byteString, item.date?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                }
                .padding(10)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .padding(14)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
            .offset(x: offset, y: drag.height * 0.2)
            .rotationEffect(.degrees(Double(offset) / 25))
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if value.translation.width < -120 { decide(false) }
                        else if value.translation.width > 120 { decide(true) }
                        else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero } }
                    }
            )
            .id(item.id)
            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.green)
            Text("All reviewed").font(.system(size: 20, weight: .bold))
            Text(toDelete.isEmpty ? "You kept everything." : "\(toDelete.count) to delete · \(toDelete.map(\.size).sum.byteString)")
                .foregroundStyle(Theme.secondary)
            if !toDelete.isEmpty {
                Button("Delete \(toDelete.count)") { onFinish(toDelete) }.buttonStyle(AccentButtonStyle(tint: Theme.red))
            }
        }
        .frame(height: 440)
    }

    private func stamp(_ text: String, _ tint: Color) -> some View {
        Text(LocalizedStringKey(text)).font(.system(size: 22, weight: .heavy)).foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 3))
            .rotationEffect(.degrees(text == "DELETE" ? -12 : 12))
    }

    private func circleButton(_ icon: String, tint: Color, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(tint.opacity(0.4)))
            }
            .buttonStyle(.plain)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
    }

    private func decide(_ keep: Bool) {
        guard let item = current else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            drag = CGSize(width: keep ? 600 : -600, height: 0)
        }
        decisions.append((item, keep))
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                drag = .zero
                index += 1
            }
        }
    }

    private func undo() {
        guard !decisions.isEmpty else { return }
        decisions.removeLast()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            index = max(index - 1, 0)
            drag = .zero
        }
    }
}
